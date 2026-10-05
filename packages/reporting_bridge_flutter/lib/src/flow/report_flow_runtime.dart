import 'package:reporting_bridge/reporting_bridge.dart';

import '../client/report_server_connection.dart';
import '../persistence/report_flow_preference_store.dart';
import '../platform/bridge_platform_adapters.dart';
import '../platform/presenter_surface_binding.dart';
import '../presenter/report_resource_preparation_service.dart';
import '../printing/thermal_printer_controller.dart';

class ReportFlowRuntime {
  ReportFlowRuntime({
    required this.connection,
    required this.bridgeClient,
    ReportResourcePreparationOperations? resourcePreparation,
    required this.preferences,
    required this.filePlatform,
    required this.surfaceBinding,
    this.printPlatform = const UnsupportedReportPrintPlatform(),
    this.thermalPrinterSettings,
    this.supportSharePlatform = const UnsupportedReportSupportSharePlatform(),
  }) : resourcePreparation =
           resourcePreparation ??
           ReportResourcePreparationService(bridgeClient: bridgeClient),
       hasCustomResourcePreparation = resourcePreparation != null;

  final ReportServerConnection connection;
  final ReportingBridgeClient bridgeClient;
  final ReportResourcePreparationOperations resourcePreparation;
  final bool hasCustomResourcePreparation;
  final ReportFlowPreferenceStore preferences;
  final ReportFilePlatform filePlatform;
  final PresenterSurfaceBinding surfaceBinding;
  final ReportPrintPlatform printPlatform;
  final ThermalPrinterSettingsController? thermalPrinterSettings;
  final ReportSupportSharePlatform supportSharePlatform;
}
