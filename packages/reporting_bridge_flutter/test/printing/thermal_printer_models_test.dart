import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bluetoothProfile = ThermalPrinterProfile(
    displayName: 'Counter printer',
    connectionType: ThermalPrinterConnectionType.bluetooth,
    bluetoothAddress: '01:23:45:67:89:AB',
    printableWidthPx: ThermalPrinterProfile.width58mm,
  );

  test('valid Bluetooth profile survives persistence encoding', () {
    final restored = ThermalPrinterProfile.decode(bluetoothProfile.encode());

    expect(restored, isNotNull);
    expect(restored!.isValid, isTrue);
    expect(restored.connectionType, ThermalPrinterConnectionType.bluetooth);
    expect(restored.bluetoothAddress, bluetoothProfile.bluetoothAddress);
    expect(restored.printableWidthPx, ThermalPrinterProfile.width58mm);
  });

  test('TCP profile retains its endpoint and feed setting', () {
    const profile = ThermalPrinterProfile(
      displayName: 'Epson network printer',
      connectionType: ThermalPrinterConnectionType.tcp,
      printableWidthPx: ThermalPrinterProfile.width80mm,
      tcpHost: '192.168.1.80',
      tcpPort: 9100,
      tcpTimeoutSeconds: 30,
      feedDots: 37,
    );

    final restored = ThermalPrinterProfile.decode(profile.encode());

    expect(restored, isNotNull);
    expect(restored!.connectionType, ThermalPrinterConnectionType.tcp);
    expect(restored.tcpHost, '192.168.1.80');
    expect(restored.tcpPort, 9100);
    expect(restored.feedDots, 37);
  });

  test('new profiles default to a visible paper feed', () {
    const profile = ThermalPrinterProfile(
      displayName: 'Counter printer',
      connectionType: ThermalPrinterConnectionType.bluetooth,
      bluetoothAddress: '01:23:45:67:89:AB',
      printableWidthPx: ThermalPrinterProfile.width58mm,
    );

    expect(profile.feedDots, 20);
  });

  test('corrupt or unsafe persisted profiles fail closed', () {
    expect(ThermalPrinterProfile.decode('{invalid'), isNull);
    expect(
      ThermalPrinterProfile.decode(
        '{"displayName":"bad","connectionType":"tcp",'
        '"printableWidthPx":384,"tcpHost":"printer",'
        '"tcpPort":70000}',
      ),
      isNull,
    );
  });

  test('enforces application copy and feed bounds', () {
    expect(bluetoothProfile.copyWith(copies: 10).isValid, isFalse);
    expect(bluetoothProfile.copyWith(feedDots: 256).isValid, isFalse);
    expect(bluetoothProfile.copyWith(copies: 9, feedDots: 255).isValid, isTrue);
  });

  test('test-print PDF is available through the package asset path', () async {
    final data = await rootBundle.load(
      'packages/reporting_bridge_flutter/assets/printing/thermal_printer_test.pdf',
    );

    expect(data.lengthInBytes, greaterThan(0));
  });
}
