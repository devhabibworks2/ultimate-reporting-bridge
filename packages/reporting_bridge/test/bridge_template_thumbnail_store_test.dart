import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
  ),
);
const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

CachedTemplate _template({
  String code = 'INV/../../evil',
  int version = 3,
  String hash = _hashA,
}) => CachedTemplate(
  type: 'invoice',
  code: code,
  publishedVersionNo: version,
  publishedThumbnail: BridgePublishedThumbnail.fromMap({
    'versionNo': version,
    'contentHash': hash,
    'mimeType': 'image/png',
    'available': true,
  }),
  document: const <String, dynamic>{'meta': <String, dynamic>{}},
);

void main() {
  late Directory root;
  late BridgeTemplateThumbnailStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('urb_plain_sibling_png_');
    store = BridgeTemplateThumbnailStore(cacheRoot: root);
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'writes plain unencrypted PNG as sibling of hashed template JSON',
    () async {
      final template = _template();
      final cache = TemplateCacheService(cacheRoot: root);
      await cache.putTemplate(template);
      await store.write(template, _png);
      final digest = sha256
          .convert(utf8.encode(template.templateCode))
          .toString();
      final png = File('${root.path}/tpl_${digest}_3_$_hashA.png');
      final json = File('${root.path}/tpl_$digest.json');
      expect(await json.exists(), isTrue);
      expect(await png.exists(), isTrue);
      expect(await png.readAsBytes(), orderedEquals(_png));
      expect((await store.read(template)), orderedEquals(_png));
      expect(await File('${root.parent.path}/evil').exists(), isFalse);
    },
  );

  test(
    'limits count across two catalogs of one authenticated scope using LRU',
    () async {
      final identityRoot = Directory('${root.path}/scoped/api/identity');
      final firstCatalog = Directory('${identityRoot.path}/catalog_first');
      final secondCatalog = Directory('${identityRoot.path}/catalog_second');
      final first = BridgeTemplateThumbnailStore(
        cacheRoot: firstCatalog,
        scopeRoot: identityRoot,
        globalRoot: root,
        maxImagesPerScope: 2,
      );
      final second = BridgeTemplateThumbnailStore(
        cacheRoot: secondCatalog,
        scopeRoot: identityRoot,
        globalRoot: root,
        maxImagesPerScope: 2,
      );
      final a = _template(code: 'A');
      final b = _template(code: 'B');
      final c = _template(code: 'C');
      await first.write(a, _png);
      final older = File((await firstCatalog.list().first).path);
      await older.setLastModified(DateTime.utc(2020));
      await second.write(b, _png);
      await second.write(c, _png);
      expect(await first.read(a), isNull);
      expect(await second.read(b), orderedEquals(_png));
      expect(await second.read(c), orderedEquals(_png));
    },
  );

  test(
    'enforces global budget across distinct identities and filter catalogs',
    () async {
      final api = Directory('${root.path}/scoped/api');
      final one = Directory('${api.path}/identity1/catalog_a');
      final two = Directory('${api.path}/identity2/catalog_b');
      final s1 = BridgeTemplateThumbnailStore(
        cacheRoot: one,
        scopeRoot: one.parent,
        globalRoot: root,
        maxGlobalBytes: _png.length * 2,
      );
      final s2 = BridgeTemplateThumbnailStore(
        cacheRoot: two,
        scopeRoot: two.parent,
        globalRoot: root,
        maxGlobalBytes: _png.length * 2,
      );
      await s1.write(_template(code: 'A'), _png);
      final oldest = File((await one.list().first).path);
      await oldest.setLastModified(DateTime.utc(2020));
      await s2.write(_template(code: 'B'), _png);
      await s2.write(_template(code: 'C'), _png);
      expect(await s1.read(_template(code: 'A')), isNull);
      expect(await s2.read(_template(code: 'C')), orderedEquals(_png));
    },
  );

  test(
    'refuses a cache directory outside the supplied trusted identity root',
    () async {
      final wrong = Directory('${root.path}/other-user/catalog');
      final trusted = Directory('${root.path}/identity-a');
      final untrusted = BridgeTemplateThumbnailStore(
        cacheRoot: wrong,
        scopeRoot: trusted,
        globalRoot: root,
      );
      await expectLater(
        untrusted.write(_template(code: 'INV'), _png),
        throwsA(isA<StateError>()),
      );
      expect(await wrong.exists(), isFalse);
    },
  );

  test(
    'reading a cached image makes it most recently used for eviction',
    () async {
      final scoped = BridgeTemplateThumbnailStore(
        cacheRoot: root,
        maxImagesPerScope: 2,
      );
      final a = _template(code: 'A');
      final b = _template(code: 'B');
      final c = _template(code: 'C');
      await scoped.write(a, _png);
      await scoped.write(b, _png);
      final aHash = sha256.convert(utf8.encode('A')).toString();
      final bHash = sha256.convert(utf8.encode('B')).toString();
      await File(
        '${root.path}/tpl_${aHash}_3_$_hashA.png',
      ).setLastModified(DateTime.utc(2020));
      await File(
        '${root.path}/tpl_${bHash}_3_$_hashA.png',
      ).setLastModified(DateTime.utc(2021));
      expect(await scoped.read(a), orderedEquals(_png));
      await scoped.write(c, _png);
      expect(await scoped.read(b), isNull);
      expect(await scoped.read(a), orderedEquals(_png));
      expect(await scoped.read(c), orderedEquals(_png));
    },
  );

  test('identity byte cap removes oldest while preserving newest', () async {
    final scoped = BridgeTemplateThumbnailStore(
      cacheRoot: root,
      maxBytesPerScope: _png.length,
    );
    await scoped.write(_template(code: 'A'), _png);
    await scoped.write(_template(code: 'B'), _png);
    expect(await scoped.read(_template(code: 'A')), isNull);
    expect(await scoped.read(_template(code: 'B')), orderedEquals(_png));
  });

  test('mismatching version/hash does not accept older image', () async {
    final template = _template();
    await store.write(template, _png);
    expect(await store.read(_template(version: 4, hash: _hashB)), isNull);
    expect(await store.read(template), orderedEquals(_png));
  });

  test(
    'rejects corrupt signature and preserves old PNG on invalid replacement',
    () async {
      final template = _template();
      await store.write(template, _png);
      expect(
        () => store.write(template, Uint8List.fromList([1, 2, 3])),
        throwsA(isA<FormatException>()),
      );
      expect(await store.read(template), orderedEquals(_png));
    },
  );

  test('rejects too-large image and damaged cached bytes', () async {
    final template = _template();
    expect(
      () => store.write(template, Uint8List(2 * 1024 * 1024 + 1)),
      throwsA(isA<FormatException>()),
    );
    await store.write(template, _png);
    final digest = sha256
        .convert(utf8.encode(template.templateCode))
        .toString();
    final file = File('${root.path}/tpl_${digest}_3_$_hashA.png');
    await file.writeAsBytes([1, 2, 3], flush: true);
    expect(await store.read(template), isNull);
  });

  test(
    'prunes stale sibling PNGs but preserves active image, notes, and links',
    () async {
      final active = _template();
      final old = _template(version: 2, hash: _hashB);
      await store.write(active, _png);
      await store.write(old, _png);
      final note = File('${root.path}/note.txt');
      await note.writeAsString('keep');
      final outside = File(
        '${root.parent.path}/thumbnail-external-sentinel.txt',
      );
      await outside.writeAsString('important');
      addTearDown(() async {
        if (await outside.exists()) await outside.delete();
      });
      final digest = sha256
          .convert(utf8.encode(active.templateCode))
          .toString();
      final link = Link('${root.path}/tpl_${digest}_99_$_hashB.png');
      await link.create(outside.path);
      await store.deleteObsolete([active]);
      expect(await store.read(active), orderedEquals(_png));
      expect(await store.read(old), isNull);
      expect(await note.readAsString(), 'keep');
      expect(await link.exists(), isTrue);
      expect(await outside.readAsString(), 'important');
    },
  );

  test(
    'rejects a modified internal PNG chunk even if the signature and trailer match',
    () async {
      final template = _template();
      await store.write(template, _png);
      final changed = Uint8List.fromList(_png);
      changed[44] ^= 1; // data changed while chunk CRC stays original.
      final digest = sha256
          .convert(utf8.encode(template.templateCode))
          .toString();
      final file = File('${root.path}/tpl_${digest}_3_$_hashA.png');
      await file.writeAsBytes(changed, flush: true);
      expect(await store.read(template), isNull);
    },
  );

  test(
    'rejects a mismatched trusted byte digest without replacing good PNG',
    () async {
      final template = _template();
      await store.write(template, _png);
      expect(
        () => store.write(template, _png, expectedBytesSha256: '0' * 64),
        throwsA(isA<FormatException>()),
      );
      expect(await store.read(template), orderedEquals(_png));
      await store.write(
        template,
        _png,
        expectedBytesSha256: sha256.convert(_png).toString(),
      );
      expect(await store.read(template), orderedEquals(_png));
    },
  );

  test('rejects incomplete PNG despite a valid signature', () async {
    final broken = Uint8List.fromList(_png.sublist(0, 33));
    expect(
      () => store.write(_template(), broken),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'does not write for missing or unavailable published image identity',
    () async {
      final template = CachedTemplate(
        type: 'invoice',
        code: 'NO-IMAGE',
        document: const <String, dynamic>{},
        publishedVersionNo: null,
      );
      expect(() => store.write(template, _png), throwsA(isA<StateError>()));
      expect(await store.read(template), isNull);
    },
  );
}
