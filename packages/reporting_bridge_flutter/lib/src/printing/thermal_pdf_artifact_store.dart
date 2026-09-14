import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

final class ThermalPdfArtifactStore {
  ThermalPdfArtifactStore._(this._directory);

  static const maximumPdfBytes = 50 * 1024 * 1024;
  static const _staleAge = Duration(days: 1);
  final Directory _directory;

  static Future<ThermalPdfArtifactStore> create() async {
    final root = await getTemporaryDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}reporting_bridge_flutter${Platform.pathSeparator}thermal_print_jobs');
    await directory.create(recursive: true);
    final store = ThermalPdfArtifactStore._(directory);
    await store.cleanupStale();
    return store;
  }

  Future<File> stage({
    required String jobId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty || bytes.length > maximumPdfBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Invalid PDF size.');
    }
    final safeId = jobId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${_directory.path}${Platform.pathSeparator}$safeId.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // The TTL cleanup provides a second chance after process interruption.
    }
  }

  Future<void> cleanupStale() async {
    final cutoff = DateTime.now().subtract(_staleAge);
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        if ((await entity.stat()).modified.isBefore(cutoff)) await entity.delete();
      } on FileSystemException {
        // A concurrent job owns this file or the cache was already cleared.
      }
    }
  }
}
