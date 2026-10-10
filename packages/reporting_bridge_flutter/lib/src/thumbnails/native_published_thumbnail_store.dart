import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import 'native_thumbnail_crypto.dart';

const int _maxImageBytes = 2 * 1024 * 1024;
const int _maxImagesPerIdentity = 64;
const int _maxBytesPerIdentity = 16 * 1024 * 1024;
const int _maxBytesGlobal = 128 * 1024 * 1024;
const int _envelopeBytes = 5 + 12 + 16;

final class TrustedThumbnailScope {
  TrustedThumbnailScope({
    required Uri apiBase,
    required String tenantId,
    required String userId,
    required String systemCode,
    required String templateCode,
  }) : apiBase = normalizeBridgeApiBaseUrl(apiBase),
       tenantId = _required(tenantId, 'tenantId'),
       userId = _required(userId, 'userId'),
       systemCode = _required(systemCode, 'systemCode'),
       templateCode = _required(templateCode, 'templateCode');

  final Uri apiBase;
  final String tenantId;
  final String userId;
  final String systemCode;
  final String templateCode;

  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, String>{
            'apiBase': apiBase.toString(),
            'tenantId': tenantId,
            'userId': userId,
            'systemCode': systemCode,
            'templateCode': templateCode,
          }),
        ),
      )
      .toString();

  String get identityFingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, String>{
            'apiBase': apiBase.toString(),
            'tenantId': tenantId,
            'userId': userId,
            'systemCode': systemCode,
          }),
        ),
      )
      .toString();

  TrustedThumbnailScope forTemplateCode(String value) => TrustedThumbnailScope(
    apiBase: apiBase,
    tenantId: tenantId,
    userId: userId,
    systemCode: systemCode,
    templateCode: value,
  );

  String associatedIdentity(BridgePublishedThumbnail ref) =>
      '$fingerprint:${ref.versionNo}:${ref.contentHash}:${ref.mimeType}';
}

abstract interface class ThumbnailKeyProvider {
  Future<Uint8List?> loadOrCreateKey();
}

final class FlutterSecureThumbnailKeyProvider implements ThumbnailKeyProvider {
  FlutterSecureThumbnailKeyProvider({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _keyName = 'urb.published-thumbnail.aes256gcm.v1';
  final FlutterSecureStorage _storage;
  Future<Uint8List?>? _inFlight;

  @override
  Future<Uint8List?> loadOrCreateKey() =>
      _inFlight ??= _loadOrCreate().whenComplete(() => _inFlight = null);

  Future<Uint8List?> _loadOrCreate() async {
    try {
      final stored = await _storage.read(key: _keyName);
      if (stored != null) {
        final decoded = base64.decode(stored);
        return decoded.length == 32 ? Uint8List.fromList(decoded) : null;
      }
      final key = Uint8List.fromList(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      );
      await _storage.write(key: _keyName, value: base64.encode(key));
      final verified = await _storage.read(key: _keyName);
      if (verified == null ||
          !constantTimeBytesEqual(base64.decode(verified), key)) {
        return null;
      }
      return key;
    } on Object {
      return null;
    }
  }
}

final class ThumbnailStoreStats {
  const ThumbnailStoreStats({
    required this.imageCount,
    required this.totalBytes,
  });
  final int imageCount;
  final int totalBytes;
}

final class NativePublishedThumbnailStore {
  NativePublishedThumbnailStore({
    required Directory root,
    required ThumbnailKeyProvider keyProvider,
    NativeThumbnailCrypto? crypto,
    DateTime Function()? clock,
    bool? nativeEnabled,
  }) : _root = root,
       _keyProvider = keyProvider,
       _crypto = crypto ?? NativeThumbnailCrypto(),
       _clock = clock ?? DateTime.now,
       _nativeEnabled = nativeEnabled ?? _isSupportedNative;

  final Directory _root;
  final ThumbnailKeyProvider _keyProvider;
  final NativeThumbnailCrypto _crypto;
  final DateTime Function() _clock;
  final bool _nativeEnabled;

  static bool get _isSupportedNative =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<NativePublishedThumbnailStore> createDefault() async {
    if (kIsWeb) {
      return NativePublishedThumbnailStore(
        root: Directory('.'),
        keyProvider: FlutterSecureThumbnailKeyProvider(),
        nativeEnabled: false,
      );
    }
    final directory = await getApplicationSupportDirectory();
    return NativePublishedThumbnailStore(
      root: Directory('${directory.path}/urb/published-thumbnails'),
      keyProvider: FlutterSecureThumbnailKeyProvider(),
    );
  }

  Future<Uint8List?> read(
    TrustedThumbnailScope scope,
    BridgePublishedThumbnail ref,
  ) async {
    if (!_nativeEnabled || !ref.available) return null;
    final file = _fileFor(scope, ref);
    if (!await file.exists()) return null;
    final key = await _safeKey();
    if (key == null) return null;
    try {
      final encrypted = await file.readAsBytes();
      final clear = await _crypto.decrypt(
        keyBytes: key,
        encryptedBytes: encrypted,
        associatedIdentity: scope.associatedIdentity(ref),
      );
      if (!_isPng(clear) || clear.length > _maxImageBytes) {
        await file.delete();
        return null;
      }
      await file.setLastModified(_clock());
      return clear;
    } on Object {
      try {
        await file.delete();
      } on Object {
        // A corrupt entry remains inaccessible and is retried as a miss.
      }
      return null;
    }
  }

  Future<void> write(
    TrustedThumbnailScope scope,
    BridgePublishedThumbnail ref,
    Uint8List bytes,
  ) async {
    if (!_nativeEnabled) return;
    if (!ref.available) {
      throw ArgumentError.value(
        ref.available,
        'ref.available',
        'Cannot persist an unavailable image.',
      );
    }
    if (bytes.isEmpty || bytes.length > _maxImageBytes || !_isPng(bytes)) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'Expected a PNG no larger than 2 MiB.',
      );
    }
    if (await read(scope, ref) != null) return;
    final key = await _safeKey();
    if (key == null) return;
    final target = _fileFor(scope, ref);
    final encrypted = await _crypto.encrypt(
      keyBytes: key,
      clearBytes: bytes,
      associatedIdentity: scope.associatedIdentity(ref),
    );
    await target.parent.create(recursive: true);
    final temp = File(
      '${target.path}.tmp-${_clock().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
    );
    try {
      await temp.writeAsBytes(encrypted, flush: true);
      await temp.rename(target.path);
      await target.setLastModified(_clock());
    } finally {
      if (await temp.exists()) await temp.delete();
    }
    await _enforceQuotas(scope.fingerprint);
  }

  Future<void> invalidateScope(TrustedThumbnailScope scope) async {
    if (!_nativeEnabled || !await _root.exists()) return;
    for (final entry in await _entries()) {
      if (entry.scopeHash == scope.fingerprint) await entry.file.delete();
    }
  }

  Future<ThumbnailStoreStats> stats() async {
    if (!_nativeEnabled) {
      return const ThumbnailStoreStats(imageCount: 0, totalBytes: 0);
    }
    final entries = await _entries();
    return ThumbnailStoreStats(
      imageCount: entries.length,
      totalBytes: entries.fold<int>(0, (sum, entry) => sum + entry.clearBytes),
    );
  }

  File _fileFor(
    TrustedThumbnailScope scope,
    BridgePublishedThumbnail ref,
  ) => File(
    '${_root.path}/${scope.fingerprint}/${ref.versionNo}_${ref.contentHash}.bin',
  );

  Future<Uint8List?> _safeKey() async {
    try {
      final key = await _keyProvider.loadOrCreateKey();
      return key?.length == 32 ? key : null;
    } on Object {
      return null;
    }
  }

  Future<void> _enforceQuotas(String newScopeHash) async {
    final entries = await _entries();
    final scoped =
        entries.where((entry) => entry.scopeHash == newScopeHash).toList()
          ..sort((a, b) => a.modified.compareTo(b.modified));
    var scopedBytes = scoped.fold<int>(
      0,
      (sum, entry) => sum + entry.clearBytes,
    );
    while (scoped.length > _maxImagesPerIdentity ||
        scopedBytes > _maxBytesPerIdentity) {
      final oldest = scoped.removeAt(0);
      scopedBytes -= oldest.clearBytes;
      await oldest.file.delete();
    }

    final global = await _entries()
      ..sort((a, b) => a.modified.compareTo(b.modified));
    var globalBytes = global.fold<int>(
      0,
      (sum, entry) => sum + entry.clearBytes,
    );
    while (globalBytes > _maxBytesGlobal && global.isNotEmpty) {
      final oldest = global.removeAt(0);
      globalBytes -= oldest.clearBytes;
      await oldest.file.delete();
    }
  }

  Future<List<_StoredEntry>> _entries() async {
    if (!await _root.exists()) return <_StoredEntry>[];
    final result = <_StoredEntry>[];
    await for (final entity in _root.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.bin')) continue;
      try {
        final relative = entity.path
            .substring(_root.path.length + 1)
            .split(Platform.pathSeparator);
        if (relative.length != 2 ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(relative.first)) {
          continue;
        }
        final size = await entity.length();
        result.add(
          _StoredEntry(
            file: entity,
            scopeHash: relative.first,
            clearBytes: max(0, size - _envelopeBytes),
            modified: await entity.lastModified(),
          ),
        );
      } on FileSystemException {
        // Concurrent deletion is harmless during quota accounting.
      }
    }
    return result;
  }
}

final class _StoredEntry {
  const _StoredEntry({
    required this.file,
    required this.scopeHash,
    required this.clearBytes,
    required this.modified,
  });
  final File file;
  final String scopeHash;
  final int clearBytes;
  final DateTime modified;
}

bool _isPng(List<int> bytes) =>
    bytes.length >= 8 &&
    const <int>[
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
    ].asMap().entries.every((e) => bytes[e.key] == e.value);

String _required(String value, String name) {
  final result = value.trim();
  if (result.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  return result;
}

bool constantTimeBytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var different = 0;
  for (var i = 0; i < left.length; i++) {
    different |= left[i] ^ right[i];
  }
  return different == 0;
}
