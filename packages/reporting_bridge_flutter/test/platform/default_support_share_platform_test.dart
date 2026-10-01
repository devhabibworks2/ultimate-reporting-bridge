import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';

void main() {
  test(
    'Bridge defaults to unsupported development-support share without share_plus',
    () {
      final bridge = ReportingBridgeFlutter(
        connection: ReportServerConnection(
          endpoints: ReportServerEndpoints.resolve(
            serverUrl: ReportServerEndpoints.parseServerUrl(
              'https://example.invalid',
            ),
            profile: ReportServerProfile.deployed,
          ),
          cacheRoot: Directory.systemTemp,
        ),
      );

      expect(
        bridge.supportSharePlatform,
        isA<UnsupportedReportSupportSharePlatform>(),
      );
      expect(bridge.filePlatform, isA<DefaultReportFilePlatform>());
    },
  );

  test('unsupported support-share fails closed', () async {
    await expectLater(
      const UnsupportedReportSupportSharePlatform().shareArchive(
        Uint8List.fromList(<int>[1, 2, 3]),
        'support.zip',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          'Development-support sharing is unavailable.',
        ),
      ),
    );
  });

  test('default PDF share remains ReportFilePlatform.sharePdf', () {
    const platform = DefaultReportFilePlatform();
    expect(platform, isA<ReportFilePlatform>());
    // Compilation of this call site pins the public sharePdf contract.
    expect(platform.sharePdf, isA<Future<void> Function(Uint8List, String)>());
  });
}
