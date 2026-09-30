import 'dart:io';
import 'dart:typed_data';

/// Stores Presenter resource bytes by their lowercase SHA-256 digest.
class PresenterResourceCacheStore {
  PresenterResourceCacheStore({
    required this.cacheRoot,
    this.maxEntryBytes = 5 * 1024 * 1024,
  }) : assert(maxEntryBytes >= 0);

  final Directory cacheRoot;
  final int maxEntryBytes;

  Future<Uint8List?> read(String sha256) async {
    _validateKey(sha256);
    final file = File('${cacheRoot.path}/$sha256');
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    if (await file.length() > maxEntryBytes) {
      throw StateError('Resource cache entry exceeds $maxEntryBytes bytes.');
    }
    return file.readAsBytes();
  }

  Future<void> write(String sha256, Uint8List bytes) async {
    _validateKey(sha256);
    if (bytes.length > maxEntryBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'Resource cache entry exceeds $maxEntryBytes bytes.',
      );
    }

    await cacheRoot.create(recursive: true);
    final destination = File('${cacheRoot.path}/$sha256');
    final existingType = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );
    if (existingType != FileSystemEntityType.notFound &&
        existingType != FileSystemEntityType.file) {
      throw FileSystemException('Resource cache path is not a file.');
    }

    final stagingDirectory = await cacheRoot.createTemp('.resource-cache-');
    final staged = File('${stagingDirectory.path}/entry');
    try {
      await staged.writeAsBytes(bytes, flush: true);
      await staged.rename(destination.path);
    } on Object {
      if (await staged.exists()) await staged.delete();
      rethrow;
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> clear() async {
    if (await cacheRoot.exists()) {
      await cacheRoot.delete(recursive: true);
    }
  }

  void _validateKey(String sha256) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw ArgumentError.value(sha256, 'sha256', 'Invalid SHA-256 key.');
    }
  }
}
