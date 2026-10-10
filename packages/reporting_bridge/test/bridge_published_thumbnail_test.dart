import 'package:reporting_bridge/reporting_bridge.dart';
import 'package:test/test.dart';

const validHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  group('BridgePublishedThumbnail', () {
    test(
      'parses a ready descriptor only with a positive version, SHA-256, and PNG MIME',
      () {
        final descriptor = BridgePublishedThumbnail.fromMap(<String, Object?>{
          'versionNo': 3,
          'contentHash': validHash,
          'mimeType': 'image/png',
          'available': true,
        });

        expect(descriptor, isNotNull);
        expect(descriptor!.versionNo, 3);
        expect(descriptor.contentHash, validHash);
        expect(descriptor.mimeType, 'image/png');
        expect(descriptor.available, isTrue);
      },
    );

    test(
      'retains an unavailable valid descriptor without enabling retrieval',
      () {
        final descriptor = BridgePublishedThumbnail.fromMap(<String, Object?>{
          'versionNo': 3,
          'contentHash': validHash,
          'mimeType': 'image/png',
          'available': false,
        });

        expect(descriptor, isNotNull);
        expect(descriptor!.available, isFalse);
      },
    );

    test('rejects malformed and unsupported descriptors without throwing', () {
      for (final value in <Object?>[
        null,
        'legacy',
        <String, Object?>{
          'versionNo': 0,
          'contentHash': validHash,
          'mimeType': 'image/png',
          'available': true,
        },
        <String, Object?>{
          'versionNo': 1,
          'contentHash': 'A' * 64,
          'mimeType': 'image/png',
          'available': true,
        },
        <String, Object?>{
          'versionNo': 1,
          'contentHash': 'short',
          'mimeType': 'image/png',
          'available': true,
        },
        <String, Object?>{
          'versionNo': 1,
          'contentHash': validHash,
          'mimeType': 'image/jpeg',
          'available': true,
        },
        <String, Object?>{
          'versionNo': 1,
          'contentHash': validHash,
          'mimeType': 'image/png',
          'available': 'true',
        },
      ]) {
        expect(BridgePublishedThumbnail.fromMap(value), isNull);
      }
    });
  });

  group('CachedTemplate published thumbnail compatibility', () {
    const document = <String, dynamic>{
      'meta': <String, dynamic>{'code': 'INVOICE-A'},
    };

    Map<String, dynamic> catalogItem({
      int? publishedVersionNo = 3,
      Object? thumbnail = const <String, Object?>{
        'versionNo': 3,
        'contentHash': validHash,
        'mimeType': 'image/png',
        'available': true,
      },
    }) => <String, dynamic>{
      'type': 'invoice',
      'code': 'INVOICE-A',
      'document': document,
      if (publishedVersionNo != null) 'publishedVersionNo': publishedVersionNo,
      if (thumbnail != null) 'thumbnail': thumbnail,
    };

    test(
      'round-trips the exact published descriptor through the file cache map',
      () {
        final template = CachedTemplate.fromMap(catalogItem());
        final restored = CachedTemplate.fromMap(template.toMap());

        expect(restored.publishedThumbnail?.versionNo, 3);
        expect(restored.publishedThumbnail?.contentHash, validHash);
        expect(restored.publishedThumbnail?.available, isTrue);
        expect(restored.publishedVersionNo, 3);
      },
    );

    test('old catalog records without a thumbnail remain compatible', () {
      final template = CachedTemplate.fromMap(catalogItem(thumbnail: null));

      expect(template.publishedThumbnail, isNull);
      expect(template.templateCode, 'INVOICE-A');
    });

    test('drafts and mismatched published versions ignore a descriptor', () {
      expect(
        CachedTemplate.fromMap(
          catalogItem(publishedVersionNo: null),
        ).publishedThumbnail,
        isNull,
      );
      expect(
        CachedTemplate.fromMap(
          catalogItem(
            publishedVersionNo: 4,
            thumbnail: const <String, Object?>{
              'versionNo': 3,
              'contentHash': validHash,
              'mimeType': 'image/png',
              'available': true,
            },
          ),
        ).publishedThumbnail,
        isNull,
      );
    });

    test('malformed descriptors never enable retrieval', () {
      final template = CachedTemplate.fromMap(
        catalogItem(
          thumbnail: const <String, Object?>{
            'versionNo': 3,
            'contentHash': 'invalid',
            'mimeType': 'image/png',
            'available': true,
          },
        ),
      );

      expect(template.publishedThumbnail, isNull);
    });

    test(
      'manually constructed stale descriptor cannot bind another version',
      () {
        final stale = BridgePublishedThumbnail.fromMap(<String, Object?>{
          'versionNo': 2,
          'contentHash': validHash,
          'mimeType': 'image/png',
          'available': true,
        });
        final template = CachedTemplate(
          type: 'invoice',
          code: 'INVOICE-A',
          document: document,
          publishedVersionNo: 3,
          publishedThumbnail: stale,
        );

        expect(template.publishedThumbnail, isNull);
        expect(template.toMap().containsKey('thumbnail'), isFalse);
      },
    );

    test(
      'published metadata does not change durable TemplateCode selection',
      () {
        final template = CachedTemplate.fromMap(catalogItem());

        expect(template.selectedTemplate.code, 'INVOICE-A');
        expect(template.selectedTemplate.toMap().containsKey('id'), isFalse);
        expect(template.toMap().containsKey('id'), isFalse);
      },
    );
  });
}
