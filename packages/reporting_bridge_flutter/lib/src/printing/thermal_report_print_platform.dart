import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../platform/bridge_platform_adapters.dart';
import '../persistence/thermal_printer_settings_store.dart';
import 'thermal_pdf_artifact_store.dart';
import 'thermal_printer_models.dart';
import 'thermal_printer_native_client.dart';

abstract interface class ThermalPrintProgressSource {
  void setPrintProgressListener(void Function(ThermalPrintProgress progress)? value);
}

abstract interface class ThermalBluetoothAvailabilitySink {
  void setKnownBluetoothAvailability(
    ThermalPrinterProfile? profile,
    ThermalPrinterAvailability availability,
  );
}

abstract interface class ThermalPrinterTestPlatform {
  Future<ReportPrintResult> testPrint(ThermalPrinterProfile profile);
}

final class ThermalReportPrintPlatform
    implements
        ReportPrintPlatform,
        ThermalPrintProgressSource,
        ThermalBluetoothAvailabilitySink,
        ThermalPrinterTestPlatform {
  ThermalReportPrintPlatform({
    required ThermalPrinterSettingsStore settingsStore,
    required ThermalPdfArtifactStore artifactStore,
    required ThermalPrinterNativeClient nativeClient,
  }) : _settingsStore = settingsStore,
       _artifactStore = artifactStore,
       _nativeClient = nativeClient {
    _nativeClient.setProgressListener((progress) => _onProgress?.call(progress));
  }

  final ThermalPrinterSettingsStore _settingsStore;
  final ThermalPdfArtifactStore _artifactStore;
  final ThermalPrinterNativeClient _nativeClient;
  void Function(ThermalPrintProgress progress)? _onProgress;
  Future<ReportPrintResult>? _activePrint;
  String? _knownBluetoothAddress;
  ThermalPrinterAvailability _knownBluetoothAvailability =
      ThermalPrinterAvailability.unknown;

  /// Lets settings avoid a known-doomed connection attempt while retaining the
  /// saved profile for the user to repair.
  @override
  void setKnownBluetoothAvailability(
    ThermalPrinterProfile? profile,
    ThermalPrinterAvailability availability,
  ) {
    _knownBluetoothAddress =
        profile?.connectionType == ThermalPrinterConnectionType.bluetooth
        ? profile?.bluetoothAddress?.trim().toUpperCase()
        : null;
    _knownBluetoothAvailability = availability;
  }

  @override
  Future<ReportPrintResult> printPdf(ReportPrintRequest request) => _startPrint(
    () => _printBytes(jobId: request.jobId, bytes: request.pdfBytes),
  );

  @override
  Future<ReportPrintResult> testPrint(ThermalPrinterProfile profile) => _startPrint(
    () async {
      final data = await rootBundle.load(
        'packages/reporting_bridge_flutter/assets/printing/thermal_printer_test.pdf',
      );
      return _printBytes(
        jobId: 'thermal-test-${DateTime.now().microsecondsSinceEpoch}',
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        profile: profile,
      );
    },
  );

  Future<ReportPrintResult> _startPrint(
    Future<ReportPrintResult> Function() operation,
  ) {
    final active = _activePrint;
    if (active != null) {
      return Future<ReportPrintResult>.value(
        const ReportPrintResult(
          status: ReportPrintStatus.failed,
          errorCode: 'thermalBusy',
        ),
      );
    }
    late final Future<ReportPrintResult> future;
    future = operation().whenComplete(() {
      if (identical(_activePrint, future)) _activePrint = null;
    });
    _activePrint = future;
    return future;
  }

  Future<ReportPrintResult> _printBytes({
    required String jobId,
    required Uint8List bytes,
    ThermalPrinterProfile? profile,
  }) async {
    final resolvedProfile = profile ?? await _settingsStore.loadDefaultProfile();
    if (resolvedProfile == null || !resolvedProfile.isValid) {
      return const ReportPrintResult(status: ReportPrintStatus.setupRequired);
    }
    if (_isKnownUnavailableBluetoothProfile(resolvedProfile)) {
      return const ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'savedBluetoothPrinterUnavailable',
      );
    }
    File? artifact;
    try {
      _onProgress?.call(
        ThermalPrintProgress(jobId: jobId, phase: ThermalPrintPhase.preparing),
      );
      artifact = await _artifactStore.stage(jobId: jobId, bytes: bytes);
      final result = await _nativeClient.printPdf(
        jobId: jobId,
        pdfPath: artifact.path,
        profile: resolvedProfile,
      );
      return _toReportResult(result);
    } on ArgumentError catch (error) {
      return ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'invalidPdf',
        diagnostic: error.message?.toString(),
      );
    } catch (error) {
      return ReportPrintResult(
        status: ReportPrintStatus.failed,
        errorCode: 'thermalNativeFailure',
        diagnostic: error.toString(),
      );
    } finally {
      if (artifact != null) await _artifactStore.delete(artifact);
    }
  }

  bool _isKnownUnavailableBluetoothProfile(ThermalPrinterProfile profile) =>
      profile.connectionType == ThermalPrinterConnectionType.bluetooth &&
      _knownBluetoothAvailability == ThermalPrinterAvailability.unavailable &&
      profile.bluetoothAddress?.trim().toUpperCase() == _knownBluetoothAddress;

  ReportPrintResult _toReportResult(ThermalPrintOperationResult result) =>
      switch (result.status) {
        ThermalPrintResultStatus.submitted => const ReportPrintResult.submitted(),
        ThermalPrintResultStatus.setupRequired => const ReportPrintResult(
          status: ReportPrintStatus.setupRequired,
        ),
        _ => ReportPrintResult(
          status: ReportPrintStatus.failed,
          errorCode: result.errorCode ?? result.status.name,
          diagnostic: result.diagnostic,
        ),
      };

  @override
  void setPrintProgressListener(void Function(ThermalPrintProgress progress)? value) {
    _onProgress = value;
  }

  void dispose() {
    _onProgress = null;
    _nativeClient.dispose();
  }
}
