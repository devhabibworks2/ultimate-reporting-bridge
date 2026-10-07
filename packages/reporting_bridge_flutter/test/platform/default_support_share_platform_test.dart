import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge_flutter/reporting_bridge_flutter.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

void main() {
  test('Bridge defaults to a working development-support share platform', () {
    final bridge = _bridge();

    expect(
      bridge.supportSharePlatform,
      isNot(isA<UnsupportedReportSupportSharePlatform>()),
    );
    expect(bridge.filePlatform, isA<DefaultReportFilePlatform>());
  });

  test(
    'default support-share forwards archive to the system share sheet',
    () async {
      final original = SharePlatform.instance;
      final fake = _FakeSharePlatform();
      SharePlatform.instance = fake;
      addTearDown(() => SharePlatform.instance = original);

      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      const origin = Rect.fromLTWH(10, 20, 30, 40);

      await _bridge().supportSharePlatform.shareArchive(
        bytes,
        'urb_report_issue_test.urb',
        sharePositionOrigin: origin,
      );

      final params = fake.lastParams;
      expect(params, isNotNull);
      expect(await params!.files!.single.readAsBytes(), orderedEquals(bytes));
      expect(params.files!.single.mimeType, 'application/octet-stream');
      expect(params.fileNameOverrides, <String>['urb_report_issue_test.urb']);
      expect(params.sharePositionOrigin, origin);
      expect(params.text, isNull);
      expect(params.uri, isNull);
    },
  );

  test(
    'unsupported support-share fails closed when explicitly selected',
    () async {
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
    },
  );

  test('default PDF share remains ReportFilePlatform.sharePdf', () {
    const platform = DefaultReportFilePlatform();
    expect(platform, isA<ReportFilePlatform>());
    expect(platform.sharePdf, isA<Future<void> Function(Uint8List, String)>());
  });
}

ReportingBridgeFlutter _bridge() => ReportingBridgeFlutter(
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

final class _FakeSharePlatform extends SharePlatform {
  ShareParams? lastParams;

  @override
  Future<ShareResult> share(ShareParams params) async {
    lastParams = params;
    return const ShareResult('fake', ShareResultStatus.success);
  }
}
