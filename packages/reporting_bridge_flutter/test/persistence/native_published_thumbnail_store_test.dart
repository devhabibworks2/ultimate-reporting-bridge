import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:reporting_bridge_flutter/src/thumbnails/core_published_thumbnail_store.dart';
import 'package:reporting_bridge_flutter/src/thumbnails/native_published_thumbnail_store.dart';

final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
  ),
);
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _ref = BridgePublishedThumbnail.fromMap({
  'versionNo': 3,
  'contentHash': _hash,
  'mimeType': 'image/png',
  'available': true,
})!;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('urb-plain-core-thumb-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  CorePublishedThumbnailStore store() => CorePublishedThumbnailStore(
    bridgeRoot: root,
    cacheIdentityBaseUrl: Uri.parse('https://api.example.test/api/'),
    filter: TemplateSyncFilter(),
    extra: const <String, Object?>{},
  );
  TrustedThumbnailScope scope({String? user, String customer = 'a'}) =>
      TrustedThumbnailScope(
        apiBase: Uri.parse('https://api.example.test/api/'),
        userId: user,
        customerContext: customer * 64,
        systemCode: 'sales',
        templateCode: 'invoice',
      );
  test('plain PNG is persisted once and reused offline', () async {
    final owned = store();
    final current = scope();
    await owned.write(current, _ref, _png);
    expect(await owned.read(current, _ref), orderedEquals(_png));
    final files = await root
        .list(recursive: true)
        .where((e) => e is File)
        .toList();
    expect(files, hasLength(1));
    expect(files.single.path, endsWith('.png'));
    expect(await (files.single as File).readAsBytes(), orderedEquals(_png));
  });
  test('optional user cannot cross authenticated customers', () async {
    final owned = store();
    await owned.write(scope(user: 'shared'), _ref, _png);
    expect(
      await owned.read(scope(user: 'shared', customer: 'b'), _ref),
      isNull,
    );
    expect(await owned.read(scope(user: 'shared'), _ref), orderedEquals(_png));
  });
  test('invalid payload fails closed without any PNG artifact', () async {
    final owned = store();
    await expectLater(
      owned.write(scope(), _ref, Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(await root.list(recursive: true).toList(), isEmpty);
  });
  test('old bin remains unreadable and untouched', () async {
    final owned = store();
    final legacy = File('${root.path}/urb/published-thumbnails/legacy.bin');
    await legacy.parent.create(recursive: true);
    await legacy.writeAsBytes([1, 2, 3], flush: true);
    expect(await owned.read(scope(), _ref), isNull);
    expect(await legacy.readAsBytes(), [1, 2, 3]);
  });
}
