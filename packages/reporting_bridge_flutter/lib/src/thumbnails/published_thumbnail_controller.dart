import 'dart:async';
import 'dart:typed_data';

import 'package:reporting_bridge/reporting_bridge.dart';

import 'native_published_thumbnail_store.dart';

typedef PublishedThumbnailFetch =
    Future<Uint8List?> Function({
      required CachedTemplate template,
      required TrustedThumbnailScope scope,
      required Future<void> cancellation,
    });

/// Loads only bytes already published and stored by the server.
final class PublishedThumbnailController {
  PublishedThumbnailController({
    required NativePublishedThumbnailStore store,
    required PublishedThumbnailFetch fetch,
  }) : _store = store,
       _fetch = fetch;

  factory PublishedThumbnailController.forServer({
    required NativePublishedThumbnailStore store,
    required Uri apiBase,
    required Map<String, String> headers,
  }) => PublishedThumbnailController(
    store: store,
    fetch: ({required template, required scope, required cancellation}) =>
        fetchPublishedThumbnail(
          apiBase: apiBase,
          systemCode: scope.systemCode,
          templateCode: scope.templateCode,
          descriptor: template.publishedThumbnail!,
          headers: headers,
          cancellation: cancellation,
        ),
  );

  static const int maxConcurrentRequests = 4;

  final NativePublishedThumbnailStore _store;
  final PublishedThumbnailFetch _fetch;
  final Set<_ThumbnailCancellation> _requests = <_ThumbnailCancellation>{};
  final Map<String, Map<String, BridgePublishedThumbnail>> _confirmed =
      <String, Map<String, BridgePublishedThumbnail>>{};
  String? _activeIdentity;
  int _generation = 0;
  int _activeRequests = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];
  bool _disposed = false;

  Future<Uint8List?> imageForVisibleTemplate(
    CachedTemplate template,
    TrustedThumbnailScope scope,
  ) async {
    if (_disposed) return null;
    final thumbnail = template.publishedThumbnail;
    if (thumbnail == null || !thumbnail.available) return null;
    final imageScope = _scopeFor(template, scope);
    if (imageScope == null) return null;
    _activate(imageScope);
    final generation = _generation;

    final cached = await _store.read(imageScope, thumbnail);
    if (cached != null) {
      return _isCurrent(imageScope, generation) ? cached : null;
    }

    await _acquireRequestSlot();
    if (!_isCurrent(imageScope, generation)) {
      _releaseRequestSlot();
      return null;
    }
    final cancellation = _ThumbnailCancellation();
    _requests.add(cancellation);
    try {
      final fetched = await _fetch(
        template: template,
        scope: imageScope,
        cancellation: cancellation.future,
      );
      if (!_isCurrent(imageScope, generation) || cancellation.isCancelled) {
        return null;
      }
      if (fetched == null) return null;
      await _store.write(imageScope, thumbnail, fetched);
      return _isCurrent(imageScope, generation) ? fetched : null;
    } on Object {
      if (!_isCurrent(imageScope, generation) || cancellation.isCancelled) {
        return null;
      }
      final cachedAfterFailure = await _store.read(imageScope, thumbnail);
      return _isCurrent(imageScope, generation) ? cachedAfterFailure : null;
    } finally {
      _requests.remove(cancellation);
      _releaseRequestSlot();
    }
  }

  Future<ThumbnailSyncSummary> synchronizeAvailablePublishedThumbnails(
    Iterable<CachedTemplate> catalog,
    TrustedThumbnailScope scope,
  ) async {
    if (_disposed) {
      return const ThumbnailSyncSummary(
        downloaded: 0,
        reused: 0,
        failed: 0,
        skipped: 0,
      );
    }
    _activate(scope);
    final operationGeneration = _generation;
    final templates = catalog.toList(growable: false);
    final current = <String, BridgePublishedThumbnail>{};
    for (final template in templates) {
      final ref = template.publishedThumbnail;
      if (ref != null && ref.available) current[template.templateCode] = ref;
    }
    final previous = _confirmed[scope.identityFingerprint];
    if (previous != null) {
      for (final entry in previous.entries) {
        final ref = current[entry.key];
        if (!_samePublication(entry.value, ref)) {
          await _store.invalidateScope(scope.forTemplateCode(entry.key));
        }
      }
    }
    _confirmed[scope.identityFingerprint] = current;

    var downloaded = 0;
    var reused = 0;
    var failed = 0;
    var skipped = 0;
    var next = 0;
    final workers = List<Future<void>>.generate(maxConcurrentRequests, (
      _,
    ) async {
      while (_isCurrent(scope, operationGeneration)) {
        final index = next++;
        if (index >= templates.length) return;
        final template = templates[index];
        final ref = template.publishedThumbnail;
        if (ref == null || !ref.available) {
          skipped++;
          continue;
        }
        final templateScope = scope.forTemplateCode(template.templateCode);
        final existing = await _store.read(templateScope, ref);
        if (!_isCurrent(scope, operationGeneration)) return;
        if (existing != null) {
          reused++;
          continue;
        }
        try {
          final bytes = await imageForVisibleTemplate(template, templateScope);
          if (!_isCurrent(scope, operationGeneration)) return;
          if (bytes == null) {
            failed++;
          } else {
            downloaded++;
          }
        } on Object {
          failed++;
        }
      }
    });
    await Future.wait(workers);
    return ThumbnailSyncSummary(
      downloaded: downloaded,
      reused: reused,
      failed: failed,
      skipped: skipped,
    );
  }

  /// Cancels in-flight work when the picker leaves the screen.
  void leaveScreen() {
    _generation++;
    for (final request in _requests.toList()) {
      request.cancel();
    }
    _activeIdentity = null;
  }

  void dispose() {
    if (_disposed) return;
    leaveScreen();
    _disposed = true;
  }

  void _activate(TrustedThumbnailScope scope) {
    final identity = scope.identityFingerprint;
    if (_activeIdentity == identity) return;
    for (final request in _requests.toList()) {
      request.cancel();
    }
    _activeIdentity = identity;
    _generation++;
  }

  bool _isCurrent(TrustedThumbnailScope scope, int generation) =>
      !_disposed &&
      _activeIdentity == scope.identityFingerprint &&
      _generation == generation;

  TrustedThumbnailScope? _scopeFor(
    CachedTemplate template,
    TrustedThumbnailScope supplied,
  ) {
    try {
      return supplied.forTemplateCode(template.templateCode);
    } on Object {
      return null;
    }
  }

  Future<void> _acquireRequestSlot() async {
    while (_activeRequests >= maxConcurrentRequests) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _activeRequests++;
  }

  void _releaseRequestSlot() {
    _activeRequests--;
    if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
  }
}

bool _samePublication(
  BridgePublishedThumbnail left,
  BridgePublishedThumbnail? right,
) =>
    right != null &&
    left.versionNo == right.versionNo &&
    left.contentHash == right.contentHash;

final class _ThumbnailCancellation {
  final Completer<void> _completer = Completer<void>();
  Future<void> get future => _completer.future;
  bool get isCancelled => _completer.isCompleted;
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}
