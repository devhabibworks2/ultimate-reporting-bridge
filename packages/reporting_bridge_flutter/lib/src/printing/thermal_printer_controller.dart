import 'package:flutter/foundation.dart';

import '../persistence/thermal_printer_settings_store.dart';
import 'thermal_printer_models.dart';
import 'thermal_printer_native_client.dart';
import 'thermal_report_print_platform.dart';

final class ThermalPrinterSettingsState {
  const ThermalPrinterSettingsState({
    this.profile,
    this.bluetoothPermission = ThermalPrinterPermissionState.denied,
    this.bluetoothDevices = const <ThermalPrinterDevice>[],
    this.bluetoothDevicesResolved = false,
    this.savedBluetoothAvailability = ThermalPrinterAvailability.unknown,
    this.usbDevices = const <ThermalPrinterDevice>[],
    this.initialized = false,
    this.loading = false,
    this.testing = false,
    this.error,
  });

  final ThermalPrinterProfile? profile;
  final ThermalPrinterPermissionState bluetoothPermission;
  final List<ThermalPrinterDevice> bluetoothDevices;
  final bool bluetoothDevicesResolved;
  final ThermalPrinterAvailability savedBluetoothAvailability;
  final List<ThermalPrinterDevice> usbDevices;
  final bool initialized;
  final bool loading;
  final bool testing;
  final String? error;

  ThermalPrinterSettingsState copyWith({
    ThermalPrinterProfile? profile,
    ThermalPrinterPermissionState? bluetoothPermission,
    List<ThermalPrinterDevice>? bluetoothDevices,
    bool? bluetoothDevicesResolved,
    ThermalPrinterAvailability? savedBluetoothAvailability,
    List<ThermalPrinterDevice>? usbDevices,
    bool? initialized,
    bool? loading,
    bool? testing,
    String? error,
    bool clearProfile = false,
    bool clearError = false,
  }) => ThermalPrinterSettingsState(
    profile: clearProfile ? null : (profile ?? this.profile),
    bluetoothPermission: bluetoothPermission ?? this.bluetoothPermission,
    bluetoothDevices: bluetoothDevices ?? this.bluetoothDevices,
    bluetoothDevicesResolved:
        bluetoothDevicesResolved ?? this.bluetoothDevicesResolved,
    savedBluetoothAvailability:
        savedBluetoothAvailability ?? this.savedBluetoothAvailability,
    usbDevices: usbDevices ?? this.usbDevices,
    initialized: initialized ?? this.initialized,
    loading: loading ?? this.loading,
    testing: testing ?? this.testing,
    error: clearError ? null : (error ?? this.error),
  );
}

final class ThermalPrinterSettingsController
    extends ValueNotifier<ThermalPrinterSettingsState> {
  ThermalPrinterSettingsController({
    required ThermalPrinterSettingsStore settingsStore,
    required ThermalPrinterNativeClient nativeClient,
    required ThermalBluetoothAvailabilitySink availabilitySink,
    required ThermalPrinterTestPlatform testPlatform,
  }) : _settingsStore = settingsStore,
       _nativeClient = nativeClient,
       _availabilitySink = availabilitySink,
       _testPlatform = testPlatform,
       super(const ThermalPrinterSettingsState());

  final ThermalPrinterSettingsStore _settingsStore;
  final ThermalPrinterNativeClient _nativeClient;
  final ThermalBluetoothAvailabilitySink _availabilitySink;
  final ThermalPrinterTestPlatform _testPlatform;
  Future<void>? _loadFuture;

  /// Loads the app-wide profile once. Device refreshes are handled separately
  /// so a settings screen cannot race its initial hydration.
  Future<void> ensureLoaded() => _loadFuture ??= _load();

  Future<void> load() => ensureLoaded();

  Future<void> _load() async {
    value = value.copyWith(loading: true, clearError: true);
    try {
      final profile = await _settingsStore.loadDefaultProfile();
      final usesBluetooth =
          profile?.connectionType == ThermalPrinterConnectionType.bluetooth;
      final permission = usesBluetooth
          ? await _nativeClient.bluetoothPermissionState()
          : ThermalPrinterPermissionState.denied;
      final devices =
          profile?.connectionType == ThermalPrinterConnectionType.bluetooth &&
              permission == ThermalPrinterPermissionState.granted
          ? await _nativeClient.listPairedBluetoothDevices()
          : const <ThermalPrinterDevice>[];
      final resolved =
          profile?.connectionType == ThermalPrinterConnectionType.bluetooth &&
          permission == ThermalPrinterPermissionState.granted;
      final availability = _availabilityFor(
        profile,
        devices,
        devicesResolved: resolved,
      );
      value = value.copyWith(
        profile: profile,
        bluetoothPermission: permission,
        bluetoothDevices: devices,
        bluetoothDevicesResolved: resolved,
        savedBluetoothAvailability: availability,
        initialized: true,
        loading: false,
        clearError: true,
      );
      _publishBluetoothAvailability(profile, availability);
    } catch (error) {
      value = value.copyWith(
        loading: false,
        initialized: true,
        error: error.toString(),
      );
    }
  }

  Future<void> refreshBluetoothDevices() async {
    if (value.loading || value.testing) return;
    value = value.copyWith(loading: true, clearError: true);
    try {
      var permission = await _nativeClient.bluetoothPermissionState();
      if (permission != ThermalPrinterPermissionState.granted) {
        permission = await _nativeClient.requestBluetoothPermissions();
      }
      final devices = permission == ThermalPrinterPermissionState.granted
          ? await _nativeClient.listPairedBluetoothDevices()
          : const <ThermalPrinterDevice>[];
      value = value.copyWith(
        bluetoothPermission: permission,
        bluetoothDevices: devices,
        bluetoothDevicesResolved:
            permission == ThermalPrinterPermissionState.granted,
        savedBluetoothAvailability: _availabilityFor(
          value.profile,
          devices,
          devicesResolved: permission == ThermalPrinterPermissionState.granted,
        ),
        loading: false,
      );
      _publishBluetoothAvailability(
        value.profile,
        value.savedBluetoothAvailability,
      );
    } catch (error) {
      value = value.copyWith(loading: false, error: error.toString());
    }
  }

  Future<void> refreshUsbDevices() async {
    if (value.loading || value.testing) return;
    value = value.copyWith(loading: true, clearError: true);
    try {
      value = value.copyWith(
        usbDevices: await _nativeClient.listConnectedUsbPrinters(),
        loading: false,
      );
    } catch (error) {
      value = value.copyWith(loading: false, error: error.toString());
    }
  }

  Future<ThermalPrinterPermissionState> requestUsbPermission(
    ThermalPrinterDevice device,
  ) async {
    if (value.loading || value.testing) {
      return ThermalPrinterPermissionState.denied;
    }
    return _nativeClient.requestUsbPermission(device);
  }

  Future<void> save(ThermalPrinterProfile profile) async {
    if (value.loading || value.testing) return;
    if (!profile.isValid) {
      value = value.copyWith(error: 'invalidPrinterConfiguration');
      return;
    }
    value = value.copyWith(loading: true, clearError: true);
    try {
      await _settingsStore.saveDefaultProfile(profile);
      final availability = _availabilityFor(
        profile,
        value.bluetoothDevices,
        devicesResolved: value.bluetoothDevicesResolved,
      );
      value = value.copyWith(
        profile: profile,
        savedBluetoothAvailability: availability,
        loading: false,
      );
      _publishBluetoothAvailability(profile, availability);
    } catch (error) {
      value = value.copyWith(loading: false, error: error.toString());
    }
  }

  Future<void> remove() async {
    if (value.loading || value.testing) return;
    value = value.copyWith(loading: true, clearError: true);
    try {
      await _settingsStore.removeDefaultProfile();
      value = value.copyWith(
        loading: false,
        clearProfile: true,
        savedBluetoothAvailability: ThermalPrinterAvailability.unknown,
      );
      _publishBluetoothAvailability(null, ThermalPrinterAvailability.unknown);
    } catch (error) {
      value = value.copyWith(loading: false, error: error.toString());
    }
  }

  Future<void> test(ThermalPrinterProfile profile) async {
    if (value.loading || value.testing) return;
    if (!profile.isValid) {
      value = value.copyWith(error: 'invalidPrinterConfiguration');
      return;
    }
    value = value.copyWith(testing: true, clearError: true);
    try {
      final result = await _testPlatform.testPrint(profile);
      value = value.copyWith(
        testing: false,
        error: result.isSubmitted ? null : (result.errorCode ?? 'printFailed'),
        clearError: result.isSubmitted,
      );
    } catch (error) {
      value = value.copyWith(testing: false, error: error.toString());
    }
  }

  ThermalPrinterAvailability _availabilityFor(
    ThermalPrinterProfile? profile,
    List<ThermalPrinterDevice> devices, {
    required bool devicesResolved,
  }) {
    if (profile?.connectionType != ThermalPrinterConnectionType.bluetooth ||
        !devicesResolved) {
      return ThermalPrinterAvailability.unknown;
    }
    final savedAddress = profile?.bluetoothAddress?.trim();
    if (savedAddress == null || savedAddress.isEmpty) {
      return ThermalPrinterAvailability.unknown;
    }
    return devices.any(
          (device) =>
              device.address?.trim().toLowerCase() ==
              savedAddress.toLowerCase(),
        )
        ? ThermalPrinterAvailability.available
        : ThermalPrinterAvailability.unavailable;
  }

  void _publishBluetoothAvailability(
    ThermalPrinterProfile? profile,
    ThermalPrinterAvailability availability,
  ) => _availabilitySink.setKnownBluetoothAvailability(profile, availability);
}
