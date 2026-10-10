import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:reporting_bridge_flutter/src/thumbnails/native_published_thumbnail_store.dart';
import 'package:reporting_bridge_flutter/src/thumbnails/published_thumbnail_controller.dart';

const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
final _png = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10, 1, 2]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late NativePublishedThumbnailStore store;
  late _Keys keys;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('thumbnail-controller-');
    keys = _Keys();
    store = NativePublishedThumbnailStore(
      root: root,
      keyProvider: keys,
      nativeEnabled: true,
    );
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('missing and unavailable descriptors make no image request', () async {
    var requests = 0;
    final controller = PublishedThumbnailController(
      store: store,
      fetch:
          ({required template, required scope, required cancellation}) async {
            requests++;
            return _png;
          },
    );
    expect(
      await controller.imageForVisibleTemplate(_template(null), _scope()),
      isNull,
    );
    expect(
      await controller.imageForVisibleTemplate(
        _template(_ref(available: false)),
        _scope(),
      ),
      isNull,
    );
    expect(requests, 0);
    controller.dispose();
  });

  test(
    'downloads ready image, then reuses it offline only for same identity',
    () async {
      var online = true;
      var requests = 0;
      final controller = PublishedThumbnailController(
        store: store,
        fetch:
            ({required template, required scope, required cancellation}) async {
              requests++;
              if (!online) throw const SocketException('offline');
              return _png;
            },
      );
      final template = _template(_ref());
      expect(
        await controller.imageForVisibleTemplate(template, _scope()),
        _png,
      );
      online = false;
      expect(
        await controller.imageForVisibleTemplate(template, _scope()),
        _png,
      );
      expect(
        await controller.imageForVisibleTemplate(
          template,
          _scope(user: 'other'),
        ),
        isNull,
      );
      expect(requests, 2);
      controller.dispose();
    },
  );

  test(
    'sync caps active fetches at four and skips unavailable descriptors',
    () async {
      var active = 0;
      var peak = 0;
      final controller = PublishedThumbnailController(
        store: store,
        fetch:
            ({required template, required scope, required cancellation}) async {
              active++;
              if (active > peak) peak = active;
              await Future<void>.delayed(const Duration(milliseconds: 10));
              active--;
              return _png;
            },
      );
      final templates = <CachedTemplate>[
        for (var i = 0; i < 9; i++)
          _template(
            _ref(version: i + 1, hash: i.isEven ? _hashA : _hashB),
            code: 't$i',
          ),
        _template(_ref(available: false), code: 'unavailable'),
      ];
      final summary = await controller.synchronizeAvailablePublishedThumbnails(
        templates,
        _scope(),
      );
      expect(peak, lessThanOrEqualTo(4));
      expect(summary.skipped, 1);
      expect(summary.downloaded, 9);
      controller.dispose();
    },
  );

  test(
    'changed publication invalidates prior version and leave cancels detached result',
    () async {
      final pending = Completer<Uint8List?>();
      final fetchStarted = Completer<void>();
      var cancellationObserved = false;
      final controller = PublishedThumbnailController(
        store: store,
        fetch: ({required template, required scope, required cancellation}) {
          if (!fetchStarted.isCompleted) fetchStarted.complete();
          cancellation.then((_) => cancellationObserved = true);
          return pending.future;
        },
      );
      final old = _template(_ref(version: 1, hash: _hashA));
      await store.write(_scope(), _ref(version: 1, hash: _hashA), _png);
      expect(await controller.imageForVisibleTemplate(old, _scope()), _png);
      await controller.synchronizeAvailablePublishedThumbnails(<CachedTemplate>[
        old,
      ], _scope());
      final pendingImage = controller.imageForVisibleTemplate(
        _template(_ref(version: 2, hash: _hashB)),
        _scope(),
      );
      await fetchStarted.future;
      controller.leaveScreen();
      pending.complete(_png);
      expect(await pendingImage, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(cancellationObserved, isTrue);
      await controller.synchronizeAvailablePublishedThumbnails(<CachedTemplate>[
        _template(_ref(version: 2, hash: _hashB)),
      ], _scope());
      expect(
        await store.read(_scope(), _ref(version: 1, hash: _hashA)),
        isNull,
      );
      controller.dispose();
    },
  );
}

CachedTemplate _template(
  BridgePublishedThumbnail? ref, {
  String code = 'report',
}) => CachedTemplate(
  type: 'report',
  code: code,
  publishedVersionNo: ref?.versionNo,
  publishedThumbnail: ref,
  document: const <String, dynamic>{},
);
BridgePublishedThumbnail _ref({
  int version = 1,
  String hash = _hashA,
  bool available = true,
}) => BridgePublishedThumbnail.fromMap(<String, Object>{
  'versionNo': version,
  'contentHash': hash,
  'mimeType': 'image/png',
  'available': available,
})!;
TrustedThumbnailScope _scope({
  String user = 'user',
  String template = 'report',
}) => TrustedThumbnailScope(
  apiBase: Uri.parse('https://api.example.test/'),
  tenantId: 'customer',
  userId: user,
  systemCode: 'sales',
  templateCode: template,
);

final class _Keys implements ThumbnailKeyProvider {
  final key = Uint8List.fromList(List<int>.filled(32, 7));
  @override
  Future<Uint8List?> loadOrCreateKey() async => key;
}
