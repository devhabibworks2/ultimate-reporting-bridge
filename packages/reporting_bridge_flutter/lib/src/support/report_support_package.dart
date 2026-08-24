import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../contracts/report_open_request.dart';
import '../flow/report_flow_failure.dart';

final class ReportSupportPackage {
  const ReportSupportPackage({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

final class ReportSupportPackageBuilder {
  const ReportSupportPackageBuilder();

  ReportSupportPackage build({
    required Map<String, dynamic> seedData,
    required CachedTemplate template,
    required ReportFlowFailure? failure,
    required String systemCode,
    required String reportType,
    required PresenterModePreference presenterMode,
    String? reportName,
    String? requestId,
    String? userId,
    String? branchId,
    String? systemUnit,
    String? customType,
    String? locale,
    PresenterSessionLaunch? presenterLaunch,
    PresenterCacheManifest? presenterManifest,
    DateTime? generatedAt,
  }) {
    final timestamp = (generatedAt ?? DateTime.now()).toUtc();
    final payloads = <String, Uint8List>{
      'template.json': _jsonBytes(template.document),
      'seed_data.json': _jsonBytes(_sanitizeDiagnosticValue(seedData)),
      'diagnostics/error.json': _jsonBytes(_errorJson(failure)),
      'diagnostics/system.json': _jsonBytes(
        _sanitizeDiagnosticValue(<String, Object?>{
          'systemCode': systemCode,
          'reportType': reportType,
          if (reportName != null) 'reportName': reportName,
          if (requestId != null) 'requestId': requestId,
          if (userId != null) 'userId': userId,
          if (branchId != null) 'branchId': branchId,
          if (systemUnit != null) 'systemUnit': systemUnit,
          if (customType != null) 'customType': customType,
          'presenterMode': presenterMode.name,
          if (locale != null) 'locale': locale,
        }),
      ),
      'diagnostics/presenter.json': _jsonBytes(
        _sanitizeDiagnosticValue(
          _presenterJson(
            presenterLaunch: presenterLaunch,
            presenterManifest: presenterManifest,
          ),
        ),
      ),
      'diagnostics/bridge.json': _jsonBytes(
        _sanitizeDiagnosticValue(_bridgeJson(template)),
      ),
    };

    final manifest = <String, Object?>{
      'format': 'urb-template-package',
      'packageVersion': 1,
      'generatedAt': timestamp.toIso8601String(),
      'producer': 'bridge',
      'packageKind': 'diagnostics',
      'sourceSystemCode': systemCode,
      'seedData': const <String, Object?>{'mode': 'redacted'},
      'integrity': <String, Object?>{
        'algorithm': 'sha256',
        'files': <String, String>{
          for (final entry in payloads.entries)
            entry.key: sha256.convert(entry.value).toString(),
        },
      },
    };

    final archive = Archive()
      ..add(_archiveFile('manifest.json', _jsonBytes(manifest)));
    for (final entry in payloads.entries) {
      archive.add(_archiveFile(entry.key, entry.value));
    }

    final bytes = ZipEncoder().encodeBytes(archive);
    return ReportSupportPackage(
      bytes: bytes,
      filename: 'urb_report_issue_${_filenameTimestamp(timestamp)}.urb',
    );
  }

  Map<String, Object?> _errorJson(ReportFlowFailure? failure) {
    if (failure == null) {
      return const <String, Object?>{'bridgeCode': null};
    }
    return <String, Object?>{
      'bridgeCode': failure.code.name,
      if (failure.diagnostic != null)
        'message': _sanitizeDiagnosticText(failure.diagnostic!),
      if (failure.technicalCode != null) 'technicalCode': failure.technicalCode,
      if (failure.technicalCategory != null)
        'technicalCategory': failure.technicalCategory,
      if (failure.technicalPath != null) 'technicalPath': failure.technicalPath,
      if (failure.details.isNotEmpty)
        'details': _sanitizeDiagnosticValue(failure.details),
    };
  }

  Map<String, Object?> _bridgeJson(CachedTemplate template) {
    return <String, Object?>{
      'bridgeVersion': BridgeContract.implementationVersion,
      'bridgePayloadVersion': BridgeContract.payloadVersion,
      'template': <String, Object?>{
        'id': template.id,
        'type': template.type,
        if (template.code != null) 'code': template.code,
        if (template.name != null) 'name': template.name,
        if (template.description != null) 'description': template.description,
        if (template.publishedVersionNo != null)
          'publishedVersionNo': template.publishedVersionNo,
        if (template.version != null) 'version': template.version,
        if (template.minPresenterVersion != null)
          'minPresenterVersion': template.minPresenterVersion,
        if (template.minBridgeVersion != null)
          'minBridgeVersion': template.minBridgeVersion,
        'metadata': template.metadata,
        'compatibility': template.compatibility,
      },
    };
  }

  Map<String, Object?> _presenterJson({
    required PresenterSessionLaunch? presenterLaunch,
    required PresenterCacheManifest? presenterManifest,
  }) {
    final manifest = presenterManifest ?? presenterLaunch?.presenterManifest;
    return <String, Object?>{
      if (presenterLaunch != null) ...<String, Object?>{
        'sessionId': presenterLaunch.sessionId,
        'presenterVersion': presenterLaunch.presenterVersion,
        'presenterDevVersion': presenterLaunch.presenterDevVersion,
      },
      if (manifest != null) ...<String, Object?>{
        'bundleVersion': manifest.bundleVersion,
        'bundleDevVersion': manifest.devVersion,
        if (manifest.presenterVersion != null)
          'cachedPresenterVersion': manifest.presenterVersion,
        if (manifest.updatedAt != null)
          'updatedAt': manifest.updatedAt!.toUtc().toIso8601String(),
        if (manifest.syncedAt != null)
          'syncedAt': manifest.syncedAt!.toUtc().toIso8601String(),
      },
    };
  }
}

ArchiveFile _archiveFile(String name, Uint8List bytes) {
  return ArchiveFile(name, bytes.length, bytes);
}

Uint8List _jsonBytes(Object? value) {
  return Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(value)),
  );
}

Object? _sanitizeDiagnosticValue(Object? value, {String? key}) {
  if (key != null && _sensitiveDiagnosticKey(key)) return '<redacted>';
  if (value is String) return _sanitizeDiagnosticText(value);
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _sanitizeDiagnosticValue(
          entry.value,
          key: entry.key.toString(),
        ),
    };
  }
  if (value is Iterable) {
    return value.map(_sanitizeDiagnosticValue).toList(growable: false);
  }
  return value;
}

bool _sensitiveDiagnosticKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (normalized == 'styletokens') return false;
  return normalized.contains('authorization') ||
      normalized == 'cookie' ||
      normalized == 'cookies' ||
      normalized.contains('password') ||
      normalized.contains('passwd') ||
      normalized.contains('secret') ||
      normalized == 'apikey' ||
      normalized.endsWith('apikey') ||
      normalized == 'token' ||
      normalized.endsWith('token') ||
      normalized.endsWith('tokens');
}

String _sanitizeDiagnosticText(String value) {
  var sanitized = value.replaceAllMapped(
    RegExp(r'(authorization\s*[:=]\s*bearer\s+)[^\s,;]+', caseSensitive: false),
    (match) => '${match.group(1)}<redacted>',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'((?:api[_-]?key|token|password|secret)\s*[:=]\s*)[^\s,;]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<redacted>',
  );
  return sanitized;
}

String _filenameTimestamp(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}'
      '${two(value.month)}${two(value.day)}T'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}Z';
}
