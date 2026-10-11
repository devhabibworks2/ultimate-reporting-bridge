import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'bridge_published_thumbnail_fetch.dart';
import 'bridge_template_cache.dart';
import 'bridge_template_sync.dart';
import 'bridge_template_thumbnail_store.dart';

/// Optional, bounded post-catalog download phase. A failure never invalidates
/// the catalog or triggers generation. Catalog identity stays authoritative.
Future<ThumbnailSyncSummary> syncPublishedTemplateThumbnails({
  required Uri apiBase,
  required Map<String, String> headers,
  required TemplateCacheService cache,
  required String systemCode,
  required Directory globalRoot,
}) async {
  final templates = await cache.listTemplates();
  final images = BridgeTemplateThumbnailStore(
    cacheRoot: cache.cacheRoot,
    globalRoot: globalRoot,
  );
  var index = 0;
  var downloaded = 0;
  var reused = 0;
  var failed = 0;
  var skipped = 0;

  Future<void> worker() async {
    while (true) {
      final next = index++;
      if (next >= templates.length) return;
      final template = templates[next];
      final descriptor = template.publishedThumbnail;
      if (descriptor == null || !descriptor.available) {
        skipped++;
        continue;
      }
      try {
        if (await images.read(template) != null) {
          reused++;
          continue;
        }
        final png = await fetchPublishedThumbnail(
          apiBase: apiBase,
          systemCode: systemCode,
          templateCode: template.templateCode,
          descriptor: descriptor,
          headers: headers,
        );
        if (png == null) {
          failed++;
          continue;
        }
        final current = await cache.getTemplateByCode(template.templateCode);
        final actual = current?.publishedThumbnail;
        if (actual == null ||
            current?.systemCode != template.systemCode ||
            current?.systemId != template.systemId ||
            actual.versionNo != descriptor.versionNo ||
            actual.contentHash != descriptor.contentHash) {
          skipped++;
          continue; // A newer sync invalidated this late image.
        }
        await images.write(template, png);
        downloaded++;
      } on Object {
        failed++;
      }
    }
  }

  final workers = min(4, templates.length);
  await Future.wait(List<Future<void>>.generate(workers, (_) => worker()));
  return ThumbnailSyncSummary(
    downloaded: downloaded,
    reused: reused,
    failed: failed,
    skipped: skipped,
  );
}
