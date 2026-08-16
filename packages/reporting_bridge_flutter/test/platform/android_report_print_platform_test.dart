import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:reporting_bridge_flutter/src/contracts/external_printer_contract.dart';
import 'package:reporting_bridge_flutter/src/platform/android_print_configuration.dart';
import 'package:reporting_bridge_flutter/src/platform/android_report_print_platform.dart';
import 'package:reporting_bridge_flutter/src/platform/bridge_platform_adapters.dart';

import 'test_print_request.dart';

void main() {
  group('system PrintManager mode', () {
    test('invokes PrintManager and maps submitted result', () async {
      final native = _FakeAndroidPrintNativeClient();
      final platform = AndroidReportPrintPlatform(
        configuration: const AndroidPrintConfiguration.systemPrintManager(),
        nativeClient: native,
        observeLifecycle: false,
      );

      final result = await platform.printPdf(testPrintRequest());

      expect(result.status, ReportPrintStatus.submitted);
      expect(native.systemCalls, 1);
      expect(native.packageQueries, 0);
      expect(native.externalCalls, 0);
      platform.dispose();
    });

    test(
      'maps native cancellation without querying external package',
      () async {
        final native = _FakeAndroidPrintNativeClient()
          ..systemResult = const ReportPrintResult.cancelled();
        final platform = AndroidReportPrintPlatform(
          configuration: const AndroidPrintConfiguration.systemPrintManager(),
          nativeClient: native,
          observeLifecycle: false,
        );

        final result = await platform.printPdf(testPrintRequest());

        expect(result.status, ReportPrintStatus.cancelled);
        expect(native.packageQueries, 0);
        platform.dispose();
      },
    );

    test('enforces size limit before native platform invocation', () async {
      final native = _FakeAndroidPrintNativeClient();
      final platform = AndroidReportPrintPlatform(
        configuration: const AndroidPrintConfiguration.systemPrintManager(
          maximumPdfBytes: 4,
        ),
        nativeClient: native,
        observeLifecycle: false,
      );

      final result = await platform.printPdf(
        testPrintRequest(pdfBytes: Uint8List(5)),
      );

      expect(result.status, ReportPrintStatus.failed);
      expect(result.errorCode, 'pdfTooLarge');
      expect(native.systemCalls, 0);
      expect(native.packageQueries, 0);
      platform.dispose();
    });
  });

  group('external-app mode', () {
    late AndroidExternalPrinterConfiguration external;

    setUp(() {
      external = AndroidExternalPrinterConfiguration(
        installUri: Uri.parse('https://example.test/install'),
      );
    });

    test('returns appNotInstalled when prompt is unavailable', () async {
      final native = _FakeAndroidPrintNativeClient()..installed = false;
      final platform = AndroidReportPrintPlatform(
        configuration: AndroidPrintConfiguration.externalApp(
          configuration: external,
        ),
        nativeClient: native,
        observeLifecycle: false,
      );

      final result = await platform.printPdf(testPrintRequest());

      expect(result.status, ReportPrintStatus.appNotInstalled);
      expect(result.errorCode, 'externalPrinterNotInstalled');
      expect(native.packageQueries, 1);
      expect(native.externalCalls, 0);
      expect(native.cleanupTtls, <Duration>[const Duration(hours: 24)]);
      platform.dispose();
    });

    test(
      'opens configured install URI after Bridge prompt acceptance',
      () async {
        final native = _FakeAndroidPrintNativeClient()..installed = false;
        Uri? promptedUri;
        final platform = AndroidReportPrintPlatform(
          configuration: AndroidPrintConfiguration.externalApp(
            configuration: external,
          ),
          nativeClient: native,
          installPrompt: (uri) async {
            promptedUri = uri;
            return true;
          },
          observeLifecycle: false,
        );

        final result = await platform.printPdf(testPrintRequest());

        expect(result.status, ReportPrintStatus.setupRequired);
        expect(promptedUri, external.installUri);
        expect(native.openedInstallUris, <Uri>[external.installUri]);
        platform.dispose();
      },
    );

    test(
      're-checks on resume and submits pending print after installation',
      () async {
        final native = _FakeAndroidPrintNativeClient()..installed = false;
        ReportPrintResult? deferred;
        final platform = AndroidReportPrintPlatform(
          configuration: AndroidPrintConfiguration.externalApp(
            configuration: external,
          ),
          nativeClient: native,
          installPrompt: (_) async => true,
          onDeferredResult: (result) => deferred = result,
          observeLifecycle: false,
        );

        final setup = await platform.printPdf(testPrintRequest());
        expect(setup.status, ReportPrintStatus.setupRequired);

        native.installed = true;
        final resumed = await platform.recheckPendingExternalPrint();

        expect(resumed?.status, ReportPrintStatus.submitted);
        expect(deferred?.status, ReportPrintStatus.submitted);
        expect(native.packageQueries, 2);
        expect(native.externalCalls, 1);
        platform.dispose();
      },
    );

    test(
      'resumed lifecycle schedules the pending external print recheck',
      () async {
        final native = _FakeAndroidPrintNativeClient()..installed = false;
        final deferred = Completer<ReportPrintResult>();
        final platform = AndroidReportPrintPlatform(
          configuration: AndroidPrintConfiguration.externalApp(
            configuration: external,
          ),
          nativeClient: native,
          installPrompt: (_) async => true,
          onDeferredResult: deferred.complete,
          observeLifecycle: false,
        );

        final setup = await platform.printPdf(testPrintRequest());
        expect(setup.status, ReportPrintStatus.setupRequired);

        native.installed = true;
        platform.didChangeAppLifecycleState(AppLifecycleState.resumed);
        final result = await deferred.future;

        expect(result.status, ReportPrintStatus.submitted);
        expect(native.packageQueries, 2);
        expect(native.externalCalls, 1);
        platform.dispose();
      },
    );

    test('uses explicit V1 Intent contract and Arabic mapping', () async {
      final native = _FakeAndroidPrintNativeClient()..installed = true;
      final platform = AndroidReportPrintPlatform(
        configuration: AndroidPrintConfiguration.externalApp(
          configuration: external,
        ),
        nativeClient: native,
        observeLifecycle: false,
      );

      final result = await platform.printPdf(
        testPrintRequest(extra: <String, Object?>{'copyCount': 2}),
      );
      final payload = native.lastExternalPayload!;

      expect(result.status, ReportPrintStatus.submitted);
      expect(payload.packageName, ultimatePrinterPackageName);
      expect(payload.action, ultimatePrinterAction);
      expect(payload.mimeType, ultimatePrinterMimeType);
      expect(payload.contractVersion, ultimatePrinterContractVersion);
      expect(payload.languageCode, 'ar');
      expect(payload.language, 1);
      expect(payload.extra, <String, Object?>{'copyCount': 2});
      expect(payload.pdfBytes, testPrintRequest().pdfBytes);
      platform.dispose();
    });

    test('maps English language to V1 value 2', () async {
      final native = _FakeAndroidPrintNativeClient()..installed = true;
      final platform = AndroidReportPrintPlatform(
        configuration: AndroidPrintConfiguration.externalApp(
          configuration: external,
        ),
        nativeClient: native,
        observeLifecycle: false,
      );

      await platform.printPdf(testPrintRequest(languageCode: 'en'));

      expect(native.lastExternalPayload?.language, 2);
      platform.dispose();
    });

    test('protects reserved fields in extra before package query', () async {
      final native = _FakeAndroidPrintNativeClient()..installed = true;
      final platform = AndroidReportPrintPlatform(
        configuration: AndroidPrintConfiguration.externalApp(
          configuration: external,
        ),
        nativeClient: native,
        observeLifecycle: false,
      );

      final result = await platform.printPdf(
        testPrintRequest(extra: <String, Object?>{'jobId': 'override'}),
      );

      expect(result.status, ReportPrintStatus.unsupportedContract);
      expect(result.errorCode, 'reservedExtraField');
      expect(native.packageQueries, 0);
      expect(native.externalCalls, 0);
      platform.dispose();
    });

    test('rejects unsupported language before native invocation', () async {
      final native = _FakeAndroidPrintNativeClient()..installed = true;
      final platform = AndroidReportPrintPlatform(
        configuration: AndroidPrintConfiguration.externalApp(
          configuration: external,
        ),
        nativeClient: native,
        observeLifecycle: false,
      );

      final result = await platform.printPdf(
        testPrintRequest(languageCode: 'fr'),
      );

      expect(result.status, ReportPrintStatus.unsupportedContract);
      expect(result.errorCode, 'unsupportedLanguage');
      expect(native.packageQueries, 0);
      platform.dispose();
    });
  });
}

final class _FakeAndroidPrintNativeClient implements AndroidPrintNativeClient {
  ReportPrintResult systemResult = const ReportPrintResult.submitted();
  ReportPrintResult externalResult = const ReportPrintResult.submitted();
  bool installed = true;
  bool installUriOpened = true;

  int systemCalls = 0;
  int packageQueries = 0;
  int externalCalls = 0;
  AndroidExternalPrintPayload? lastExternalPayload;
  final List<Uri> openedInstallUris = <Uri>[];
  final List<Duration> cleanupTtls = <Duration>[];

  @override
  Future<void> cleanupStaleFiles(Duration ttl) async {
    cleanupTtls.add(ttl);
  }

  @override
  Future<bool> isExternalAppInstalled({
    required String packageName,
    required String action,
    required String mimeType,
  }) async {
    packageQueries += 1;
    expect(packageName, ultimatePrinterPackageName);
    expect(action, ultimatePrinterAction);
    expect(mimeType, ultimatePrinterMimeType);
    return installed;
  }

  @override
  Future<bool> openInstallUri(Uri installUri) async {
    openedInstallUris.add(installUri);
    return installUriOpened;
  }

  @override
  Future<ReportPrintResult> printWithExternalApp(
    AndroidExternalPrintPayload payload,
  ) async {
    externalCalls += 1;
    lastExternalPayload = payload;
    return externalResult;
  }

  @override
  Future<ReportPrintResult> printWithSystemManager({
    required Uint8List pdfBytes,
    required String documentTitle,
    required int maximumPdfBytes,
  }) async {
    systemCalls += 1;
    expect(pdfBytes, isNotEmpty);
    expect(documentTitle, 'Invoice 42');
    return systemResult;
  }
}
