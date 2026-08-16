import 'bridge_config.dart';
import 'bridge_selected_template.dart';

class FileRef {
  const FileRef({required this.path, this.url});

  final String path;
  final String? url;

  static FileRef? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    final path = raw['path'];
    if (path is! String || path.isEmpty) {
      return null;
    }
    return FileRef(path: path, url: raw['url'] as String?);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'path': path, if (url != null) 'url': url};
  }
}

/// Runtime session metadata prepared by Bridge before Presenter opens.
class RuntimeSession {
  const RuntimeSession({
    required this.sessionId,
    required this.reportType,
    this.reportName,
    this.mode,
    this.locale,
    this.direction,
    this.presenterUrl,
    this.selectedTemplate,
    this.branding,
    this.seedReportData,
    this.template,
    this.session,
    this.apiHeaders,
  });

  final String sessionId;
  final String reportType;
  final String? reportName;
  final String? mode;
  final String? locale;
  final String? direction;
  final String? presenterUrl;
  final SelectedTemplate? selectedTemplate;
  final BrandConfig? branding;
  final FileRef? seedReportData;
  final FileRef? template;
  final FileRef? session;
  final ApiHeaderConfig? apiHeaders;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'sessionId': sessionId,
      'reportType': reportType,
      if (reportName != null) 'reportName': reportName,
      if (mode != null) 'mode': mode,
      if (locale != null) 'locale': locale,
      if (direction != null) 'direction': direction,
      if (presenterUrl != null) 'presenterUrl': presenterUrl,
      if (selectedTemplate != null)
        'selectedTemplate': selectedTemplate!.toMap(),
      if (branding != null) 'branding': branding!.toMap(),
      if (seedReportData != null) 'seedReportData': seedReportData!.toMap(),
      if (template != null) 'template': template!.toMap(),
      if (session != null) 'session': session!.toMap(),
      if (apiHeaders != null) 'apiHeaders': apiHeaders!.toRedactedMap(),
    };
  }
}
