import 'dart:convert';
import 'dart:io';

import 'bridge_config.dart';
import 'bridge_runtime_error.dart';
import 'bridge_runtime_session.dart';
import 'bridge_selected_template.dart';

class RuntimeSessionInput {
  const RuntimeSessionInput({
    required this.reportType,
    required this.seedData,
    required this.templateDocument,
    this.sessionId,
    this.reportName,
    this.mode,
    this.locale,
    this.direction,
    this.presenterUrl,
    this.selectedTemplate,
    this.branding,
    this.apiHeaders,
    this.writeSessionJson = true,
  });

  final String? sessionId;
  final String reportType;
  final String? reportName;
  final String? mode;
  final String? locale;
  final String? direction;
  final String? presenterUrl;
  final Map<String, dynamic> seedData;
  final Map<String, dynamic> templateDocument;
  final SelectedTemplate? selectedTemplate;
  final BrandConfig? branding;
  final ApiHeaderConfig? apiHeaders;
  final bool writeSessionJson;
}

class RuntimeSessionStorage {
  const RuntimeSessionStorage({required this.runtimeRoot});

  final Directory runtimeRoot;

  Future<RuntimeSession> prepareRuntimeSession(
    RuntimeSessionInput input,
  ) async {
    final sessionId = _sessionId(input.sessionId);
    if (input.reportType.trim().isEmpty) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeSessionInvalid,
        'Runtime session requires reportType.',
      );
    }

    final sessionDir = Directory('${runtimeRoot.path}/$sessionId');
    try {
      await sessionDir.create(recursive: true);
      final seedRef = await writeSeedReportData(
        sessionId: sessionId,
        seedData: input.seedData,
      );
      final templateRef = await writeTemplateJson(
        sessionId: sessionId,
        template: input.templateDocument,
      );

      final partialSession = RuntimeSession(
        sessionId: sessionId,
        reportType: input.reportType,
        reportName: input.reportName,
        mode: input.mode,
        locale: input.locale,
        direction: input.direction,
        presenterUrl: input.presenterUrl,
        selectedTemplate: input.selectedTemplate,
        branding: input.branding,
        seedReportData: seedRef,
        template: templateRef,
        apiHeaders: input.apiHeaders,
      );
      final sessionRef = input.writeSessionJson
          ? await writeSessionJson(partialSession)
          : null;
      return RuntimeSession(
        sessionId: sessionId,
        reportType: input.reportType,
        reportName: input.reportName,
        mode: input.mode,
        locale: input.locale,
        direction: input.direction,
        presenterUrl: input.presenterUrl,
        selectedTemplate: input.selectedTemplate,
        branding: input.branding,
        seedReportData: seedRef,
        template: templateRef,
        session: sessionRef,
        apiHeaders: input.apiHeaders,
      );
    } on BridgeRuntimeException {
      await _deleteDirectoryIfExists(sessionDir);
      rethrow;
    } on Object catch (error) {
      await _deleteDirectoryIfExists(sessionDir);
      throw BridgeRuntimeException(
        BridgeRuntimeErrorCodes.runtimeFileWriteFailed,
        'Failed to write runtime session files: $error',
      );
    }
  }

  Future<void> deleteRuntimeSession(String sessionId) async {
    final normalizedSessionId = _sessionId(sessionId);
    final sessionDir = Directory('${runtimeRoot.path}/$normalizedSessionId');
    if (await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
    }
  }

  Future<FileRef> writeSeedReportData({
    required String sessionId,
    required Map<String, dynamic> seedData,
  }) {
    return _writeJson(
      sessionId: sessionId,
      fileName: 'seed_report_data.json',
      data: seedData,
    );
  }

  Future<FileRef> writeTemplateJson({
    required String sessionId,
    required Map<String, dynamic> template,
  }) {
    if (template.isEmpty) {
      throw const BridgeRuntimeException(
        BridgeRuntimeErrorCodes.templateDocumentInvalid,
        'Template document must not be empty.',
      );
    }
    return _writeJson(
      sessionId: sessionId,
      fileName: 'template.json',
      data: template,
    );
  }

  Future<FileRef> writeSessionJson(RuntimeSession session) {
    return _writeJson(
      sessionId: session.sessionId,
      fileName: 'session.json',
      data: session.toMap(),
    );
  }

  Future<FileRef> _writeJson({
    required String sessionId,
    required String fileName,
    required Map<String, dynamic> data,
  }) async {
    final normalizedSessionId = _sessionId(sessionId);
    final dir = Directory('${runtimeRoot.path}/$normalizedSessionId');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonEncode(data), flush: true);
    return FileRef(
      path: file.path,
      url: '/runtime/$normalizedSessionId/$fileName',
    );
  }
}

String _sessionId(String? requested) {
  final source = requested?.trim();
  final value = source == null || source.isEmpty
      ? 'session-${DateTime.now().microsecondsSinceEpoch}'
      : source;
  final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  if (normalized.isEmpty || normalized == '.' || normalized == '..') {
    throw const BridgeRuntimeException(
      BridgeRuntimeErrorCodes.runtimeSessionInvalid,
      'Runtime session ID is invalid.',
    );
  }
  return normalized;
}

Future<void> _deleteDirectoryIfExists(Directory directory) async {
  try {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  } on FileSystemException {
    // Preserve the original runtime preparation failure.
  }
}
