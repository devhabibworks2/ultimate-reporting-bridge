import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  const bluetooth = ThermalPrinterProfile(
    displayName: 'Counter',
    connectionType: ThermalPrinterConnectionType.bluetooth,
    printableWidthPx: ThermalPrinterProfile.width58mm,
    bluetoothAddress: 'AA:BB',
    copies: 2,
    gradient: true,
    feedDots: 37,
    cutAfterPrint: true,
    useEscAsteriskCommand: true,
  );

  test('Bluetooth v1 fields round trip', () {
    final restored = ThermalPrinterProfile.decode(bluetooth.encode())!;
    expect(restored.displayName, 'Counter');
    expect(restored.connectionType, ThermalPrinterConnectionType.bluetooth);
    expect(restored.printableWidthPx, 384);
    expect(restored.bluetoothAddress, 'AA:BB');
    expect(restored.copies, 2);
    expect(restored.gradient, isTrue);
    expect(restored.feedDots, 37);
    expect(restored.cutAfterPrint, isTrue);
    expect(restored.useEscAsteriskCommand, isTrue);
  });

  test('USB and TCP fields round trip', () {
    const usb = ThermalPrinterProfile(
      displayName: 'USB',
      connectionType: ThermalPrinterConnectionType.usb,
      printableWidthPx: 576,
      usbVendorId: 1,
      usbProductId: 2,
      usbSerialNumber: 'serial',
      usbDeviceName: 'device',
    );
    final u = ThermalPrinterProfile.decode(usb.encode())!;
    expect(
      [u.usbVendorId, u.usbProductId, u.usbSerialNumber, u.usbDeviceName],
      [1, 2, 'serial', 'device'],
    );
    const tcp = ThermalPrinterProfile(
      displayName: 'TCP',
      connectionType: ThermalPrinterConnectionType.tcp,
      printableWidthPx: 576,
      tcpHost: 'printer',
      tcpPort: 9100,
      tcpTimeoutSeconds: 45,
    );
    final t = ThermalPrinterProfile.decode(tcp.encode())!;
    expect(
      [t.tcpHost, t.tcpPort, t.tcpTimeoutSeconds, t.printableWidthPx],
      ['printer', 9100, 45, 576],
    );
    expect(ThermalPrinterProfile.width80mm, 576);
  });

  test('malformed and invalid connection profiles fail closed', () {
    expect(ThermalPrinterProfile.decode('{'), isNull);
    expect(ThermalPrinterProfile.decode('[]'), isNull);
    expect(bluetooth.copyWith(bluetoothAddress: ' ').isValid, isFalse);
    expect(
      const ThermalPrinterProfile(
        displayName: 'USB',
        connectionType: ThermalPrinterConnectionType.usb,
        printableWidthPx: 384,
        usbVendorId: 1,
      ).isValid,
      isFalse,
    );
    expect(
      const ThermalPrinterProfile(
        displayName: 'TCP',
        connectionType: ThermalPrinterConnectionType.tcp,
        printableWidthPx: 384,
        tcpHost: 'host',
        tcpPort: 70000,
      ).isValid,
      isFalse,
    );
    expect(bluetooth.copyWith(copies: 10).isValid, isFalse);
    expect(bluetooth.copyWith(feedDots: 256).isValid, isFalse);
  });
}
