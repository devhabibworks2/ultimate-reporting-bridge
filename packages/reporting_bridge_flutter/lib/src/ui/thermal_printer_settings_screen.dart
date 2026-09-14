import 'package:flutter/material.dart';

import '../printing/thermal_printer_controller.dart';
import '../printing/thermal_printer_models.dart';

class ThermalPrinterSettingsScreen extends StatefulWidget {
  const ThermalPrinterSettingsScreen({super.key, required this.controller});

  final ThermalPrinterSettingsController controller;

  @override
  State<ThermalPrinterSettingsScreen> createState() =>
      _ThermalPrinterSettingsScreenState();
}

class _ThermalPrinterSettingsScreenState
    extends State<ThermalPrinterSettingsScreen> {
  late ThermalPrinterConnectionType _type;
  late final TextEditingController _name;
  late final TextEditingController _width;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _timeout;
  ThermalPrinterDevice? _selectedBluetoothDevice;
  ThermalPrinterDevice? _selectedUsbDevice;
  String? _bluetoothAddress;
  int? _usbVendorId;
  int? _usbProductId;
  String? _usbSerialNumber;
  String? _usbDeviceName;
  bool _draftHydrated = false;
  bool _hasCustomPrinterName = false;
  bool _gradient = false;
  bool _cut = false;
  int _copies = 1;
  int _feed = 20;

  @override
  void initState() {
    super.initState();
    _type = ThermalPrinterConnectionType.bluetooth;
    _name = TextEditingController();
    _width = TextEditingController(text: '${ThermalPrinterProfile.width80mm}');
    _host = TextEditingController();
    _port = TextEditingController(text: '9100');
    _timeout = TextEditingController(text: '30');
    for (final controller in <TextEditingController>[
      _name,
      _width,
      _host,
      _port,
      _timeout,
    ]) {
      controller.addListener(_onDraftChanged);
    }
    widget.controller.addListener(_syncProfile);
    _syncProfile();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.controller.ensureLoaded(),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncProfile);
    for (final controller in <TextEditingController>[
      _name,
      _width,
      _host,
      _port,
      _timeout,
    ]) {
      controller
        ..removeListener(_onDraftChanged)
        ..dispose();
    }
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  void _syncProfile() {
    final state = widget.controller.value;
    final profile = state.profile;
    if (!_draftHydrated && state.initialized) {
      _draftHydrated = true;
      if (profile != null) {
        _type = profile.connectionType;
        _name.text = profile.displayName;
        _width.text = '${profile.printableWidthPx}';
        _host.text = profile.tcpHost ?? '';
        _port.text = '${profile.tcpPort ?? 9100}';
        _timeout.text = '${profile.tcpTimeoutSeconds}';
        _gradient = profile.gradient;
        _cut = profile.cutAfterPrint;
        _copies = profile.copies;
        _feed = profile.feedDots;
        _bluetoothAddress = profile.bluetoothAddress;
        _usbVendorId = profile.usbVendorId;
        _usbProductId = profile.usbProductId;
        _usbSerialNumber = profile.usbSerialNumber;
        _usbDeviceName = profile.usbDeviceName;
        _hasCustomPrinterName = profile.displayName != 'Thermal printer';
      }
    }
    _selectedBluetoothDevice = _findBluetooth(
      state.bluetoothDevices,
      _bluetoothAddress,
    );
    _selectedUsbDevice = _findUsb(state.usbDevices);
    if (!_hasCustomPrinterName && _selectedBluetoothDevice != null) {
      _name.text = _selectedBluetoothDevice!.displayName;
    }
    if (mounted) setState(() {});
  }

  ThermalPrinterDevice? _findBluetooth(
    List<ThermalPrinterDevice> devices,
    String? address,
  ) {
    final normalized = address?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final device in devices) {
      if (device.address?.trim().toLowerCase() == normalized) return device;
    }
    return null;
  }

  ThermalPrinterDevice? _findUsb(List<ThermalPrinterDevice> devices) {
    if (_usbVendorId == null || _usbProductId == null) return null;
    for (final device in devices) {
      if (device.vendorId != _usbVendorId ||
          device.productId != _usbProductId) {
        continue;
      }
      if (_usbSerialNumber != null && _usbSerialNumber!.isNotEmpty) {
        if (device.serialNumber == _usbSerialNumber) return device;
        continue;
      }
      if (_usbDeviceName == null || device.deviceName == _usbDeviceName) {
        return device;
      }
    }
    return null;
  }

  ThermalPrinterProfile _profile() => ThermalPrinterProfile(
    displayName: _name.text.trim().isEmpty
        ? 'Thermal printer'
        : _name.text.trim(),
    connectionType: _type,
    printableWidthPx: int.tryParse(_width.text) ?? 0,
    bluetoothAddress: _type == ThermalPrinterConnectionType.bluetooth
        ? _bluetoothAddress
        : null,
    usbVendorId: _type == ThermalPrinterConnectionType.usb
        ? _usbVendorId
        : null,
    usbProductId: _type == ThermalPrinterConnectionType.usb
        ? _usbProductId
        : null,
    usbSerialNumber: _type == ThermalPrinterConnectionType.usb
        ? _usbSerialNumber
        : null,
    usbDeviceName: _type == ThermalPrinterConnectionType.usb
        ? _usbDeviceName
        : null,
    tcpHost: _type == ThermalPrinterConnectionType.tcp
        ? _host.text.trim()
        : null,
    tcpPort: _type == ThermalPrinterConnectionType.tcp
        ? int.tryParse(_port.text)
        : null,
    tcpTimeoutSeconds: int.tryParse(_timeout.text) ?? 0,
    copies: _copies,
    gradient: _gradient,
    feedDots: _feed,
    cutAfterPrint: _cut,
  );

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.value;
    final profile = _profile();
    final busy = state.loading || state.testing;
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الطابعة الحرارية')),
      body: SafeArea(
        child: Form(
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              DropdownButtonFormField<ThermalPrinterConnectionType>(
                key: ValueKey<ThermalPrinterConnectionType>(_type),
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'نوع الاتصال'),
                items: ThermalPrinterConnectionType.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(switch (item) {
                          ThermalPrinterConnectionType.bluetooth => 'Bluetooth',
                          ThermalPrinterConnectionType.usb => 'USB',
                          ThermalPrinterConnectionType.tcp => 'TCP / Network',
                        }),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        _type = value!;
                        if (_type == ThermalPrinterConnectionType.bluetooth &&
                            !state.bluetoothDevicesResolved) {
                          widget.controller.refreshBluetoothDevices();
                        }
                        if (_type == ThermalPrinterConnectionType.usb &&
                            state.usbDevices.isEmpty) {
                          widget.controller.refreshUsbDevices();
                        }
                      }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                enabled: !busy,
                onChanged: (_) => setState(() => _hasCustomPrinterName = true),
                decoration: const InputDecoration(labelText: 'اسم الطابعة'),
              ),
              const SizedBox(height: 12),
              if (state.profile != null) ...<Widget>[
                _savedPrinterCard(state),
                const SizedBox(height: 12),
              ],
              _connectionSelector(state),
              const Divider(height: 32),
              DropdownButtonFormField<int>(
                key: ValueKey<int>(int.tryParse(_width.text) ?? 0),
                initialValue:
                    int.tryParse(_width.text) == ThermalPrinterProfile.width58mm
                    ? ThermalPrinterProfile.width58mm
                    : ThermalPrinterProfile.width80mm,
                decoration: const InputDecoration(
                  labelText: 'مقاس الورق المقترح',
                ),
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem(value: 384, child: Text('58mm — 384px')),
                  DropdownMenuItem(value: 576, child: Text('80mm — 576px')),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => _width.text = '$value'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _width,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'العرض القابل للطباعة (px)',
                ),
                validator: (value) => (int.tryParse(value ?? '') ?? 0) > 0
                    ? null
                    : 'أدخل عرض طباعة صالحًا.',
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey<int>(_copies),
                      initialValue: _copies,
                      decoration: const InputDecoration(labelText: 'النسخ'),
                      items: List<DropdownMenuItem<int>>.generate(
                        9,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text('${index + 1}'),
                        ),
                      ),
                      onChanged: busy
                          ? null
                          : (value) => setState(() => _copies = value ?? 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Feed dots'),
                      child: Text('$_feed'),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _feed.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                label: '$_feed',
                onChanged: busy
                    ? null
                    : (value) => setState(() => _feed = value.round()),
              ),
              SwitchListTile(
                value: _gradient,
                title: const Text('تدرج رمادي'),
                subtitle: const Text('إيقافه يرسل أسود وأبيض'),
                onChanged: busy
                    ? null
                    : (value) => setState(() => _gradient = value),
              ),
              SwitchListTile(
                value: _cut,
                title: const Text('إرسال أمر قص الورق'),
                subtitle: const Text('لا يمكن التحقق من وجود قاطع في الطابعة'),
                onChanged: busy
                    ? null
                    : (value) => setState(() => _cut = value),
              ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _errorMessage(state.error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: busy || !_canPrintProfile(profile, state)
                    ? null
                    : () => widget.controller.test(profile),
                icon: state.testing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined),
                label: const Text('طباعة اختبار'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: busy || !profile.isValid
                    ? null
                    : () async {
                        await widget.controller.save(profile);
                        if (context.mounted &&
                            widget.controller.value.error == null) {
                          Navigator.of(context).pop();
                        }
                      },
                child: const Text('حفظ الطابعة الافتراضية'),
              ),
              if (state.profile != null)
                TextButton(
                  onPressed: busy ? null : widget.controller.remove,
                  child: const Text('إزالة الطابعة الافتراضية'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _savedPrinterCard(ThermalPrinterSettingsState state) {
    final profile = state.profile!;
    final bluetoothUnavailable =
        profile.connectionType == ThermalPrinterConnectionType.bluetooth &&
        state.savedBluetoothAvailability ==
            ThermalPrinterAvailability.unavailable;
    final identity = switch (profile.connectionType) {
      ThermalPrinterConnectionType.bluetooth => profile.bluetoothAddress ?? '—',
      ThermalPrinterConnectionType.usb =>
        '${profile.usbVendorId ?? '—'} / ${profile.usbProductId ?? '—'}',
      ThermalPrinterConnectionType.tcp =>
        '${profile.tcpHost ?? '—'}:${profile.tcpPort ?? '—'}',
    };
    return Card(
      color: bluetoothUnavailable
          ? Theme.of(context).colorScheme.errorContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'الطابعة الافتراضية',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(profile.displayName),
            Text(identity, textDirection: TextDirection.ltr),
            if (bluetoothUnavailable) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'الطابعة المحفوظة غير متاحة الآن. اربطها من إعدادات Android ثم حدّث الأجهزة وأعد اختيارها.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.controller.refreshBluetoothDevices,
                icon: const Icon(Icons.refresh),
                label: const Text('تحديث الأجهزة'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _canPrintProfile(
    ThermalPrinterProfile profile,
    ThermalPrinterSettingsState state,
  ) {
    if (!profile.isValid) return false;
    if (profile.connectionType != ThermalPrinterConnectionType.bluetooth ||
        !state.bluetoothDevicesResolved) {
      return true;
    }
    return _findBluetooth(state.bluetoothDevices, profile.bluetoothAddress) !=
        null;
  }

  String _errorMessage(String code) => switch (code) {
    'savedBluetoothPrinterUnavailable' || 'bluetoothPrinterUnavailable' =>
      'الطابعة المحفوظة غير متاحة. تأكد من ربطها عبر Bluetooth ثم حدّث الأجهزة.',
    'bluetoothPermissionDenied' =>
      'يلزم السماح بصلاحية الأجهزة القريبة لاستخدام طابعة Bluetooth.',
    'bluetoothUnavailable' ||
    'bluetoothDisabled' => 'Bluetooth غير متاح. فعّله ثم أعد المحاولة.',
    'bluetoothConnectionFailed' =>
      'تعذر الاتصال بطابعة Bluetooth. تأكد أنها قيد التشغيل وقريبة.',
    'tcpConnectionTimeout' =>
      'انتهت مهلة الاتصال بالشبكة. تحقق من عنوان IP والمنفذ والشبكة.',
    'tcpHostNotFound' => 'تعذر العثور على عنوان الطابعة في الشبكة.',
    'tcpConnectionRefused' =>
      'رفضت الطابعة الاتصال. تأكد من المنفذ وأن الطابعة متصلة بالشبكة.',
    'tcpSendFailed' || 'tcpConnectionFailed' =>
      'تعذر الإرسال إلى طابعة الشبكة. تحقق من IP والمنفذ وأن الجهازين على الشبكة نفسها.',
    'printerConnectionFailed' =>
      'تعذر الاتصال بالطابعة. تأكد أنها قيد التشغيل.',
    _ => 'تعذر تنفيذ الطباعة. راجع إعدادات الطابعة ثم أعد المحاولة.',
  };

  Widget _connectionSelector(ThermalPrinterSettingsState state) {
    final busy = state.loading || state.testing;
    switch (_type) {
      case ThermalPrinterConnectionType.bluetooth:
        return _deviceSelector(
          label: 'الأجهزة المرتبطة عبر Bluetooth',
          devices: state.bluetoothDevices,
          selectedId: _bluetoothAddress,
          onRefresh: widget.controller.refreshBluetoothDevices,
          busy: busy,
        );
      case ThermalPrinterConnectionType.usb:
        return _deviceSelector(
          label: 'طابعات USB المتصلة',
          devices: state.usbDevices,
          selectedId: _selectedUsbDevice?.id ?? _usbDeviceName,
          onRefresh: widget.controller.refreshUsbDevices,
          requestPermission: true,
          busy: busy,
        );
      case ThermalPrinterConnectionType.tcp:
        return Column(
          children: <Widget>[
            TextFormField(
              controller: _host,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Host / IP'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'أدخل عنوان IP أو اسم المضيف.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _port,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
              validator: (value) {
                final port = int.tryParse(value ?? '');
                return port != null && port >= 1 && port <= 65535
                    ? null
                    : 'أدخل منفذًا بين 1 و65535.';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _timeout,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Timeout (seconds)'),
              validator: (value) {
                final timeout = int.tryParse(value ?? '');
                return timeout != null && timeout >= 1 && timeout <= 60
                    ? null
                    : 'أدخل مهلة بين 1 و60 ثانية.';
              },
            ),
          ],
        );
    }
  }

  Widget _deviceSelector({
    required String label,
    required List<ThermalPrinterDevice> devices,
    required String? selectedId,
    required Future<void> Function() onRefresh,
    required bool busy,
    bool requestPermission = false,
  }) => Card(
    child: Column(
      children: <Widget>[
        ListTile(
          title: Text(label),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: busy ? null : onRefresh,
          ),
        ),
        RadioGroup<String>(
          groupValue: selectedId,
          onChanged: (id) {
            if (!busy) _selectDevice(id, devices, requestPermission);
          },
          child: Column(
            children: <Widget>[
              for (final device in devices)
                RadioListTile<String>(
                  value: device.id,
                  title: Text(device.displayName),
                  subtitle: Text(
                    device.address ?? device.deviceName ?? device.id,
                  ),
                ),
            ],
          ),
        ),
        if (devices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('اضغط تحديث لعرض الأجهزة المتاحة.'),
          ),
      ],
    ),
  );

  Future<void> _selectDevice(
    String? id,
    List<ThermalPrinterDevice> devices,
    bool requestPermission,
  ) async {
    ThermalPrinterDevice? device;
    for (final item in devices) {
      if (item.id == id) {
        device = item;
        break;
      }
    }
    if (device == null) {
      return;
    }
    final selectedDevice = device;
    if (requestPermission) {
      final permission = await widget.controller.requestUsbPermission(
        selectedDevice,
      );
      if (permission != ThermalPrinterPermissionState.granted || !mounted) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (_type == ThermalPrinterConnectionType.bluetooth) {
        _selectedBluetoothDevice = selectedDevice;
        _bluetoothAddress = selectedDevice.address;
        if (!_hasCustomPrinterName) {
          _name.text = selectedDevice.displayName;
        }
      } else {
        _selectedUsbDevice = selectedDevice;
        _usbVendorId = selectedDevice.vendorId;
        _usbProductId = selectedDevice.productId;
        _usbSerialNumber = selectedDevice.serialNumber;
        _usbDeviceName = selectedDevice.deviceName;
      }
    });
  }
}
