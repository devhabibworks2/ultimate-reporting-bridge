import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../contracts/report_contract_values.dart';

abstract interface class ReportFilePlatform {
  Future<bool> savePdf(Uint8List bytes, String filename);
  Future<void> sharePdf(Uint8List bytes, String filename);
}

abstract interface class ReportSupportSharePlatform {
  Future<void> shareArchive(
    Uint8List bytes,
    String filename, {
    Rect? sharePositionOrigin,
  });
}

final class SharePlusReportSupportSharePlatform
    implements ReportSupportSharePlatform {
  const SharePlusReportSupportSharePlatform();

  @override
  Future<void> shareArchive(
    Uint8List bytes,
    String filename, {
    Rect? sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile.fromData(bytes, mimeType: 'application/zip')],
        fileNameOverrides: <String>[filename],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}

final class UnsupportedReportSupportSharePlatform
    implements ReportSupportSharePlatform {
  const UnsupportedReportSupportSharePlatform();

  @override
  Future<void> shareArchive(
    Uint8List bytes,
    String filename, {
    Rect? sharePositionOrigin,
  }) {
    return Future<void>.error(
      UnsupportedError('Development-support sharing is unavailable.'),
    );
  }
}

enum ReportPrintStatus {
  submitted,
  cancelled,
  setupRequired,
  failed,
  unsupportedContract,
  unsupportedPaperConversion,
  appNotInstalled,
}

/// Document metadata carried into the platform print boundary.
///
/// Values must come from selected-template metadata, not from a competing
/// Host print-language/layout override.
final class ReportPrintDocumentMetadata {
  const ReportPrintDocumentMetadata({
    required this.unit,
    required this.layout,
    required this.size,
    required this.width,
    required this.height,
    required this.orientation,
    required this.languageCode,
  });

  final String unit;
  final String layout;
  final String size;
  final double width;
  final double height;
  final String orientation;
  final String languageCode;

  /// Legacy external printer language integer (`ar→1`, `en→2`).
  int get legacyLanguage =>
      ReportLanguage.parseCanonical(languageCode).legacyExternalValue;
}

final class ReportPrintRequest {
  ReportPrintRequest({
    required Uint8List pdfBytes,
    required this.filename,
    required this.jobId,
    required this.documentTitle,
    required this.document,
    this.extra = const <String, Object?>{},
  }) : pdfBytes = Uint8List.fromList(pdfBytes);

  final Uint8List pdfBytes;
  final String filename;
  final String jobId;
  final String documentTitle;
  final ReportPrintDocumentMetadata document;
  final Map<String, Object?> extra;
}

final class ReportPrintResult {
  const ReportPrintResult({
    required this.status,
    this.errorCode,
    this.diagnostic,
  });

  const ReportPrintResult.submitted()
    : status = ReportPrintStatus.submitted,
      errorCode = null,
      diagnostic = null;

  const ReportPrintResult.cancelled()
    : status = ReportPrintStatus.cancelled,
      errorCode = null,
      diagnostic = null;

  final ReportPrintStatus status;
  final String? errorCode;
  final String? diagnostic;

  bool get isSubmitted => status == ReportPrintStatus.submitted;
}

abstract interface class ReportPrintPlatform {
  Future<ReportPrintResult> printPdf(ReportPrintRequest request);
}

final class UnsupportedReportPrintPlatform implements ReportPrintPlatform {
  const UnsupportedReportPrintPlatform();

  @override
  Future<ReportPrintResult> printPdf(ReportPrintRequest request) async {
    return const ReportPrintResult(
      status: ReportPrintStatus.failed,
      errorCode: 'platformUnsupported',
    );
  }
}

class DefaultReportFilePlatform implements ReportFilePlatform {
  const DefaultReportFilePlatform();

  @override
  Future<bool> savePdf(Uint8List bytes, String filename) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save PDF',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
      bytes: bytes,
    );
    return path != null;
  }

  @override
  Future<void> sharePdf(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);
}
