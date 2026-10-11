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
  BridgeTemplateThumbnailStore({required this.cacheRoot});

  final Directory cacheRoot;
  static const maxImageBytes = 2 * 1024 * 1024;
  static const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  static const _pngIend = <int>[0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];
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

  static bool _looksLikePng(List<int> png) {
    if (png.length < 33 || png.length > maxImageBytes) return false;
    for (var i = 0; i < _pngSignature.length; i++) {
      if (png[i] != _pngSignature[i]) return false;
    }
    for (var i = 0; i < _pngIend.length; i++) {
      if (png[png.length - _pngIend.length + i] != _pngIend[i]) return false;
    }
    return true;
  }

  Future<Uint8List?> read(CachedTemplate template) async {
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
      return _looksLikePng(bytes) ? bytes : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(CachedTemplate template, Uint8List png) async {
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
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  /// Remove only obsolete sibling PNGs, never JSON, other files, or symlinks.
  Future<void> deleteObsolete(Iterable<CachedTemplate> activeTemplates) async {
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
