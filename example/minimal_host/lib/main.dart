import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  runApp(const MinimalHostApp());
}

class MinimalHostApp extends StatelessWidget {
  const MinimalHostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reporting Bridge Minimal Host',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF29AD5F)),
      ),
      home: const MinimalHostScreen(),
    );
  }
}

class MinimalHostScreen extends StatefulWidget {
  const MinimalHostScreen({super.key});

  @override
  State<MinimalHostScreen> createState() => _MinimalHostScreenState();
}

class _MinimalHostScreenState extends State<MinimalHostScreen> {
  static const String defaultServerUrl = 'https://mdev.yemensoft.net:473';

  static const String serverUrl = String.fromEnvironment(
    'HOST_SERVER_URL',
    defaultValue: defaultServerUrl,
  );

  static const String serverProfileName = String.fromEnvironment(
    'HOST_SERVER_PROFILE',
    defaultValue: 'deployed',
  );

  final TextEditingController _urlController = TextEditingController(
    text: serverUrl,
  );
  bool _opening = false;
  String? _status;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _openReport() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _status = null;
    });

    ReportingBridgeFlutterClient? client;
    try {
      final endpoints = ReportServerEndpoints.resolve(
        serverUrl: ReportServerEndpoints.parseServerUrl(
          _urlController.text.trim(),
        ),
        profile:
            ReportServerProfileX.tryParse(serverProfileName) ??
            ReportServerProfile.deployed,
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
      await client.openReport(
        context,
        ReportOpenRequest(
          seedData: const <String, dynamic>{
            'documentNumber': 'MIN-001',
            'customerName': 'Minimal Host',
          },
          selectedTemplateCriteria: SelectedTemplateCriteria(
            reportType: UrbReportType.salesInvoice,
            identity: const ReportIdentity(
              userId: 'minimal_host',
              branchId: 'branch_01',
            ),
          ),
          templateSyncRequest: TemplateSyncRequest(
            systemCode: UrbSystem.motakamelTransactions,
            identity: const ReportIdentity(
              userId: 'minimal_host',
              branchId: 'branch_01',
            ),
            filter: TemplateSyncFilter(reportTypes: <String>['sales_invoice']),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.toString();
      });
    } finally {
      await client?.dispose();
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minimal Host')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Report Server URL',
                border: OutlineInputBorder(),
              ),
              enabled: !_opening,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _opening ? null : _openReport,
              child: Text(_opening ? 'Opening…' : 'Open report'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Text(_status!),
            ],
          ],
        ),
      ),
    );
  }
}
