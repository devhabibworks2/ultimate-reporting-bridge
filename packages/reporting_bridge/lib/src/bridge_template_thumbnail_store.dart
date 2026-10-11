import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bridge_template_cache.dart';

/// Plain, private, published-version PNG files beside hashed template JSONs.
///
/// The caller supplies the already-authorized, query-scoped catalog directory.
/// Reads never fetch from the network and writes cannot change catalog identity.
final class BridgeTemplateThumbnailStore {
  BridgeTemplateThumbnailStore({
    required this.cacheRoot,
    Directory? scopeRoot,
    Directory? globalRoot,
    this.maxImagesPerScope = 64,
    this.maxBytesPerScope = 16 * 1024 * 1024,
    this.maxGlobalBytes = 128 * 1024 * 1024,
  }) : scopeRoot = scopeRoot ?? cacheRoot,
       globalRoot = globalRoot ?? scopeRoot ?? cacheRoot;

  final Directory cacheRoot;

  /// Trusted user/tenant/system cache root, shared by all filter catalogs.
  final Directory scopeRoot;

  /// Trusted bridge cache root, shared by all identities.
  final Directory globalRoot;
  final int maxImagesPerScope;
  final int maxBytesPerScope;
  final int maxGlobalBytes;
  static const maxImageBytes = 2 * 1024 * 1024;

  static String _canonicalPath(Directory value) {
    final path = value.absolute.uri.normalizePath().toFilePath();
    return path.length > 1 && path.endsWith(Platform.pathSeparator)
        ? path.substring(0, path.length - 1)
        : path;
  }

  static bool _inside(Directory child, Directory ancestor) {
    final a = _canonicalPath(ancestor);
    final c = _canonicalPath(child);
    return c == a || c.startsWith('$a${Platform.pathSeparator}');
  }

  Future<void> _requireTrustedRoots() async {
    if (!_inside(cacheRoot, scopeRoot) || !_inside(scopeRoot, globalRoot)) {
      throw StateError(
        'Thumbnail cache path is outside trusted identity scope.',
      );
    }
    var cursor = cacheRoot;
    final global = _canonicalPath(globalRoot);
    while (true) {
      if (await FileSystemEntity.type(cursor.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError(
          'Thumbnail storage cannot traverse symlinked directories.',
        );
      }
      if (_canonicalPath(cursor) == global) break;
      cursor = cursor.parent;
    }
  }

  static const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  static final _candidate = RegExp(
    r'^tpl_[0-9a-f]{64}_[1-9][0-9]*_[0-9a-f]{64}\.png$',
  );

  File? _file(CachedTemplate template) {
    final thumbnail = template.publishedThumbnail;
    if (thumbnail == null || !thumbnail.available) return null;
    final code = template.durableTemplateCode;
    if (code == null || code.trim().isEmpty) return null;
    final digest = sha256.convert(utf8.encode(code)).toString();
    return File(
      '${cacheRoot.path}/tpl_${digest}_${thumbnail.versionNo}_${thumbnail.contentHash}.png',
    );
  }

  static int _word(List<int> data, int offset) =>
      (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];

  static int _crc32(List<int> data, int start, int end) {
    var crc = 0xffffffff;
    for (var i = start; i < end; i++) {
      crc ^= data[i];
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  /// Structural PNG parser: chunk boundaries, sizes and CRCs must all agree.
  static bool _looksLikePng(List<int> png) {
    if (png.length < 57 || png.length > maxImageBytes) return false;
    for (var i = 0; i < _pngSignature.length; i++) {
      if (png[i] != _pngSignature[i]) return false;
    }
    var position = _pngSignature.length;
    var chunkCount = 0;
    var sawIdat = false;
    while (position + 12 <= png.length) {
      final length = _word(png, position);
      if (length < 0 ||
          length > maxImageBytes ||
          position + 12 + length > png.length) {
        return false;
      }
      final end = position + 12 + length;
      final type = String.fromCharCodes(
        png.sublist(position + 4, position + 8),
      );
      if (chunkCount == 0) {
        if (type != 'IHDR' || length != 13) return false;
        final width = _word(png, position + 8);
        final height = _word(png, position + 12);
        if (width < 1 || height < 1 || width > 640 || height > 640) {
          return false;
        }
      }
      if (_crc32(png, position + 4, end - 4) != _word(png, end - 4)) {
        return false;
      }
      if (type == 'IDAT') sawIdat = true;
      if (type == 'IEND') {
        return length == 0 && sawIdat && end == png.length;
      }
      position = end;
      chunkCount++;
    }
    return false;
  }

  Future<Uint8List?> read(CachedTemplate template) async {
    try {
      await _requireTrustedRoots();
    } on StateError {
      return null;
    }
    final file = _file(template);
    if (file == null || !await cacheRoot.exists()) return null;
    try {
      if (await FileSystemEntity.type(cacheRoot.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file) {
        return null;
      }
      if (await file.length() > maxImageBytes) return null;
      final bytes = await file.readAsBytes();
      if (!_looksLikePng(bytes)) return null;
      try {
        await file.setLastModified(DateTime.now().toUtc());
      } on FileSystemException {
        // A readable offline image remains valid even on read-only storage.
      }
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(
    CachedTemplate template,
    Uint8List png, {
    String? expectedBytesSha256,
  }) async {
    await _requireTrustedRoots();
    if (expectedBytesSha256 != null &&
        (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedBytesSha256) ||
            sha256.convert(png).toString() != expectedBytesSha256)) {
      throw const FormatException(
        'Published image bytes failed SHA-256 verification.',
      );
    }
    final file = _file(template);
    if (file == null) {
      throw StateError('A valid published thumbnail identity is required.');
    }
    if (!_looksLikePng(png)) {
      throw const FormatException('Invalid or oversized PNG.');
    }
    await cacheRoot.create(recursive: true);
    if (await FileSystemEntity.type(cacheRoot.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw FileSystemException('Catalog root must be a regular directory.');
    }
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('Cannot overwrite a symlinked image.');
    }
    final current = await read(template);
    if (current != null && _equalBytes(current, png)) return;
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
    );
    try {
      await tmp.writeAsBytes(png, flush: true);
      if (!_looksLikePng(await tmp.readAsBytes())) {
        throw const FormatException('Staged PNG failed validation.');
      }
      await tmp.rename(file.path);
      await _enforceQuota(file.path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  Future<List<({File file, int size, DateTime modified})>> _imagesIn(
    Directory root,
  ) async {
    if (!await root.exists()) return [];
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Thumbnail quota root must not be a symlink.');
    }
    final images = <({File file, int size, DateTime modified})>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File ||
          !_candidate.hasMatch(entity.uri.pathSegments.last)) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) continue;
        images.add((file: entity, size: stat.size, modified: stat.modified));
      } on FileSystemException {
        continue;
      }
    }
    return images;
  }

  Future<void> _pruneQuota(
    Directory root, {
    required int maxCount,
    required int maxBytes,
    required String protect,
  }) async {
    final images = await _imagesIn(root);
    images.sort((a, b) {
      if (a.file.path == protect) return 1;
      if (b.file.path == protect) return -1;
      final byTime = a.modified.compareTo(b.modified);
      return byTime != 0 ? byTime : a.file.path.compareTo(b.file.path);
    });
    var count = images.length;
    var bytes = images.fold<int>(0, (total, image) => total + image.size);
    for (final image in images) {
      if (count <= maxCount && bytes <= maxBytes) break;
      if (image.file.path == protect) {
        throw StateError('New PNG alone exceeds the cache budget.');
      }
      try {
        await image.file.delete();
        count--;
        bytes -= image.size;
      } on FileSystemException {
        // Fail closed: make the budget failure observable to the caller.
        rethrow;
      }
    }
  }

  Future<void> _enforceQuota(String protectedPath) async {
    if (maxImagesPerScope < 1 || maxBytesPerScope < 1 || maxGlobalBytes < 1) {
      throw StateError('Thumbnail quotas must be positive.');
    }
    await _pruneQuota(
      scopeRoot,
      maxCount: maxImagesPerScope,
      maxBytes: maxBytesPerScope,
      protect: protectedPath,
    );
    await _pruneQuota(
      globalRoot,
      maxCount: 0x7fffffff,
      maxBytes: maxGlobalBytes,
      protect: protectedPath,
    );
  }

  /// Remove only obsolete sibling PNGs, never JSON, other files, or symlinks.
  Future<void> deleteObsolete(Iterable<CachedTemplate> activeTemplates) async {
    await _requireTrustedRoots();
    if (!await cacheRoot.exists()) return;
    if (await FileSystemEntity.type(cacheRoot.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    final keep = activeTemplates
        .map(_file)
        .whereType<File>()
        .map((file) => file.path)
        .toSet();
    await for (final entity in cacheRoot.list(followLinks: false)) {
      if (entity is! File ||
          !_candidate.hasMatch(entity.uri.pathSegments.last) ||
          keep.contains(entity.path)) {
        continue;
      }
      await entity.delete();
    }
  }

  static bool _equalBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
