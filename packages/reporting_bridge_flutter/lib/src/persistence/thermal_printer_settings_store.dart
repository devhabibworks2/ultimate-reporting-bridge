import 'package:shared_preferences/shared_preferences.dart';

import '../printing/thermal_printer_models.dart';

abstract interface class ThermalPrinterSettingsStore {
  Future<ThermalPrinterProfile?> loadDefaultProfile();
  Future<void> saveDefaultProfile(ThermalPrinterProfile profile);
  Future<void> removeDefaultProfile();
}

final class SharedPreferencesThermalPrinterSettingsStore
    implements ThermalPrinterSettingsStore {
  SharedPreferencesThermalPrinterSettingsStore._(this._preferences);

  static const _key = 'reporting_bridge_flutter.thermal_printer.v1';
  static Future<void> _serial = Future<void>.value();
  final SharedPreferences _preferences;

  static Future<SharedPreferencesThermalPrinterSettingsStore> create() async =>
      SharedPreferencesThermalPrinterSettingsStore._(
        await SharedPreferences.getInstance(),
      );

  @override
  Future<ThermalPrinterProfile?> loadDefaultProfile() async {
    final raw = _preferences.getString(_key);
    final profile = ThermalPrinterProfile.decode(raw);
    if (raw != null && profile == null) await removeDefaultProfile();
    return profile;
  }

  @override
  Future<void> saveDefaultProfile(ThermalPrinterProfile profile) {
    if (!profile.isValid) {
      return Future<void>.error(ArgumentError.value(profile, 'profile'));
    }
    return _enqueue(() async {
      final saved = await _preferences.setString(_key, profile.encode());
      if (!saved) throw StateError('thermalPrinterSettingsWriteFailed');
      return saved;
    });
  }

  @override
  Future<void> removeDefaultProfile() =>
      _enqueue(() => _preferences.remove(_key));

  Future<void> _enqueue(Future<bool> Function() action) {
    final future = _serial.then((_) async {
      await action();
    });
    _serial = future.catchError((_) {});
    return future;
  }
}

final class MemoryThermalPrinterSettingsStore
    implements ThermalPrinterSettingsStore {
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
