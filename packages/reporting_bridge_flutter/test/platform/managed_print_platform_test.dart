import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/platform/android_print_configuration.dart';
import 'package:reporting_bridge_flutter/src/platform/bridge_platform_adapters.dart';
import 'package:reporting_bridge_flutter/src/platform/ios_print_configuration.dart';
import 'package:reporting_bridge_flutter/src/platform/managed_print_platform.dart';

void main() {
  test('explicit override bypasses every managed factory', () async {
    final override = _Platform();
    var factoryCalls = 0;

    final resources = await resolveManagedPrintPlatform(
      override: override,
      effectivePlatform: TargetPlatform.android,
      androidConfiguration: const AndroidPrintConfiguration.escPos(),
      iosPrintMode: IosPrintMode.airPrint,
      thermalFactory: (_) async {
        factoryCalls += 1;
        throw StateError('must not run');
      },
      androidFactory: (_) async {
        factoryCalls += 1;
        throw StateError('must not run');
      },
      iosFactory: (_) async {
        factoryCalls += 1;
        throw StateError('must not run');
      },
    );

    expect(resources.platform, same(override));
    expect(resources.thermalPrinterSettings, isNull);
    expect(resources.dispose, isNull);
    expect(factoryCalls, 0);
  });

  test(
    'unsupported targets fail closed without invoking platform factories',
    () async {
      var factoryCalls = 0;

      final resources = await resolveManagedPrintPlatform(
        effectivePlatform: null,
        androidConfiguration: const AndroidPrintConfiguration.escPos(),
        iosPrintMode: IosPrintMode.airPrint,
        thermalFactory: (_) async {
          factoryCalls += 1;
          throw StateError('must not run');
        },
        androidFactory: (_) async {
          factoryCalls += 1;
          throw StateError('must not run');
        },
        iosFactory: (_) async {
          factoryCalls += 1;
          throw StateError('must not run');
        },
      );

      expect(resources.platform, isA<UnsupportedReportPrintPlatform>());
      expect(resources.thermalPrinterSettings, isNull);
      expect(factoryCalls, 0);
    },
  );

  test(
    'Android ESC/POS selects thermal and forwards exact configuration',
    () async {
      const config = AndroidPrintConfiguration.escPos(maximumPdfBytes: 1234);
      AndroidPrintConfiguration? seen;
      final expected = _Platform();
      final resources = await resolveManagedPrintPlatform(
        effectivePlatform: TargetPlatform.android,
        androidConfiguration: config,
        iosPrintMode: IosPrintMode.airPrint,
        thermalFactory: (value) async {
          seen = value;
          return ManagedPrintPlatformResources(platform: expected);
        },
        androidFactory: (_) async => throw StateError('wrong Android factory'),
        iosFactory: (_) async => throw StateError('wrong iOS factory'),
      );
      expect(resources.platform, same(expected));
      expect(seen, same(config));
    },
  );

  test('Android system mode selects Android factory', () async {
    const config = AndroidPrintConfiguration.systemPrintManager(
      maximumPdfBytes: 4321,
    );
    var thermalCalls = 0;
    AndroidPrintConfiguration? seen;
    final expected = _Platform();
    final resources = await resolveManagedPrintPlatform(
      effectivePlatform: TargetPlatform.android,
      androidConfiguration: config,
      iosPrintMode: IosPrintMode.airPrint,
      thermalFactory: (_) async {
        thermalCalls += 1;
        throw StateError('wrong thermal factory');
      },
      androidFactory: (value) async {
        seen = value;
        return ManagedPrintPlatformResources(platform: expected);
      },
      iosFactory: (_) async => throw StateError('wrong iOS factory'),
    );
    expect(resources.platform, same(expected));
    expect(seen, same(config));
    expect(thermalCalls, 0);
  });

  test(
    'Android externalApp mode selects Android factory and forwards exact configuration',
    () async {
      final config = AndroidPrintConfiguration.externalApp(
        configuration: AndroidExternalPrinterConfiguration(
          installUri: Uri.parse('https://example.test/printer'),
          maximumPdfBytes: 2048,
        ),
      );
      var thermalCalls = 0;
      var iosCalls = 0;
      AndroidPrintConfiguration? seen;
      final expected = _Platform();
      final resources = await resolveManagedPrintPlatform(
        effectivePlatform: TargetPlatform.android,
        androidConfiguration: config,
        iosPrintMode: IosPrintMode.airPrint,
        thermalFactory: (_) async {
          thermalCalls += 1;
          throw StateError('wrong thermal factory');
        },
        androidFactory: (value) async {
          seen = value;
          return ManagedPrintPlatformResources(platform: expected);
        },
        iosFactory: (_) async {
          iosCalls += 1;
          throw StateError('wrong iOS factory');
        },
      );

      expect(resources.platform, same(expected));
      expect(seen, same(config));
      expect(seen!.mode, AndroidPrintMode.externalApp);
      expect(seen!.maximumPdfBytes, 2048);
      expect(
        seen!.externalApp?.installUri,
        Uri.parse('https://example.test/printer'),
      );
      expect(thermalCalls, 0);
      expect(iosCalls, 0);
    },
  );

  test('iOS selects AirPrint factory', () async {
    IosPrintMode? seen;
    final expected = _Platform();
    final resources = await resolveManagedPrintPlatform(
      effectivePlatform: TargetPlatform.iOS,
      androidConfiguration: const AndroidPrintConfiguration.escPos(),
      iosPrintMode: IosPrintMode.airPrint,
      thermalFactory: (_) async => throw StateError('wrong thermal factory'),
      androidFactory: (_) async => throw StateError('wrong Android factory'),
      iosFactory: (value) async {
        seen = value;
        return ManagedPrintPlatformResources(platform: expected);
      },
    );
    expect(resources.platform, same(expected));
    expect(seen, IosPrintMode.airPrint);
  });

  test('selected factory failure has no fallback', () async {
    var fallbackCalls = 0;
    await expectLater(
      resolveManagedPrintPlatform(
        effectivePlatform: TargetPlatform.android,
        androidConfiguration: const AndroidPrintConfiguration.escPos(),
        iosPrintMode: IosPrintMode.airPrint,
        thermalFactory: (_) async => throw StateError('thermal failed'),
        androidFactory: (_) async {
          fallbackCalls += 1;
          return ManagedPrintPlatformResources(platform: _Platform());
        },
        iosFactory: (_) async {
          fallbackCalls += 1;
          return ManagedPrintPlatformResources(platform: _Platform());
        },
      ),
      throwsStateError,
    );
    expect(fallbackCalls, 0);
  });
}

final class _Platform implements ReportPrintPlatform {
  @override
  Future<ReportPrintResult> printPdf(ReportPrintRequest request) async =>
      const ReportPrintResult.submitted();
}
