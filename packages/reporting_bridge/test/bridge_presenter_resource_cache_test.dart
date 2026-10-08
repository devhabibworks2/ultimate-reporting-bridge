import 'dart:io';
import 'dart:typed_data';

import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

void main() {
  test(
    'stores bytes under lowercase SHA-256 keys and clears the cache',
    () async {
      final root = await Directory.systemTemp.createTemp('bridge_resource_');
      addTearDown(() => root.delete(recursive: true));
      final cacheRoot = Directory('${root.path}/cache');
      final cache = PresenterResourceCacheStore(cacheRoot: cacheRoot);
      final key = List<String>.filled(64, 'a').join();

      await cache.write(key, Uint8List.fromList(<int>[0, 1, 255]));
      final Uint8List? cached = await cache.read(key);
      expect(cached, Uint8List.fromList(<int>[0, 1, 255]));

      await cache.clear();
      expect(await cache.read(key), isNull);
      expect(await cacheRoot.exists(), isFalse);
    },
  );

  test(
    'rejects invalid keys and entries larger than the configured limit',
    () async {
      final root = await Directory.systemTemp.createTemp('bridge_resource_');
      addTearDown(() => root.delete(recursive: true));
      final cache = PresenterResourceCacheStore(
        cacheRoot: root,
        maxEntryBytes: 2,
      );

      await expectLater(cache.read('A' * 64), throwsArgumentError);
      await expectLater(
        cache.write('short', Uint8List.fromList(<int>[1])),
        throwsArgumentError,
      );
      await expectLater(
        cache.write('b' * 64, Uint8List.fromList(<int>[1, 2, 3])),
        throwsArgumentError,
      );
      expect((await root.list().toList()), isEmpty);
    },
  );

  test(
    'does not read through a digest symlink outside the cache root',
    () async {
      final root = await Directory.systemTemp.createTemp('bridge_resource_');
      addTearDown(() => root.delete(recursive: true));
      final cacheRoot = Directory('${root.path}/cache');
      await cacheRoot.create();
      final outside = File('${root.path}/outside');
      await outside.writeAsString('outside');
      final key = List<String>.filled(64, 'e').join();
      await Link('${cacheRoot.path}/$key').create(outside.path);
      final cache = PresenterResourceCacheStore(cacheRoot: cacheRoot);

      expect(await cache.read(key), isNull);
      await expectLater(
        cache.write(key, Uint8List.fromList(<int>[1])),
        throwsA(isA<FileSystemException>()),
      );
      expect(await outside.readAsString(), 'outside');
    },
  );
  test(
    'persistent bytes survive local session replacement and server stop',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge_cache_sessions_',
      );
      addTearDown(() => root.delete(recursive: true));
      final presenter = Directory(root.path + '/presenter');
      final runtime = Directory(root.path + '/runtime');
      await presenter.create();
      await runtime.create();
      await File(presenter.path + '/index.html').writeAsString('site');
      final store = PresenterResourceCacheStore(
        cacheRoot: Directory(root.path + '/persistent'),
      );
      final key = 'a' * 64;
      await store.write(key, Uint8List.fromList(<int>[9, 8, 7]));
      final server = LocalPresenterServer(
        presenterRoot: presenter,
        runtimeRoot: runtime,
        resourceCacheStore: store,
      );
      final first = await server.start(sessionId: 'first');
      await first.stop();
      final second = await server.start(sessionId: 'second');
      await second.stop();
      await server.stop();
      expect(await store.read(key), Uint8List.fromList(<int>[9, 8, 7]));
    },
  );
}
