import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:reporting_bridge_flutter/src/client/report_server_connection.dart';

void main() {
  final deployed = ReportServerEndpoints.deployed(
    Uri.parse('https://mdev.yemensoft.net:473'),
  );

  test('certificate verification remains enabled by default', () {
    final connection = ReportServerConnection(
      endpoints: deployed,
      cacheRoot: Directory.systemTemp,
    );
    expect(connection.resolvedHttpClientFactory, isNull);
    expect(
      connection.acceptsInvalidCertificateFor('mdev.yemensoft.net', 473),
      isFalse,
    );
  });

  test('opt-in accepts only configured HTTPS server host and port', () {
    final connection = ReportServerConnection(
      endpoints: deployed,
      cacheRoot: Directory.systemTemp,
      allowInvalidServerCertificates: true,
    );
    final client = connection.resolvedHttpClientFactory!();
    addTearDown(() => client.close(force: true));

    expect(
      connection.acceptsInvalidCertificateFor('mdev.yemensoft.net', 473),
      isTrue,
    );
    expect(
      connection.acceptsInvalidCertificateFor('MDEV.YEMENSOFT.NET', 473),
      isTrue,
    );
    expect(
      connection.acceptsInvalidCertificateFor('mdev.yemensoft.net', 443),
      isFalse,
    );
    expect(
      connection.acceptsInvalidCertificateFor('another.example.net', 473),
      isFalse,
    );
  });

  test('HTTPS local-development backend and presenter use exact ports', () {
    final endpoints = ReportServerEndpoints.localDevelopment(
      Uri.parse('https://localhost'),
      backendPort: 8100,
      presenterPort: 8200,
    );
    final connection = ReportServerConnection(
      endpoints: endpoints,
      cacheRoot: Directory.systemTemp,
      allowInvalidServerCertificates: true,
    );
    expect(connection.acceptsInvalidCertificateFor('localhost', 8100), isTrue);
    expect(connection.acceptsInvalidCertificateFor('localhost', 8200), isTrue);
    expect(connection.acceptsInvalidCertificateFor('localhost', 443), isFalse);
  });

  test('HTTP local development never needs certificate bypass', () {
    final endpoints = ReportServerEndpoints.localDevelopment(
      Uri.parse('http://127.0.0.1'),
    );
    final connection = ReportServerConnection(
      endpoints: endpoints,
      cacheRoot: Directory.systemTemp,
      allowInvalidServerCertificates: true,
    );
    expect(connection.acceptsInvalidCertificateFor('127.0.0.1', 8000), isFalse);
    expect(endpoints.apiBaseUrl.scheme, 'http');
    expect(endpoints.presenterEntryUrl.scheme, 'http');
  });

  test('existing custom HTTP client factory retains precedence', () {
    final custom = HttpClient.new;
    final connection = ReportServerConnection(
      endpoints: deployed,
      cacheRoot: Directory.systemTemp,
      allowInvalidServerCertificates: true,
      httpClientFactory: custom,
    );
    expect(connection.resolvedHttpClientFactory, same(custom));
  });
}
