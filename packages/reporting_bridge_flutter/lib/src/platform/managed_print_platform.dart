import 'package:flutter/foundation.dart';

import '../printing/thermal_printer_controller.dart';
import 'android_print_configuration.dart';
import 'bridge_platform_adapters.dart';
import 'ios_print_configuration.dart';

final class ManagedPrintPlatformResources {
  const ManagedPrintPlatformResources({
    required this.platform,
    this.thermalPrinterSettings,
    this.dispose,
  });

  final ReportPrintPlatform platform;
  final ThermalPrinterSettingsController? thermalPrinterSettings;
  final void Function()? dispose;
}

typedef ManagedAndroidPrintFactory =
    Future<ManagedPrintPlatformResources> Function(
      AndroidPrintConfiguration configuration,
    );
typedef ManagedIosPrintFactory =
    Future<ManagedPrintPlatformResources> Function(IosPrintMode mode);

Future<ManagedPrintPlatformResources> resolveManagedPrintPlatform({
  ReportPrintPlatform? override,
  required TargetPlatform? effectivePlatform,
  required AndroidPrintConfiguration androidConfiguration,
  required IosPrintMode iosPrintMode,
  required ManagedAndroidPrintFactory thermalFactory,
  required ManagedAndroidPrintFactory androidFactory,
  required ManagedIosPrintFactory iosFactory,
}) async {
  if (override != null) {
    return ManagedPrintPlatformResources(platform: override);
  }

  return switch (effectivePlatform) {
    TargetPlatform.android =>
      androidConfiguration.mode == AndroidPrintMode.escPos
          ? thermalFactory(androidConfiguration)
          : androidFactory(androidConfiguration),
    TargetPlatform.iOS => iosFactory(iosPrintMode),
    _ => Future<ManagedPrintPlatformResources>.value(
      const ManagedPrintPlatformResources(
        platform: UnsupportedReportPrintPlatform(),
      ),
    ),
  };
}
