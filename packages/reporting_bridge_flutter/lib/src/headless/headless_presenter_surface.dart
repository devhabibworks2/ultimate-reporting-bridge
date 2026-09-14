import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../platform/presenter_surface_binding.dart';

abstract interface class HeadlessPresenterSurface {
  Future<void> start({
    required PresenterSessionLaunch launch,
    required String templateName,
    required ReportFlowController controller,
    required PresenterSurfaceBinding surfaceBinding,
  });

  Future<void> dispose();
}

typedef HeadlessPresenterSurfaceFactory = HeadlessPresenterSurface Function();
