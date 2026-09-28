import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'reporting_bridge_flutter.thermal_printer.v1';
  const profile = ThermalPrinterProfile(
    displayName: 'Counter',
    connectionType: ThermalPrinterConnectionType.bluetooth,
    printableWidthPx: 384,
    bluetoothAddress: 'AA:BB',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save load remove uses v1 key', () async {
    final store = await SharedPreferencesThermalPrinterSettingsStore.create();
    await store.saveDefaultProfile(profile);
    expect(
      (await SharedPreferences.getInstance()).getString(key),
      contains('Counter'),
    );
    expect((await store.loadDefaultProfile())!.bluetoothAddress, 'AA:BB');
    await store.removeDefaultProfile();
    expect(await store.loadDefaultProfile(), isNull);
  });

  test('invalid save rejects without replacing profile', () async {
    final store = await SharedPreferencesThermalPrinterSettingsStore.create();
    await store.saveDefaultProfile(profile);
    await expectLater(
      store.saveDefaultProfile(profile.copyWith(copies: 0)),
      throwsArgumentError,
    );
    expect((await store.loadDefaultProfile())!.displayName, 'Counter');
  });

  test('corrupt stored payload is removed', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, '{');
    final store = await SharedPreferencesThermalPrinterSettingsStore.create();
    expect(await store.loadDefaultProfile(), isNull);
    expect(preferences.getString(key), isNull);
  });

  test('concurrent writes retain last submitted profile', () async {
    final store = await SharedPreferencesThermalPrinterSettingsStore.create();
    await Future.wait([
      store.saveDefaultProfile(profile),
      store.saveDefaultProfile(profile.copyWith(displayName: 'Last')),
    ]);
    expect((await store.loadDefaultProfile())!.displayName, 'Last');
  });
}
