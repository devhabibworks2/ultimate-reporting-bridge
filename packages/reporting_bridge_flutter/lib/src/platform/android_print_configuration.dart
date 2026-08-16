import '../contracts/external_printer_contract.dart';

const int defaultMaximumPdfBytes = 50 * 1024 * 1024;
const String ultimatePrinterContractVersion = '1';

enum AndroidPrintMode { systemPrintManager, externalApp }

final class AndroidExternalPrinterConfiguration {
  AndroidExternalPrinterConfiguration({
    required this.installUri,
    this.packageName = ultimatePrinterPackageName,
    this.action = ultimatePrinterAction,
    this.maximumPdfBytes = defaultMaximumPdfBytes,
    this.staleFileTtl = const Duration(hours: 24),
  }) {
    if (packageName != ultimatePrinterPackageName) {
      throw ArgumentError.value(
        packageName,
        'packageName',
        'V1 requires $ultimatePrinterPackageName.',
      );
    }
    if (action != ultimatePrinterAction) {
      throw ArgumentError.value(
        action,
        'action',
        'V1 requires $ultimatePrinterAction.',
      );
    }
    if (!installUri.hasScheme) {
      throw ArgumentError.value(
        installUri,
        'installUri',
        'Must be an absolute URI.',
      );
    }
    if (maximumPdfBytes <= 0 || maximumPdfBytes > defaultMaximumPdfBytes) {
      throw ArgumentError.value(
        maximumPdfBytes,
        'maximumPdfBytes',
        'Must be between 1 and $defaultMaximumPdfBytes bytes.',
      );
    }
    if (staleFileTtl <= Duration.zero) {
      throw ArgumentError.value(
        staleFileTtl,
        'staleFileTtl',
        'Must be greater than zero.',
      );
    }
  }

  final Uri installUri;
  final String packageName;
  final String action;
  final int maximumPdfBytes;
  final Duration staleFileTtl;

  String get mimeType => ultimatePrinterMimeType;
  String get contractVersion => ultimatePrinterContractVersion;
}

final class AndroidPrintConfiguration {
  const AndroidPrintConfiguration.systemPrintManager({
    this.maximumPdfBytes = defaultMaximumPdfBytes,
  }) : assert(maximumPdfBytes > 0),
       mode = AndroidPrintMode.systemPrintManager,
       externalApp = null;

  AndroidPrintConfiguration.externalApp({
    required AndroidExternalPrinterConfiguration configuration,
  }) : mode = AndroidPrintMode.externalApp,
       maximumPdfBytes = configuration.maximumPdfBytes,
       externalApp = configuration;

  final AndroidPrintMode mode;
  final int maximumPdfBytes;
  final AndroidExternalPrinterConfiguration? externalApp;
}
