import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/src/persistence/thermal_printer_settings_store.dart';
import 'package:reporting_bridge_flutter/src/platform/bridge_platform_adapters.dart';
import 'package:reporting_bridge_flutter/src/printing/thermal_pdf_artifact_store.dart';
import 'package:reporting_bridge_flutter/src/printing/thermal_printer_models.dart';
import 'package:reporting_bridge_flutter/src/printing/thermal_printer_native_client.dart';
import 'package:reporting_bridge_flutter/src/printing/thermal_report_print_platform.dart';

void main() {
  group('ThermalPdfArtifactStore', () {
    late Directory directory;
    late ThermalPdfArtifactStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'thermal-artifact-test-',
      );
      store = ThermalPdfArtifactStore.forDirectory(directory);
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('rejects empty and oversized PDFs', () async {
      expect(
        () => store.stage(jobId: 'empty', bytes: Uint8List(0)),
        throwsArgumentError,
      );

      expect(
        () => store.stage(
          jobId: 'oversized',
          bytes: Uint8List(ThermalPdfArtifactStore.maximumPdfBytes + 1),
        ),
        throwsArgumentError,
      );
    });

    test('sanitizes job ids and deletes staged files', () async {
      final file = await store.stage(
        jobId: '../unsafe job/42',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );

      expect(file.parent.path, directory.path);
      expect(file.path.contains('unsafe_job_42.pdf'), isTrue);
      expect(await file.exists(), isTrue);

      await store.delete(file);

      expect(await file.exists(), isFalse);
    });
  });

  group('ThermalReportPrintPlatform', () {
    late Directory directory;
    late ThermalPdfArtifactStore artifactStore;
    late _FakeSettingsStore settingsStore;
    late _FakeNativeClient nativeClient;
    late ThermalReportPrintPlatform platform;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'thermal-platform-test-',
      );
      artifactStore = ThermalPdfArtifactStore.forDirectory(directory);
      settingsStore = _FakeSettingsStore(profile: _tcpProfile);
      nativeClient = _FakeNativeClient();
      platform = ThermalReportPrintPlatform(
        settingsStore: settingsStore,
        artifactStore: artifactStore,
        nativeClient: nativeClient,
      );
    });

    tearDown(() async {
      platform.dispose();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('returns setupRequired when no valid saved profile exists', () async {
      settingsStore.profile = null;

      final result = await platform.printPdf(_request());

      expect(result.status, ReportPrintStatus.setupRequired);
      expect(nativeClient.printCalls, 0);
    });

    test('returns invalidPdf for empty bytes without calling native', () async {
      final result = await platform.printPdf(_request(bytes: Uint8List(0)));

      expect(result.status, ReportPrintStatus.failed);
      expect(result.errorCode, 'invalidPdf');
      expect(nativeClient.printCalls, 0);
    });

    test('rejects a saved bluetooth printer known to be unavailable', () async {
      settingsStore.profile = _bluetoothProfile;
      platform.setKnownBluetoothAvailability(
        _bluetoothProfile,
        ThermalPrinterAvailability.unavailable,
      );

      final result = await platform.printPdf(_request());

      expect(result.status, ReportPrintStatus.failed);
      expect(result.errorCode, 'savedBluetoothPrinterUnavailable');
      expect(nativeClient.printCalls, 0);
    });

    test('maps native submitted and typed failure results', () async {
      nativeClient.result = const ThermalPrintOperationResult(
        status: ThermalPrintResultStatus.submitted,
      );

      final submitted = await platform.printPdf(_request(jobId: 'submitted'));

      expect(submitted.status, ReportPrintStatus.submitted);
      expect(await directory.list().toList(), isEmpty);

      nativeClient.result = const ThermalPrintOperationResult(
        status: ThermalPrintResultStatus.connectionFailed,
        errorCode: 'tcpConnectionRefused',
        diagnostic: 'refused',
      );

      final failed = await platform.printPdf(_request(jobId: 'failed'));

      expect(failed.status, ReportPrintStatus.failed);
      expect(failed.errorCode, 'tcpConnectionRefused');
      expect(failed.diagnostic, 'refused');
      expect(await directory.list().toList(), isEmpty);
    });

    test('returns busy while a prior print is still active', () async {
      final completer = Completer<ThermalPrintOperationResult>();
      nativeClient.pendingResult = completer;

      final first = platform.printPdf(_request(jobId: 'first'));
      final second = await platform.printPdf(_request(jobId: 'second'));

      expect(second.status, ReportPrintStatus.failed);
      expect(second.errorCode, 'thermalBusy');

      completer.complete(
        const ThermalPrintOperationResult(
          status: ThermalPrintResultStatus.submitted,
        ),
      );
      expect((await first).status, ReportPrintStatus.submitted);
      expect(nativeClient.printCalls, 1);
    });

    test('forwards progress and detaches native listener on dispose', () async {
      ThermalPrintProgress? observed;
      platform.setPrintProgressListener((progress) => observed = progress);

      nativeClient.emit(
        const ThermalPrintProgress(
          jobId: 'progress',
          phase: ThermalPrintPhase.transmitting,
          bytesSent: 10,
          totalBytes: 20,
        ),
      );

      expect(observed?.jobId, 'progress');
      expect(observed?.phase, ThermalPrintPhase.transmitting);

      platform.dispose();

      expect(nativeClient.disposed, isTrue);
      expect(nativeClient.listener, isNull);
    });

    test('cleans staged artifacts when native throws', () async {
      nativeClient.error = StateError('boom');

      final result = await platform.printPdf(_request(jobId: 'throws'));

      expect(result.status, ReportPrintStatus.failed);
      expect(result.errorCode, 'thermalNativeFailure');
      expect(await directory.list().toList(), isEmpty);
    });
  });
}

final _tcpProfile = ThermalPrinterProfile(
  displayName: 'TCP printer',
  connectionType: ThermalPrinterConnectionType.tcp,
  printableWidthPx: ThermalPrinterProfile.width58mm,
  tcpHost: '127.0.0.1',
  tcpPort: 9100,
);

final _bluetoothProfile = ThermalPrinterProfile(
  displayName: 'Bluetooth printer',
  connectionType: ThermalPrinterConnectionType.bluetooth,
  printableWidthPx: ThermalPrinterProfile.width58mm,
  bluetoothAddress: 'AA:BB:CC:DD:EE:FF',
);

ReportPrintRequest _request({String jobId = 'job-1', Uint8List? bytes}) =>
    ReportPrintRequest(
      pdfBytes: bytes ?? Uint8List.fromList(<int>[1, 2, 3, 4]),
      filename: 'report.pdf',
      jobId: jobId,
      documentTitle: 'Report',
      document: const ReportPrintDocumentMetadata(
        unit: 'mm',
        layout: 'receipt',
        size: 'custom',
        width: 58,
        height: 100,
        orientation: 'portrait',
        languageCode: 'en',
      ),
    );

final class _FakeSettingsStore implements ThermalPrinterSettingsStore {
  _FakeSettingsStore({this.profile});

  ThermalPrinterProfile? profile;

  @override
  Future<ThermalPrinterProfile?> loadDefaultProfile() async => profile;

  @override
  Future<void> removeDefaultProfile() async => profile = null;

  @override
  Future<void> saveDefaultProfile(ThermalPrinterProfile value) async {
    profile = value;
  }
}

final class _FakeNativeClient implements ThermalPrinterNativeClient {
  ThermalPrintOperationResult result = const ThermalPrintOperationResult(
    status: ThermalPrintResultStatus.submitted,
  );
  Completer<ThermalPrintOperationResult>? pendingResult;
  Object? error;
  int printCalls = 0;
  bool disposed = false;
  void Function(ThermalPrintProgress progress)? listener;

  void emit(ThermalPrintProgress progress) => listener?.call(progress);

  @override
  Future<ThermalPrinterPermissionState> bluetoothPermissionState() async =>
      ThermalPrinterPermissionState.granted;

  @override
  void dispose() {
    disposed = true;
    listener = null;
  }

  @override
  Future<List<ThermalPrinterDevice>> listConnectedUsbPrinters() async =>
      const <ThermalPrinterDevice>[];

  @override
  Future<List<ThermalPrinterDevice>> listPairedBluetoothDevices() async =>
      const <ThermalPrinterDevice>[];

  @override
  Future<ThermalPrintOperationResult> printPdf({
    required String jobId,
    required String pdfPath,
    required ThermalPrinterProfile profile,
  }) async {
    printCalls += 1;
    final thrown = error;
    if (thrown != null) throw thrown;
    final pending = pendingResult;
    if (pending != null) return pending.future;
    return result;
  }

  @override
  Future<ThermalPrinterPermissionState> requestBluetoothPermissions() async =>
      ThermalPrinterPermissionState.granted;

  @override
  Future<ThermalPrinterPermissionState> requestUsbPermission(
    ThermalPrinterDevice device,
  ) async => ThermalPrinterPermissionState.granted;

  @override
  void setProgressListener(
    void Function(ThermalPrintProgress progress)? value,
  ) {
    listener = value;
  }

  @override
  Future<ThermalPrinterPermissionState> usbPermission(
    ThermalPrinterDevice device,
  ) async => ThermalPrinterPermissionState.granted;
}
