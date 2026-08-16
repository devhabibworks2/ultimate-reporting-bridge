import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../contracts/external_printer_contract.dart';
import 'android_print_configuration.dart';
import 'bridge_platform_adapters.dart';

typedef AndroidInstallPrompt = Future<bool> Function(Uri installUri);
typedef DeferredReportPrintResultCallback =
    void Function(ReportPrintResult result);

abstract interface class AndroidPrintNativeClient {
  Future<ReportPrintResult> printWithSystemManager({
    required Uint8List pdfBytes,
    required String documentTitle,
    required int maximumPdfBytes,
  });

  Future<bool> isExternalAppInstalled({
    required String packageName,
    required String action,
    required String mimeType,
  });

  Future<ReportPrintResult> printWithExternalApp(
    AndroidExternalPrintPayload payload,
  );

  Future<bool> openInstallUri(Uri installUri);

  Future<void> cleanupStaleFiles(Duration ttl);
}

final class AndroidExternalPrintPayload {
  AndroidExternalPrintPayload({
    required Uint8List pdfBytes,
    required this.filename,
    required this.maximumPdfBytes,
    required this.staleFileTtl,
    required this.packageName,
    required this.action,
    required this.mimeType,
    required this.contractVersion,
    required this.jobId,
    required this.documentTitle,
    required this.unit,
    required this.layout,
    required this.size,
    required this.width,
    required this.height,
    required this.orientation,
    required this.languageCode,
    required this.language,
    required Map<String, Object?> extra,
  }) : pdfBytes = Uint8List.fromList(pdfBytes),
       extra = Map<String, Object?>.unmodifiable(extra);

  final Uint8List pdfBytes;
  final String filename;
  final int maximumPdfBytes;
  final Duration staleFileTtl;
  final String packageName;
  final String action;
  final String mimeType;
  final String contractVersion;
  final String jobId;
  final String documentTitle;
  final String unit;
  final String layout;
  final String size;
  final double width;
  final double height;
  final String orientation;
  final String languageCode;
  final int language;
  final Map<String, Object?> extra;

  Map<String, Object?> toMethodArguments() => <String, Object?>{
    'pdfBytes': pdfBytes,
    'filename': filename,
    'maximumPdfBytes': maximumPdfBytes,
    'staleFileTtlMillis': staleFileTtl.inMilliseconds,
    'packageName': packageName,
    'action': action,
    'mimeType': mimeType,
    'contractVersion': contractVersion,
    'jobId': jobId,
    'documentTitle': documentTitle,
    'unit': unit,
    'layout': layout,
    'size': size,
    'width': width,
    'height': height,
    'orientation': orientation,
    'language_code': languageCode,
    'language': language,
    'extra': extra,
  };
}

final class MethodChannelAndroidPrintNativeClient
    implements AndroidPrintNativeClient {
  const MethodChannelAndroidPrintNativeClient({
    MethodChannel channel = const MethodChannel(
      'reporting_bridge_flutter/print',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<ReportPrintResult> printWithSystemManager({
    required Uint8List pdfBytes,
    required String documentTitle,
    required int maximumPdfBytes,
  }) async {
    final response = await _channel.invokeMethod<Object?>('printSystem', {
      'pdfBytes': pdfBytes,
      'documentTitle': documentTitle,
      'maximumPdfBytes': maximumPdfBytes,
    });
    return _decodeResult(response);
  }

  @override
  Future<bool> isExternalAppInstalled({
    required String packageName,
    required String action,
    required String mimeType,
  }) async {
    final installed = await _channel.invokeMethod<bool>(
      'isExternalAppInstalled',
      <String, Object?>{
        'packageName': packageName,
        'action': action,
        'mimeType': mimeType,
      },
    );
    return installed ?? false;
  }

  @override
  Future<ReportPrintResult> printWithExternalApp(
    AndroidExternalPrintPayload payload,
  ) async {
    final response = await _channel.invokeMethod<Object?>(
      'printExternal',
      payload.toMethodArguments(),
    );
    return _decodeResult(response);
  }

  @override
  Future<bool> openInstallUri(Uri installUri) async {
    final opened = await _channel.invokeMethod<bool>(
      'openInstallUri',
      <String, Object?>{'installUri': installUri.toString()},
    );
    return opened ?? false;
  }

  @override
  Future<void> cleanupStaleFiles(Duration ttl) => _channel.invokeMethod<void>(
    'cleanupStaleFiles',
    <String, Object?>{'staleFileTtlMillis': ttl.inMilliseconds},
  );

  static ReportPrintResult _decodeResult(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return const ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'nativeMalformedResult',
      );
    }
    final statusName = value['status'];
    final status = switch (statusName) {
      'submitted' => ReportPrintStatus.submitted,
      'cancelled' => ReportPrintStatus.cancelled,
      'setupRequired' => ReportPrintStatus.setupRequired,
      'failed' => ReportPrintStatus.failed,
      'unsupportedContract' => ReportPrintStatus.unsupportedContract,
      'unsupportedPaperConversion' =>
        ReportPrintStatus.unsupportedPaperConversion,
      'appNotInstalled' => ReportPrintStatus.appNotInstalled,
      _ => ReportPrintStatus.failed,
    };
    return ReportPrintResult(
      status: status,
      errorCode: value['errorCode'] as String?,
      diagnostic: value['diagnostic'] as String?,
    );
  }
}

final class AndroidReportPrintPlatform extends WidgetsBindingObserver
    implements ReportPrintPlatform {
  AndroidReportPrintPlatform({
    required this.configuration,
    AndroidPrintNativeClient? nativeClient,
    this.installPrompt,
    this.onDeferredResult,
    bool observeLifecycle = true,
  }) : _nativeClient =
           nativeClient ?? const MethodChannelAndroidPrintNativeClient(),
       _observeLifecycle = observeLifecycle {
    if (_observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  static const Set<String> reservedExtraFields = <String>{
    'contractVersion',
    'jobId',
    'documentTitle',
    'unit',
    'layout',
    'size',
    'width',
    'height',
    'orientation',
    'language_code',
    'language',
    'extra',
  };

  final AndroidPrintConfiguration configuration;
  final AndroidInstallPrompt? installPrompt;
  final DeferredReportPrintResultCallback? onDeferredResult;
  final AndroidPrintNativeClient _nativeClient;
  final bool _observeLifecycle;

  ReportPrintRequest? _pendingExternalRequest;
  bool _active = false;
  bool _resumeCheckInProgress = false;
  bool _disposed = false;

  @override
  Future<ReportPrintResult> printPdf(ReportPrintRequest request) async {
    if (_disposed) {
      return const ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'platformDisposed',
      );
    }
    if (_active) {
      return const ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'printInProgress',
      );
    }

    final validationFailure = _validate(request);
    if (validationFailure != null) return validationFailure;

    _active = true;
    try {
      if (configuration.mode == AndroidPrintMode.systemPrintManager) {
        return await _nativeClient.printWithSystemManager(
          pdfBytes: request.pdfBytes,
          documentTitle: request.documentTitle,
          maximumPdfBytes: _effectiveMaximumPdfBytes,
        );
      }
      return await _printExternal(request);
    } on PlatformException catch (error) {
      return ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: error.code,
        diagnostic: error.message,
      );
    } catch (error) {
      return ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'platformInvocationFailed',
        diagnostic: error.toString(),
      );
    } finally {
      _active = false;
    }
  }

  Future<ReportPrintResult> _printExternal(ReportPrintRequest request) async {
    final external = configuration.externalApp!;
    await _nativeClient.cleanupStaleFiles(external.staleFileTtl);

    final installed = await _nativeClient.isExternalAppInstalled(
      packageName: external.packageName,
      action: external.action,
      mimeType: external.mimeType,
    );
    if (installed) {
      _pendingExternalRequest = null;
      return _printExternalInstalled(request, external);
    }

    final prompt = installPrompt;
    if (prompt == null || !await prompt(external.installUri)) {
      return const ReportPrintResult(
        status: ReportPrintStatus.appNotInstalled,
        errorCode: 'externalPrinterNotInstalled',
      );
    }

    final opened = await _nativeClient.openInstallUri(external.installUri);
    if (!opened) {
      return const ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'installUriOpenFailed',
      );
    }

    _pendingExternalRequest = request;
    return const ReportPrintResult(
      status: ReportPrintStatus.setupRequired,
      errorCode: 'externalPrinterInstallRequired',
    );
  }

  Future<ReportPrintResult> _printExternalInstalled(
    ReportPrintRequest request,
    AndroidExternalPrinterConfiguration external,
  ) {
    final language = request.document.legacyLanguage;
    return _nativeClient.printWithExternalApp(
      AndroidExternalPrintPayload(
        pdfBytes: request.pdfBytes,
        filename: request.filename,
        maximumPdfBytes: external.maximumPdfBytes,
        staleFileTtl: external.staleFileTtl,
        packageName: external.packageName,
        action: external.action,
        mimeType: external.mimeType,
        contractVersion: external.contractVersion,
        jobId: request.jobId,
        documentTitle: request.documentTitle,
        unit: request.document.unit,
        layout: request.document.layout,
        size: request.document.size,
        width: request.document.width,
        height: request.document.height,
        orientation: request.document.orientation,
        languageCode: request.document.languageCode.trim().toLowerCase(),
        language: language,
        extra: request.extra,
      ),
    );
  }

  int get _effectiveMaximumPdfBytes {
    final configured = configuration.maximumPdfBytes;
    if (configured <= 0 || configured > defaultMaximumPdfBytes) {
      return defaultMaximumPdfBytes;
    }
    return configured;
  }

  ReportPrintResult? _validate(ReportPrintRequest request) {
    if (request.pdfBytes.isEmpty) {
      return const ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'emptyPdf',
      );
    }
    if (request.pdfBytes.length > _effectiveMaximumPdfBytes) {
      return const ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'pdfTooLarge',
      );
    }
    if (request.filename.trim().isEmpty ||
        request.jobId.trim().isEmpty ||
        request.documentTitle.trim().isEmpty) {
      return const ReportPrintResult(
        status: ReportPrintStatus.unsupportedContract,
        errorCode: 'missingRequiredPrintField',
      );
    }

    final reserved = request.extra.keys
        .where(reservedExtraFields.contains)
        .toList(growable: false);
    if (reserved.isNotEmpty) {
      return ReportPrintResult(
        status: ReportPrintStatus.unsupportedContract,
        errorCode: 'reservedExtraField',
        diagnostic: reserved.join(','),
      );
    }
    if (!_supportsChannelValue(request.extra)) {
      return const ReportPrintResult(
        status: ReportPrintStatus.unsupportedContract,
        errorCode: 'unsupportedExtraValue',
      );
    }

    if (configuration.mode == AndroidPrintMode.externalApp &&
        legacyExternalLanguageValue(request.document.languageCode) == null) {
      return ReportPrintResult(
        status: ReportPrintStatus.unsupportedContract,
        errorCode: 'unsupportedLanguage',
        diagnostic: request.document.languageCode,
      );
    }
    return null;
  }

  static bool _supportsChannelValue(Object? value) {
    if (value == null || value is bool || value is int || value is String) {
      return true;
    }
    if (value is double) {
      return value.isFinite;
    }
    if (value is List<Object?>) {
      return value.every(_supportsChannelValue);
    }
    if (value is Map<Object?, Object?>) {
      return value.keys.every((key) => key is String) &&
          value.values.every(_supportsChannelValue);
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(recheckPendingExternalPrint());
    }
  }

  Future<ReportPrintResult?> recheckPendingExternalPrint() async {
    if (_disposed ||
        _resumeCheckInProgress ||
        _active ||
        configuration.mode != AndroidPrintMode.externalApp) {
      return null;
    }
    final pending = _pendingExternalRequest;
    if (pending == null) return null;

    _resumeCheckInProgress = true;
    try {
      final external = configuration.externalApp!;
      final installed = await _nativeClient.isExternalAppInstalled(
        packageName: external.packageName,
        action: external.action,
        mimeType: external.mimeType,
      );
      if (!installed) return null;

      _pendingExternalRequest = null;
      _active = true;
      final result = await _printExternalInstalled(pending, external);
      onDeferredResult?.call(result);
      return result;
    } on PlatformException catch (error) {
      final result = ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: error.code,
        diagnostic: error.message,
      );
      onDeferredResult?.call(result);
      return result;
    } catch (error) {
      final result = ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'resumeRecheckFailed',
        diagnostic: error.toString(),
      );
      onDeferredResult?.call(result);
      return result;
    } finally {
      _active = false;
      _resumeCheckInProgress = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pendingExternalRequest = null;
    if (_observeLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
  }
}
