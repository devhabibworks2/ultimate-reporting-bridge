import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:reporting_bridge_flutter/src/thumbnails/native_published_thumbnail_store.dart';

const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
final _png = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 1, 2]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late _MemoryKeyProvider keys;
  late NativePublishedThumbnailStore store;
  var tick = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('published-thumbnail-store-');
    keys = _MemoryKeyProvider();
    store = NativePublishedThumbnailStore(
      root: root,
      keyProvider: keys,
      clock: () => DateTime.utc(2025).add(Duration(seconds: tick++)),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'writes encrypted bytes and reads only under the same identity scope',
    () async {
      final a = _scope(user: 'user-a', tenant: 'customer-a');
      final b = _scope(user: 'user-b', tenant: 'customer-b');
      final ref = _ref(_hashA);

      await store.write(a, ref, _png);

      expect(await store.read(a, ref), _png);
      expect(await store.read(b, ref), isNull);
      final files = await root
          .list(recursive: true)
          .where((e) => e is File)
          .cast<File>()
          .toList();
      expect(files, hasLength(1));
      expect(await files.single.readAsBytes(), isNot(contains(137)));
    },
  );

  test(
    'wrong key, modified ciphertext, and truncated files fail closed',
    () async {
      final scope = _scope();
      final ref = _ref(_hashA);
      await store.write(scope, ref, _png);
      keys.key = Uint8List.fromList(List<int>.filled(32, 9));
      expect(await store.read(scope, ref), isNull);
      keys.key = Uint8List.fromList(List<int>.filled(32, 7));
      await store.write(scope, ref, _png);
      final file =
          (await root
                  .list(recursive: true)
                  .where((e) => e is File)
                  .cast<File>()
                  .toList())
              .single;
      await file.writeAsBytes(<int>[1, 2, 3], flush: true);
      expect(await store.read(scope, ref), isNull);
    },
  );

  test('authenticated ciphertext bit flips are rejected', () async {
    final scope = _scope();
    final ref = _ref(_hashA);
    await store.write(scope, ref, _png);
    final file =
        (await root
                .list(recursive: true)
                .where((e) => e is File)
                .cast<File>()
                .toList())
            .single;
    final bytes = await file.readAsBytes();
    bytes[bytes.length - 1] ^= 0x80;
    await file.writeAsBytes(bytes, flush: true);
    expect(await store.read(scope, ref), isNull);
  });

  test(
    'A to B to A only reopens the matching authenticated identity',
    () async {
      final a = _scope(user: 'user-a');
      final b = _scope(user: 'user-b');
      final ref = _ref(_hashA);
      await store.write(a, ref, _png);
      expect(await store.read(b, ref), isNull);
      expect(await store.read(a, ref), _png);
    },
  );

  test(
    'repeated equal identity is a no-op and changed content hash is distinct',
    () async {
      final scope = _scope();
      await store.write(scope, _ref(_hashA), _png);
      final file =
          (await root
                  .list(recursive: true)
                  .where((e) => e is File)
                  .cast<File>()
                  .toList())
              .single;
      final ciphertext = await file.readAsBytes();
      await store.write(scope, _ref(_hashA), _png);
      expect(await file.readAsBytes(), ciphertext);
      await store.write(scope, _ref(_hashB), _png);
      expect(await store.read(scope, _ref(_hashA)), _png);
      expect(await store.read(scope, _ref(_hashB)), _png);
    },
  );

  test(
    'path traversal selectors cannot escape the hashed store root',
    () async {
      final scope = _scope(templateCode: '../../outside');
      await store.write(scope, _ref(_hashA), _png);
      expect(await store.read(scope, _ref(_hashA)), _png);
      expect(await File('${root.parent.path}/outside').exists(), isFalse);
    },
  );

  test(
    '65th image evicts least recently used image in the identity scope',
    () async {
      final scope = _scope();
      for (var i = 0; i < 65; i++) {
        await store.write(
          scope,
          _ref(i.toRadixString(16).padLeft(64, '0')),
          _png,
        );
      }
      expect(await store.read(scope, _ref('0' * 64)), isNull);
      expect((await store.stats()).imageCount, 64);
    },
  );

  test(
    '16 MiB identity byte quota evicts least recently used images',
    () async {
      final scope = _scope();
      final payload = Uint8List(2 * 1024 * 1024)
        ..setRange(0, 8, <int>[137, 80, 78, 71, 13, 10, 26, 10]);
      for (var i = 1; i <= 9; i++) {
        await store.write(
          scope,
          _ref(i.toRadixString(16).padLeft(64, '0')),
          payload,
        );
      }
      final stats = await store.stats();
      expect(stats.totalBytes, lessThanOrEqualTo(16 * 1024 * 1024));
      expect(stats.imageCount, 8);
      expect(await store.read(scope, _ref('1'.padLeft(64, '0'))), isNull);
    },
  );

  test('scope invalidation removes access to that identity only', () async {
    final a = _scope(user: 'user-a');
    final b = _scope(user: 'user-b');
    final ref = _ref(_hashA);
    await store.write(a, ref, _png);
    await store.write(b, ref, _png);
    await store.invalidateScope(a);
    expect(await store.read(a, ref), isNull);
    expect(await store.read(b, ref), _png);
  });

  test(
    'oversized individual image and unavailable descriptor are refused',
    () async {
      final scope = _scope();
      await expectLater(
        store.write(scope, _ref(_hashA), Uint8List(2 * 1024 * 1024 + 1)),
        throwsArgumentError,
      );
      await expectLater(
        store.write(scope, _ref(_hashA, available: false), _png),
        throwsArgumentError,
      );
      expect((await store.stats()).imageCount, 0);
    },
  );

  test(
    'missing protected key and web-disabled store do not persist images',
    () async {
      final scope = _scope();
      final ref = _ref(_hashA);
      final unavailable = NativePublishedThumbnailStore(
        root: root,
        keyProvider: _UnavailableKeyProvider(),
      );
      await unavailable.write(scope, ref, _png);
      expect(await unavailable.read(scope, ref), isNull);

      final web = NativePublishedThumbnailStore(
        root: root,
        keyProvider: keys,
        nativeEnabled: false,
      );
      await web.write(scope, ref, _png);
      expect(await web.read(scope, ref), isNull);
      expect(await root.list(recursive: true).toList(), isEmpty);
    },
  );
}

TrustedThumbnailScope _scope({
  String user = 'user-a',
  String tenant = 'tenant-a',
  String templateCode = 'invoice-A',
}) => TrustedThumbnailScope(
  apiBase: Uri.parse('https://api.example.test/api/'),
  tenantId: tenant,
  userId: user,
  systemCode: 'sales',
  templateCode: templateCode,
);

BridgePublishedThumbnail _ref(String hash, {bool available = true}) =>
    BridgePublishedThumbnail.fromMap(<String, Object?>{
      'versionNo': 2,
      'contentHash': hash,
      'mimeType': 'image/png',
      'available': available,
    })!;

class _MemoryKeyProvider implements ThumbnailKeyProvider {
  Uint8List key = Uint8List.fromList(List<int>.filled(32, 7));
  @override
  Future<Uint8List?> loadOrCreateKey() async => key;
}

class _UnavailableKeyProvider implements ThumbnailKeyProvider {
  @override
  Future<Uint8List?> loadOrCreateKey() async => null;
}
