import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:reporting_bridge_flutter/src/thumbnails/core_published_thumbnail_store.dart';
import 'package:reporting_bridge_flutter/src/thumbnails/native_published_thumbnail_store.dart';
import 'package:reporting_bridge_flutter/src/thumbnails/published_thumbnail_controller.dart';

const hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
  ),
);
final descriptor = BridgePublishedThumbnail.fromMap({
  'versionNo': 3,
  'contentHash': hashA,
  'mimeType': 'image/png',
  'available': true,
})!;

CachedTemplate template() => CachedTemplate(
  type: 'receipt',
  code: 'sale-receipt',
  publishedVersionNo: 3,
  publishedThumbnail: descriptor,
  document: const {'meta': <String, dynamic>{}},
);

void main() {
  late Directory root;
  final api = Uri.parse('https://example.test/UltimateReport/backend/api/');
  final filter = TemplateSyncFilter();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('urb-flutter-core-png-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  CorePublishedThumbnailStore store() => CorePublishedThumbnailStore(
    bridgeRoot: root,
    cacheIdentityBaseUrl: api,
    filter: filter,
    extra: const <String, Object?>{},
  );
  TrustedThumbnailScope scope(String customer, {String? user}) =>
      TrustedThumbnailScope(
        apiBase: api,
        customerContext: customer,
        userId: user,
        systemCode: 'skey-pos',
        templateCode: 'sale-receipt',
      );

  test(
    'Flutter writes the same plain sibling PNG used by the core catalog',
    () async {
      final owned = store();
      final s = scope('a' * 64);
      await owned.write(s, descriptor, png);
      expect(await owned.read(s, descriptor), orderedEquals(png));

      final catalog = bridgeTemplateCacheDirectoryForScope(
        bridgeRoot: root,
        scope: BridgeTemplateCacheScope(
          apiBaseUrl: api,
          authContextDigest: 'a' * 64,
          systemCode: 'skey-pos',
          filter: filter,
          extra: const <String, Object?>{},
        ),
      );
      final core = BridgeTemplateThumbnailStore(cacheRoot: catalog);
      expect(await core.read(template()), orderedEquals(png));
      expect(
        (await catalog.list().where((e) => e is File).toList()).every(
          (e) => e.path.endsWith('.png'),
        ),
        isTrue,
      );
    },
  );

  test(
    'picker controller reuses the same core PNG without another GET',
    () async {
      var gets = 0;
      final controller = PublishedThumbnailController(
        store: store(),
        fetch:
            ({required template, required scope, required cancellation}) async {
              gets++;
              return png;
            },
      );
      addTearDown(controller.dispose);
      final identity = scope('a' * 64);
      expect(
        await controller.imageForVisibleTemplate(template(), identity),
        orderedEquals(png),
      );
      expect(
        await controller.imageForVisibleTemplate(template(), identity),
        orderedEquals(png),
      );
      expect(gets, 1);
    },
  );

  test('historical encrypted bin is ignored but never deleted', () async {
    final owned = store();
    final identity = scope('a' * 64);
    final legacy = File(
      '${root.path}/urb/published-thumbnails/${'a' * 64}/3_$hashA.bin',
    );
    await legacy.parent.create(recursive: true);
    await legacy.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
    expect(await owned.read(identity, descriptor), isNull);
    expect(await legacy.readAsBytes(), <int>[1, 2, 3, 4]);
    await owned.write(identity, descriptor, png);
    expect(await owned.read(identity, descriptor), orderedEquals(png));
    expect(await legacy.readAsBytes(), <int>[1, 2, 3, 4]);
  });

  test('different authenticated customers never share stored PNGs', () async {
    final owned = store();
    final a = scope('a' * 64, user: 'shared-user');
    final b = scope('b' * 64, user: 'shared-user');
    await owned.write(a, descriptor, png);
    expect(await owned.read(a, descriptor), orderedEquals(png));
    expect(await owned.read(b, descriptor), isNull);
  });

  test(
    'missing identity allows GET but never creates unscoped cache',
    () async {
      final owned = store();
      final anonymous = TrustedThumbnailScope(
        apiBase: api,
        cacheEnabled: false,
        systemCode: 'skey-pos',
        templateCode: 'sale-receipt',
      );
      await owned.write(anonymous, descriptor, png);
      expect(await owned.read(anonymous, descriptor), isNull);
      expect(await root.list().toList(), isEmpty);
    },
  );
}
