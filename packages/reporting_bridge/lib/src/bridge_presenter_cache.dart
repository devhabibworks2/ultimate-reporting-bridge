import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'bridge_cache_namespace.dart';
import 'bridge_http_fetch.dart';
import 'bridge_presenter_bundle_contract.dart';
import 'bridge_runtime_error.dart';
import 'bridge_semantic_version.dart';

class PresenterCacheManifest {
  const PresenterCacheManifest({
    required this.bundleVersion,
    required this.devVersion,
    required this.rootPath,
    this.presenterVersion,
    this.updatedAt,
    this.syncedAt,
  });

  final String bundleVersion;
  final int devVersion;
  final String rootPath;
  final String? presenterVersion;
  final DateTime? updatedAt;
  final DateTime? syncedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'bundleVersion': bundleVersion,
      'devVersion': devVersion,
      'rootPath': rootPath,
      if (presenterVersion != null) 'presenterVersion': presenterVersion,
      if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      if (syncedAt != null) 'syncedAt': syncedAt!.toUtc().toIso8601String(),
    };
  }
}

class RemotePresenterManifest {
  const RemotePresenterManifest({
    required this.presenterVersion,
    required this.bundleVersion,
    required this.devVersion,
    required this.downloadUrl,
    required this.available,
    required this.enforceUpdate,
    this.updatedAt,
  });

  final String presenterVersion;
  final String bundleVersion;
  final int devVersion;
  final String? downloadUrl;
  final bool available;
  final bool enforceUpdate;
  final DateTime? updatedAt;
}

class PresenterCacheService {
  PresenterCacheService({
    required this.presenterRoot,
    HttpClient Function()? httpClientFactory,
    bool closeClientAfterRequest = true,
  }) : _http = BridgeHttpFetch(
         httpClientFactory: httpClientFactory,
         closeClientAfterRequest: closeClientAfterRequest,
       );

  final Directory presenterRoot;
  final BridgeHttpFetch _http;

  static const String _fallbackManifestPath = 'presenter/bundles/manifest';
  static const String _manifestFileName = 'presenter_manifest.json';
  static const String _offlineBaseHref = '/UltimateReport/apps/presenter/';

  File get indexFile => File('${presenterRoot.path}/index.html');
  File get manifestFile =>
      File('${presenterRoot.parent.path}/$_manifestFileName');

  Future<bool> isReady() async {
    if (!await presenterRoot.exists() || !await _isNonEmptyFile(manifestFile)) {
      return false;
    }
    return _isBundleSiteReady(presenterRoot);
  }

  Future<bool> supportsCurrentLifecycleContract() async {
    if (!await isReady()) return false;
    return _containsAllMarkers(
      File('${presenterRoot.path}/main.dart.js'),
      PresenterBundleContract.requiredJavaScriptMarkers,
    );
  }

  Future<bool> _isBundleSiteReady(Directory root) async {
    if (!await _isNonEmptyFile(File('${root.path}/index.html'))) return false;

    for (final path in PresenterBundleContract.requiredRuntimeFiles) {
      if (!await _isNonEmptyFile(File('${root.path}/$path'))) return false;
    }

    var assetManifestReady = false;
    for (final path in PresenterBundleContract.assetManifestPaths) {
      if (await _isNonEmptyFile(File('${root.path}/$path'))) {
        assetManifestReady = true;
        break;
      }
    }
    if (!assetManifestReady) return false;

    return true;
  }

  Future<bool> _isNonEmptyFile(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _containsAllMarkers(
    File file,
    List<String> requiredMarkers,
  ) async {
    final missing = requiredMarkers.toSet();
    if (missing.isEmpty) return true;
    final overlap = requiredMarkers.fold<int>(
      0,
      (length, marker) => marker.length > length ? marker.length : length,
    );
    var carry = '';
    try {
      await for (final chunk in file.openRead().transform(utf8.decoder)) {
        final searchable = '$carry$chunk';
        missing.removeWhere((marker) => searchable.contains(marker));
        if (missing.isEmpty) return true;
        carry = searchable.length < overlap
            ? searchable
            : searchable.substring(searchable.length - overlap);
      }
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    }
    return false;
  }

  Future<PresenterCacheManifest> requireReady({
    required String bundleVersion,
    required int devVersion,
    String? presenterVersion,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) async {
    if (!await isReady()) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.offlineAssetsNotReady,
        'Cached Presenter site is incomplete or missing required assets.',
      );
    }
    return PresenterCacheManifest(
      bundleVersion: bundleVersion,
      devVersion: devVersion,
      rootPath: presenterRoot.path,
      presenterVersion: presenterVersion,
      updatedAt: updatedAt,
      syncedAt: syncedAt,
    );
  }

  Future<PresenterCacheManifest> syncPresenterSite({
    required String? bundleManifestUrl,
    required String? apiBaseUrl,
    Map<String, String> headers = const <String, String>{},
    void Function(double progress)? onProgress,
  }) async {
    void report(num value) =>
        onProgress?.call(value.clamp(0.0, 1.0).toDouble());

    report(0);
    final manifestUri = _requiredManifestUri(
      bundleManifestUrl: bundleManifestUrl,
      apiBaseUrl: apiBaseUrl,
    );
    final remote = await fetchRemoteManifest(
      bundleManifestUrl: bundleManifestUrl,
      apiBaseUrl: apiBaseUrl,
      headers: headers,
    );
    report(0.05);
    if (!remote.available) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.offlineAssetsNotReady,
        'Presenter bundle is not available from manifest endpoint.',
      );
    }
    final rawDownloadUrl = remote.downloadUrl;
    if (rawDownloadUrl == null || rawDownloadUrl.isEmpty) {
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Presenter manifest is missing downloadUrl for ${remote.bundleVersion}.',
      );
    }

    final downloadUri = _resolveDownloadUri(manifestUri, rawDownloadUrl);
    final zipBytes = await _http.getBytes(
      downloadUri,
      headers: headers,
      onProgress: (received, total) {
        if (total != null && total > 0) {
          final ratio = (received / total).clamp(0.0, 1.0);
          report(0.05 + (ratio * 0.75));
        } else if (received > 0) {
          report(0.1);
        }
      },
    );
    report(0.82);
    final staging = await _extractBundleToStaging(zipBytes);
    report(0.94);

    final syncedAt = DateTime.now().toUtc();
    final manifest = PresenterCacheManifest(
      presenterVersion: remote.presenterVersion,
      bundleVersion: remote.bundleVersion,
      devVersion: remote.devVersion,
      rootPath: presenterRoot.path,
      updatedAt: remote.updatedAt,
      syncedAt: syncedAt,
    );
    final manifestPayload = jsonEncode(<String, dynamic>{
      ...manifest.toMap(),
      'manifestUrl': manifestUri.toString(),
      'downloadUrl': downloadUri.toString(),
    });
    await _activateStaging(staging, manifestPayload);
    report(1);
    return manifest;
  }

  Future<RemotePresenterManifest> fetchRemoteManifest({
    required String? bundleManifestUrl,
    required String? apiBaseUrl,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final manifestUri = _resolveManifestUri(
      bundleManifestUrl: bundleManifestUrl,
      apiBaseUrl: apiBaseUrl,
    );
    if (manifestUri == null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'bundleManifestUrl or apiBaseUrl is required for presenter sync.',
      );
    }

    final manifestPayload = await _http.getJsonObject(
      manifestUri,
      headers: headers,
      notValidJsonMessage:
          'Manifest response from $manifestUri is not valid JSON.',
    );
    final data = unwrapBridgeEnvelopeData(manifestPayload);
    final available = data['available'] as bool? ?? true;
    final presenterVersion = data['presenterVersion']?.toString().trim();
    final bundleVersion = data['bundleVersion']?.toString().trim();
    final devVersion = _asInt(data['devVersion']);
    final rawDownloadUrl = data['downloadUrl']?.toString();
    final updatedAt = DateTime.tryParse(data['updatedAt']?.toString() ?? '');
    if (presenterVersion == null ||
        presenterVersion.isEmpty ||
        BridgeSemanticVersion.tryParse(presenterVersion) == null ||
        bundleVersion == null ||
        bundleVersion.isEmpty ||
        devVersion == null) {
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Presenter manifest requires semantic presenterVersion, '
        'bundleVersion, and devVersion: $data',
      );
    }
    return RemotePresenterManifest(
      presenterVersion: presenterVersion,
      bundleVersion: bundleVersion,
      devVersion: devVersion,
      downloadUrl: rawDownloadUrl,
      available: available,
      enforceUpdate: data['enforceUpdate'] as bool? ?? false,
      updatedAt: updatedAt,
    );
  }

  Future<void> clearPresenterCache() async {
    if (await presenterRoot.exists()) {
      await presenterRoot.delete(recursive: true);
    }
    if (await manifestFile.exists()) {
      await manifestFile.delete();
    }
  }

  Future<void> normalizeCachedPresenterForOffline() async {
    final index = indexFile;
    if (await index.exists()) {
      await _rewriteIndexForOfflineLocalhost(index);
    }
  }

  Uri? _resolveManifestUri({
    required String? bundleManifestUrl,
    required String? apiBaseUrl,
  }) {
    final explicit = bundleManifestUrl?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return Uri.tryParse(explicit);
    }

    final base = apiBaseUrl?.trim();
    if (base == null || base.isEmpty) return null;
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) return null;
    return resolveBridgeApiRoute(baseUri, _fallbackManifestPath);
  }

  Uri _requiredManifestUri({
    required String? bundleManifestUrl,
    required String? apiBaseUrl,
  }) {
    final manifestUri = _resolveManifestUri(
      bundleManifestUrl: bundleManifestUrl,
      apiBaseUrl: apiBaseUrl,
    );
    if (manifestUri == null) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'bundleManifestUrl or apiBaseUrl is required for presenter sync.',
      );
    }
    return manifestUri;
  }

  Uri _resolveDownloadUri(Uri manifestUri, String rawDownloadUrl) {
    final parsed = Uri.tryParse(rawDownloadUrl);
    if (parsed != null && parsed.hasScheme) return parsed;
    if (rawDownloadUrl.startsWith('/api/')) {
      final prefixIndex = manifestUri.path.indexOf('/api/');
      final mountPrefix = prefixIndex <= 0
          ? ''
          : manifestUri.path.substring(0, prefixIndex);
      return manifestUri.replace(path: '$mountPrefix$rawDownloadUrl');
    }
    return manifestUri.resolve(rawDownloadUrl);
  }

  Future<Directory> _extractBundleToStaging(List<int> zipBytes) async {
    final staging = Directory(
      '${presenterRoot.parent.path}/.presenter_staging_'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    await staging.create(recursive: true);
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
      for (final entry in archive) {
        final sanitized = _sanitizeZipPath(entry.name);
        if (sanitized == null) {
          throw BridgeRuntimeException(
            BridgeRuntimeErrorCodes.offlineAssetsNotReady,
            'Unsafe zip entry path rejected: ${entry.name}',
          );
        }
        if (entry.isSymbolicLink) {
          throw const BridgeRuntimeException(
            BridgeRuntimeErrorCodes.offlineAssetsNotReady,
            'Symlink entries are not allowed in presenter bundle.',
          );
        }
        final outputPath = '${staging.path}/$sanitized';
        if (entry.isFile) {
          final outFile = File(outputPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        } else {
          await Directory(outputPath).create(recursive: true);
        }
      }
      final stagedIndex = File('${staging.path}/index.html');
      if (!await stagedIndex.exists()) {
        throw const BridgeRuntimeException(
          BridgeRuntimeErrorCodes.offlineAssetsNotReady,
          'Extracted presenter site is missing index.html.',
        );
      }
      await _rewriteIndexForOfflineLocalhost(stagedIndex);
      if (!await _isBundleSiteReady(staging)) {
        throw const BridgeRuntimeException(
          BridgeRuntimeErrorCodes.offlineAssetsNotReady,
          'Extracted Presenter bundle is incomplete or incompatible.',
        );
      }
      return staging;
    } catch (error) {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (error is BridgeRuntimeException) rethrow;
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.offlineAssetsNotReady,
        'Failed to extract presenter bundle: $error',
      );
    }
  }

  Future<void> _activateStaging(
    Directory staging,
    String manifestPayload,
  ) async {
    await presenterRoot.parent.create(recursive: true);
    await manifestFile.parent.create(recursive: true);

    final transactionId = DateTime.now().microsecondsSinceEpoch;
    final siteBackup = Directory('${presenterRoot.path}.backup_$transactionId');
    final manifestBackup = File('${manifestFile.path}.backup_$transactionId');
    final pendingManifest = File('${manifestFile.path}.pending_$transactionId');
    final hadCurrentSite = await presenterRoot.exists();
    final hadCurrentManifest = await manifestFile.exists();

    await pendingManifest.writeAsString(manifestPayload, flush: true);

    try {
      if (hadCurrentManifest) {
        await manifestFile.rename(manifestBackup.path);
      }
      if (hadCurrentSite) {
        await presenterRoot.rename(siteBackup.path);
      }

      await staging.rename(presenterRoot.path);
      await pendingManifest.rename(manifestFile.path);

      if (!await isReady()) {
        throw const BridgeRuntimeException(
          BridgeRuntimeErrorCodes.offlineAssetsNotReady,
          'Activated Presenter bundle failed readiness verification.',
        );
      }
    } catch (error, stackTrace) {
      await _deleteFileIfExists(pendingManifest);
      await _deleteDirectoryIfExists(presenterRoot);
      await _deleteFileIfExists(manifestFile);

      if (await siteBackup.exists()) {
        await siteBackup.rename(presenterRoot.path);
      }
      if (await manifestBackup.exists()) {
        await manifestBackup.rename(manifestFile.path);
      }
      await _deleteDirectoryIfExists(staging);
      Error.throwWithStackTrace(error, stackTrace);
    }

    // Activation is committed after readiness succeeds. Backup cleanup is
    // intentionally best-effort so a cleanup failure cannot destroy the new
    // valid bundle after the old bundle has already been removed.
    await _deleteDirectorySilently(siteBackup);
    await _deleteFileSilently(manifestBackup);
  }

  Future<void> _deleteDirectorySilently(Directory directory) async {
    try {
      await _deleteDirectoryIfExists(directory);
    } on FileSystemException {
      // A later cache refresh can remove an orphaned backup.
    }
  }

  Future<void> _deleteFileSilently(File file) async {
    try {
      await _deleteFileIfExists(file);
    } on FileSystemException {
      // A later cache refresh can remove an orphaned backup.
    }
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _deleteFileIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? _sanitizeZipPath(String rawPath) {
    final normalized = rawPath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty || normalized.startsWith('/')) return null;
    if (RegExp(r'^[a-zA-Z]:/').hasMatch(normalized)) return null;
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;
    if (segments.any((segment) => segment == '.' || segment == '..')) {
      return null;
    }
    return segments.join('/');
  }

  Future<void> _rewriteIndexForOfflineLocalhost(File indexFile) async {
    final html = await indexFile.readAsString();
    final normalized = html.replaceFirstMapped(
      RegExp(r'<base\s+href="[^"]*"\s*/?>', caseSensitive: false),
      (_) => '<base href="$_offlineBaseHref">',
    );
    if (normalized != html) await indexFile.writeAsString(normalized);
  }
}
