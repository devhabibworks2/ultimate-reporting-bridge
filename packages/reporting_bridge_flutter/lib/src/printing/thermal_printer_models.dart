import 'dart:convert';

/// The physical link used by a saved thermal-printer profile.
enum ThermalPrinterConnectionType { bluetooth, usb, tcp }

enum ThermalPrinterPermissionState {
  granted,
  denied,
  permanentlyDenied,
  activityUnavailable,
  unsupported,
}

/// Whether Android can currently see the Bluetooth printer saved in the profile.
/// A saved profile is intentionally retained when this becomes unavailable.
enum ThermalPrinterAvailability { unknown, available, unavailable }

enum ThermalPrintPhase {
  preparing,
  connecting,
  rasterizing,
  transmitting,
  printing,
}

enum ThermalPrintResultStatus {
  submitted,
  setupRequired,
  permissionDenied,
  deviceUnavailable,
  connectionFailed,
  invalidRequest,
  invalidPdf,
  rasterizationFailed,
  busy,
  nativeFailure,
}

final class ThermalPrinterDevice {
  const ThermalPrinterDevice({
    required this.id,
    required this.connectionType,
    required this.displayName,
    this.address,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.deviceName,
    this.preferred = false,
  });

  final String id;
  final ThermalPrinterConnectionType connectionType;
  final String displayName;
  final String? address;
  final int? vendorId;
  final int? productId;
  final String? serialNumber;
  final String? deviceName;
  final bool preferred;
}

final class ThermalPrinterProfile {
  const ThermalPrinterProfile({
    required this.displayName,
    required this.connectionType,
    required this.printableWidthPx,
    this.bluetoothAddress,
    this.usbVendorId,
    this.usbProductId,
    this.usbSerialNumber,
    this.usbDeviceName,
    this.tcpHost,
    this.tcpPort,
    this.tcpTimeoutSeconds = 30,
    this.copies = 1,
    this.gradient = false,
    this.feedDots = 20,
    this.cutAfterPrint = false,
    this.useEscAsteriskCommand = false,
  });

  static const int width58mm = 384;
  static const int width80mm = 576;

  final String displayName;
  final ThermalPrinterConnectionType connectionType;
  final int printableWidthPx;
  final String? bluetoothAddress;
  final int? usbVendorId;
  final int? usbProductId;
  final String? usbSerialNumber;
  final String? usbDeviceName;
  final String? tcpHost;
  final int? tcpPort;
  final int tcpTimeoutSeconds;
  final int copies;
  final bool gradient;
  final int feedDots;
  final bool cutAfterPrint;

  /// Reserved for a later compatibility flow. It intentionally has no v1 UI.
  final bool useEscAsteriskCommand;

  bool get isValid {
    if (displayName.trim().isEmpty || printableWidthPx <= 0) return false;
    if (copies < 1 || copies > 9 || feedDots < 0 || feedDots > 255) {
      return false;
    }
    return switch (connectionType) {
      ThermalPrinterConnectionType.bluetooth =>
        bluetoothAddress != null && bluetoothAddress!.trim().isNotEmpty,
      ThermalPrinterConnectionType.usb =>
        usbVendorId != null && usbProductId != null,
      ThermalPrinterConnectionType.tcp =>
        tcpHost != null &&
            tcpHost!.trim().isNotEmpty &&
            tcpPort != null &&
            tcpPort! >= 1 &&
            tcpPort! <= 65535 &&
            tcpTimeoutSeconds >= 1 &&
            tcpTimeoutSeconds <= 60,
    };
  }

  ThermalPrinterProfile copyWith({
    String? displayName,
    ThermalPrinterConnectionType? connectionType,
    int? printableWidthPx,
    String? bluetoothAddress,
    int? usbVendorId,
    int? usbProductId,
    String? usbSerialNumber,
    String? usbDeviceName,
    String? tcpHost,
    int? tcpPort,
    int? tcpTimeoutSeconds,
    int? copies,
    bool? gradient,
    int? feedDots,
    bool? cutAfterPrint,
    bool? useEscAsteriskCommand,
  }) => ThermalPrinterProfile(
    displayName: displayName ?? this.displayName,
    connectionType: connectionType ?? this.connectionType,
    printableWidthPx: printableWidthPx ?? this.printableWidthPx,
    bluetoothAddress: bluetoothAddress ?? this.bluetoothAddress,
    usbVendorId: usbVendorId ?? this.usbVendorId,
    usbProductId: usbProductId ?? this.usbProductId,
    usbSerialNumber: usbSerialNumber ?? this.usbSerialNumber,
    usbDeviceName: usbDeviceName ?? this.usbDeviceName,
    tcpHost: tcpHost ?? this.tcpHost,
    tcpPort: tcpPort ?? this.tcpPort,
    tcpTimeoutSeconds: tcpTimeoutSeconds ?? this.tcpTimeoutSeconds,
    copies: copies ?? this.copies,
    gradient: gradient ?? this.gradient,
    feedDots: feedDots ?? this.feedDots,
    cutAfterPrint: cutAfterPrint ?? this.cutAfterPrint,
    useEscAsteriskCommand: useEscAsteriskCommand ?? this.useEscAsteriskCommand,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'displayName': displayName,
    'connectionType': connectionType.name,
    'printableWidthPx': printableWidthPx,
    'bluetoothAddress': bluetoothAddress,
    'usbVendorId': usbVendorId,
    'usbProductId': usbProductId,
    'usbSerialNumber': usbSerialNumber,
    'usbDeviceName': usbDeviceName,
    'tcpHost': tcpHost,
    'tcpPort': tcpPort,
    'tcpTimeoutSeconds': tcpTimeoutSeconds,
    'copies': copies,
    'gradient': gradient,
    'feedDots': feedDots,
    'cutAfterPrint': cutAfterPrint,
    'useEscAsteriskCommand': useEscAsteriskCommand,
  };

  String encode() => jsonEncode(toJson());

  static ThermalPrinterProfile? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      final type = ThermalPrinterConnectionType.values.where(
        (item) => item.name == value['connectionType'],
      );
      if (type.isEmpty) return null;
      final profile = ThermalPrinterProfile(
        displayName: value['displayName']?.toString() ?? '',
        connectionType: type.first,
        printableWidthPx: value['printableWidthPx'] is num
            ? (value['printableWidthPx'] as num).toInt()
            : 20,
        bluetoothAddress: value['bluetoothAddress']?.toString(),
        usbVendorId: value['usbVendorId'] is num
            ? (value['usbVendorId'] as num).toInt()
            : null,
        usbProductId: value['usbProductId'] is num
            ? (value['usbProductId'] as num).toInt()
            : null,
        usbSerialNumber: value['usbSerialNumber']?.toString(),
        usbDeviceName: value['usbDeviceName']?.toString(),
        tcpHost: value['tcpHost']?.toString(),
        tcpPort: value['tcpPort'] is num
            ? (value['tcpPort'] as num).toInt()
            : null,
        tcpTimeoutSeconds: value['tcpTimeoutSeconds'] is num
            ? (value['tcpTimeoutSeconds'] as num).toInt()
            : 30,
        copies: value['copies'] is num ? (value['copies'] as num).toInt() : 1,
        gradient: value['gradient'] == true,
        feedDots: value['feedDots'] is num
            ? (value['feedDots'] as num).toInt()
            : 0,
        cutAfterPrint: value['cutAfterPrint'] == true,
        useEscAsteriskCommand: value['useEscAsteriskCommand'] == true,
      );
      return profile.isValid ? profile : null;
    } catch (_) {
      return null;
    }
  }
}

final class ThermalPrintProgress {
  const ThermalPrintProgress({
    required this.jobId,
    required this.phase,
    this.copyIndex,
    this.copyCount,
    this.pageIndex,
    this.pageCount,
    this.bytesSent,
    this.totalBytes,
  });

  final String jobId;
  final ThermalPrintPhase phase;
  final int? copyIndex;
  final int? copyCount;
  final int? pageIndex;
  final int? pageCount;
  final int? bytesSent;
  final int? totalBytes;
}

final class ThermalPrintOperationResult {
  const ThermalPrintOperationResult({
    required this.status,
    this.errorCode,
    this.diagnostic,
  });

  final ThermalPrintResultStatus status;
  final String? errorCode;
  final String? diagnostic;
}
