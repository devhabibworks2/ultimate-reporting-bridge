import 'package:reporting_bridge/reporting_bridge.dart';

import '../client/report_server_connection.dart';
import '../persistence/report_flow_preference_store.dart';
import '../platform/bridge_platform_adapters.dart';
import '../platform/presenter_surface_binding.dart';
import '../printing/thermal_printer_controller.dart';

class ReportFlowRuntime {
  const ReportFlowRuntime({
    required this.connection,
    required this.bridgeClient,
    required this.preferences,
    required this.filePlatform,
    required this.surfaceBinding,
    this.printPlatform = const UnsupportedReportPrintPlatform(),
    this.thermalPrinterSettings,
    this.supportSharePlatform = const UnsupportedReportSupportSharePlatform(),
  });

  final ReportServerConnection connection;
  final ReportingBridgeClient bridgeClient;
  final ReportFlowPreferenceStore preferences;
  final ReportFilePlatform filePlatform;
  final PresenterSurfaceBinding surfaceBinding;
  final ReportPrintPlatform printPlatform;
  final ThermalPrinterSettingsController? thermalPrinterSettings;
  final ReportSupportSharePlatform supportSharePlatform;
}
