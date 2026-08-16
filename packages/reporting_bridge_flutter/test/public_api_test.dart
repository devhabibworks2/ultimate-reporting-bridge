import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test('barrel exposes every type required by the public client contract', () {
    final root = Directory.systemTemp.createTempSync('urb-public-api-');
    addTearDown(() => root.deleteSync(recursive: true));

    final endpoints = ReportServerEndpoints.deployed(
      Uri.parse('https://example.test'),
    );
    Map<String, String> provider(BridgeHeaderContext context) =>
        <String, String>{'X-Tenant-Id': '${context.systemId ?? 0}'};
    final connection = ReportServerConnection(
      endpoints: endpoints,
      cacheRoot: root,
      headersProvider: provider,
    );
    const ui = BridgeUiConfig.brand(seedColor: Color(0xFF29AD5F));
    final filter = TemplateSyncFilter(
      reportTypes: <String>[UrbReportType.salesInvoice.value],
      layouts: <String>[ReportLayout.pages.value],
    );
    final request = ReportOpenRequest(
      seedData: const <String, dynamic>{'id': 1},
      selectedTemplateCriteria: SelectedTemplateCriteria(
        reportType: UrbReportType.salesInvoice,
        identity: const ReportIdentity(userId: '42'),
      ),
      templateSyncRequest: TemplateSyncRequest(
        systemCode: UrbSystem.motakamelTransactions,
        identity: const ReportIdentity(userId: '42'),
        filter: filter,
      ),
      compatibility: const TemplateCompatibilityConstraints(
        language: ReportLanguage.ar,
        layout: ReportLayout.pages,
        size: ReportPageSize.a4,
      ),
    );

    expect(connection.headersProvider, same(provider));
    expect(
      endpoints.apiBaseUrl.toString(),
      'https://example.test/UltimateReport/backend/api/',
    );
    expect(
      endpoints.cacheIdentityBaseUrl.toString(),
      'https://example.test/UltimateReport/backend/',
    );
    expect(
      connection.preferenceSourceKey,
      'deployed|https://example.test|https://example.test/UltimateReport/backend/|'
      'https://example.test/UltimateReport/apps/presenter/index.html|8000|8080',
    );

    final localEndpoints = ReportServerEndpoints.localDevelopment(
      Uri.parse('http://127.0.0.1'),
    );
    final localConnection = ReportServerConnection(
      endpoints: localEndpoints,
      cacheRoot: root,
    );
    expect(
      localEndpoints.apiBaseUrl.toString(),
      'http://127.0.0.1:8000/UltimateReport/backend/api/',
    );
    expect(
      localEndpoints.cacheIdentityBaseUrl.toString(),
      'http://127.0.0.1:8000/',
    );
    expect(
      localConnection.preferenceSourceKey,
      'localDevelopment|http://127.0.0.1|http://127.0.0.1:8000/|'
      'http://127.0.0.1:8080/UltimateReport/apps/presenter/index.html|8000|8080',
    );

    expect(request.reportType, UrbReportType.salesInvoice);
    expect(
      request.selectedTemplateCriteria.reportType,
      UrbReportType.salesInvoice,
    );
    expect(request.templateSyncRequest.filter, same(filter));
    expect(ui.mode, BridgeUiThemeMode.brand);
    expect(
      const BridgeUiConfig.inheritHost().mode,
      BridgeUiThemeMode.inheritHost,
    );
    expect(
      BridgeUiConfig.custom(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF123456)),
      ).mode,
      BridgeUiThemeMode.custom,
    );
    expect(BridgeHeaderOperation.prepareSession.name, 'prepareSession');
    expect(
      const TemplateCompatibilityConstraints(
        language: ReportLanguage.ar,
        layout: ReportLayout.pages,
        size: ReportPageSize.a4,
      ).language,
      ReportLanguage.ar,
    );
    expect(filter.reportTypes, <String>['sales_invoice']);
    expect(filter.layouts, <String>['Pages']);

    const unsupported = UnsupportedReportPrintPlatform();
    final AndroidReportPrintPlatform? androidPrintPlatform = null;
    final IosAirPrintReportPrintPlatform? iosPrintPlatform = null;
    final ReportFilePlatform? filePlatform = null;

    expect(unsupported, isA<ReportPrintPlatform>());
    expect(androidPrintPlatform, isNull);
    expect(iosPrintPlatform, isNull);
    expect(filePlatform, isNull);
  });
}
