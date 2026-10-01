import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  runApp(const CompatibilityHostLegacyApp());
}

class CompatibilityHostLegacyApp extends StatelessWidget {
  const CompatibilityHostLegacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: CompatibilityHostLegacyScreen(),
    );
  }
}

class CompatibilityHostLegacyScreen extends StatefulWidget {
  const CompatibilityHostLegacyScreen({super.key});

  @override
  State<CompatibilityHostLegacyScreen> createState() =>
      _CompatibilityHostLegacyScreenState();
}

class _CompatibilityHostLegacyScreenState
    extends State<CompatibilityHostLegacyScreen> {
  String? _status;

  Future<void> _constructBridge() async {
    ReportingBridgeFlutterClient? client;
    try {
      final endpoints = ReportServerEndpoints.resolve(
        serverUrl: ReportServerEndpoints.parseServerUrl(
          'https://example.invalid',
        ),
        profile: ReportServerProfile.deployed,
      );
      final supportDir = await getApplicationSupportDirectory();
      final cacheRoot = Directory('${supportDir.path}/reporting_bridge');
      await cacheRoot.create(recursive: true);

      client = await ReportingBridgeFlutter(
        connection: ReportServerConnection(
          endpoints: endpoints,
          cacheRoot: cacheRoot,
        ),
      ).createClient();

      if (!mounted) return;
      setState(() {
        _status = 'bridge_ready';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.toString();
      });
    } finally {
      await client?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: _constructBridge,
              child: const Text('Construct bridge'),
            ),
            if (_status != null) Text(_status!),
          ],
        ),
      ),
    );
  }
}
