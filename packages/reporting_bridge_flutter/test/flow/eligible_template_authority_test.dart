import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_controller_impl.dart';
import 'package:reporting_bridge_flutter/src/flow/report_flow_runtime.dart';
import '../test_open_request.dart';

void main() {
  late Directory root;
  late ReportServerConnection connection;
  late MemoryReportFlowPreferenceStore preferences;

  setUp(() {
    root = Directory.systemTemp.createTempSync('urb-eligible-auth-');
    connection = ReportServerConnection(
      endpoints: ReportServerEndpoints.deployed(
        Uri.parse('https://example.test'),
      ),
      cacheRoot: root,
    );
    preferences = MemoryReportFlowPreferenceStore();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test(
    'state.templates is the single eligible authority used by workflow',
    () async {
      final bridge = _FakeBridge(
        root,
        templates: <CachedTemplate>[
          _canonical(
            id: 'wrong-lang',
            language: 'en',
            size: 'A4',
            width: 210,
            height: 297,
          ),
          _malformed(id: 'malformed'),
          _canonical(
            id: 'wrong-size',
            language: 'ar',
            size: 'A5',
            width: 148,
            height: 210,
          ),
          _canonical(
            id: 'valid',
            language: 'ar',
            size: 'A4',
            width: 210,
            height: 297,
          ),
        ],
      );
      final controller = ReportFlowControllerImpl(
        request: buildTestOpenRequest(
          entryPolicy: ReportEntryPolicy.alwaysPrepare,
          compatibility: const TemplateCompatibilityConstraints(
            language: ReportLanguage.ar,
            layout: ReportLayout.pages,
            size: ReportPageSize.a4,
          ),
        ),
        runtime: ReportFlowRuntime(
          connection: connection,
          bridgeClient: bridge,
          preferences: preferences,
          filePlatform: const _NoopFiles(),
          surfaceBinding: PresenterSurfaceBinding(),
        ),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.value.templates.map((t) => t.id), <String>['valid']);
      expect(controller.eligibleTemplates.map((t) => t.id), <String>['valid']);
      expect(controller.value.templates.length, 1);
      expect(controller.value.selectedTemplateId, 'valid');

      await controller.continueFromPreparation();
      expect(controller.value.stage, ReportFlowStage.selectingTemplate);
      expect(controller.value.templates.length, 1);

      controller.selectTemplate('wrong-lang');
      expect(controller.value.selectedTemplateId, 'valid');
      controller.selectTemplate('valid');
      expect(controller.value.selectedTemplateId, 'valid');
    },
  );

  test(
    'reportType matches with zero eligible keep Preparation unready',
    () async {
      final bridge = _FakeBridge(
        root,
        templates: <CachedTemplate>[
          _canonical(
            id: 'en-only',
            language: 'en',
            size: 'A4',
            width: 210,
            height: 297,
          ),
          _canonical(
            id: 'a5-ar',
            language: 'ar',
            size: 'A5',
            width: 148,
            height: 210,
          ),
          _malformed(id: 'broken'),
        ],
      );
      final controller = ReportFlowControllerImpl(
        request: buildTestOpenRequest(
          entryPolicy: ReportEntryPolicy.alwaysPrepare,
          compatibility: const TemplateCompatibilityConstraints(
            language: ReportLanguage.ar,
            layout: ReportLayout.pages,
            size: ReportPageSize.a4,
          ),
        ),
        runtime: ReportFlowRuntime(
          connection: connection,
          bridgeClient: bridge,
          preferences: preferences,
          filePlatform: const _NoopFiles(),
          surfaceBinding: PresenterSurfaceBinding(),
        ),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.value.templates, isEmpty);
      expect(controller.eligibleTemplates, isEmpty);
      expect(controller.value.stage, ReportFlowStage.preparingResources);

      await controller.continueFromPreparation();
      expect(controller.value.stage, ReportFlowStage.preparingResources);
      expect(controller.value.templates, isEmpty);
    },
  );
}

class _FakeBridge extends ReportingBridgeClient {
  _FakeBridge(Directory root, {required this.templates})
    : super(
        apiBaseUrl: Uri.parse(
          'https://example.test/UltimateReport/backend/api/',
        ),
        presenterEntryUrl: Uri.parse(
          'https://example.test/UltimateReport/apps/presenter/',
        ),
        bridgeRoot: root,
      );

  final List<CachedTemplate> templates;

  @override
  Future<TemplateSyncSummary> syncTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => TemplateSyncSummary(
    syncedCount: templates.length,
    listCount: templates.length,
    errors: const <String>[],
  );

  @override
  Future<List<CachedTemplate>> listTemplates({
    String? systemCode,
    int? systemId,
    TemplateSyncFilter? filter,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async => List<CachedTemplate>.from(templates);

  @override
  Future<ReportingBridgeStatus> getStatus() async => ReportingBridgeStatus(
    apiBaseUrl: apiBaseUrl.toString(),
    presenterCached: true,
    templateCount: templates.length,
  );

  @override
  Future<void> updateIdentityContext(BridgeIdentityContext identity) async {}

  @override
  Future<void> clearIdentityContext() async {}
}

CachedTemplate _canonical({
  required String id,
  required String language,
  required String size,
  required double width,
  required double height,
}) => CachedTemplate(
  id: id,
  type: 'sales_invoice',
  name: id,
  version: '1.0.0',
  document: <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': const <String, dynamic>{
      'name': 'Invoice',
      'family': 'sales_invoice',
    },
    'page': <String, dynamic>{
      'layout': 'Pages',
      'size': size,
      'unit': 'mm',
      'orientation': 'portrait',
      'language': language,
      'direction': language == 'ar' ? 'rtl' : 'ltr',
      'width': width,
      'height': height,
    },
    'styleTokens': const <String, dynamic>{},
    'assets': const <dynamic>[],
    'layers': const <dynamic>[],
    'elements': const <dynamic>[],
  },
);

CachedTemplate _malformed({required String id}) => CachedTemplate(
  id: id,
  type: 'sales_invoice',
  name: id,
  version: '1.0.0',
  document: const <String, dynamic>{
    'schemaVersion': '1.0.0',
    'meta': <String, dynamic>{'name': 'Broken', 'family': 'sales_invoice'},
    'page': <String, dynamic>{'layout': 'Pages', 'language': 'ar'},
  },
);

class _NoopFiles implements ReportFilePlatform {
  const _NoopFiles();

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async => true;

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) async {}
}
