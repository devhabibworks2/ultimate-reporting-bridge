import 'dart:async';

import 'package:reporting_bridge/reporting_bridge.dart';

import '../contracts/report_open_request.dart';
import 'presenter_warmup.dart';

typedef PresenterWarmupSurfaceAction = Future<bool> Function();
typedef PresenterWarmupModeResolver =
    Future<PresenterModePreference> Function(ReportOpenRequest request);
typedef PresenterWarmupResourceAction =
    Future<void> Function(
      ReportOpenRequest request,
      PresenterModePreference mode,
    );

final class PresenterWarmupCoordinator {
  PresenterWarmupCoordinator({
    required PresenterWarmupSurfaceAction warmSurface,
    required PresenterWarmupModeResolver resolveMode,
    required PresenterWarmupResourceAction refreshResources,
  }) : _warmSurface = warmSurface,
       _resolveMode = resolveMode,
       _refreshResources = refreshResources;

  final PresenterWarmupSurfaceAction _warmSurface;
  final PresenterWarmupModeResolver _resolveMode;
  final PresenterWarmupResourceAction _refreshResources;

  bool _disposed = false;
  bool _surfaceReady = false;
  Future<_SurfaceOutcome>? _surfaceFuture;
  final Map<_ResourceKey, Future<_ResourceOutcome>> _resourceFutures =
      <_ResourceKey, Future<_ResourceOutcome>>{};

  Future<PresenterWarmupResult> warmUp(
    ReportOpenRequest request, {
    bool refreshResources = false,
    bool warmHeadlessSurface = false,
  }) async {
    if (_disposed) {
      return PresenterWarmupResult(
        surfaceStatus: warmHeadlessSurface
            ? PresenterWarmupSurfaceStatus.failed
            : PresenterWarmupSurfaceStatus.skipped,
        resourceStatus: refreshResources
            ? PresenterWarmupResourceStatus.failed
            : PresenterWarmupResourceStatus.skipped,
        presenterMode: request.presenterMode,
        diagnostic: 'disposed',
      );
    }

    final surfaceFuture = warmHeadlessSurface ? _ensureSurfaceWarm() : null;
    final resourceFuture = refreshResources ? _prepareResources(request) : null;

    final outcomes = await Future.wait<Object?>(<Future<Object?>>[
      if (surfaceFuture != null) surfaceFuture,
      if (resourceFuture != null) resourceFuture,
    ]);

    var index = 0;
    final surface = surfaceFuture == null
        ? const _SurfaceOutcome(PresenterWarmupSurfaceStatus.skipped)
        : outcomes[index++]! as _SurfaceOutcome;
    final resource = resourceFuture == null
        ? _ResourceOutcome(
            PresenterWarmupResourceStatus.skipped,
            request.presenterMode,
          )
        : outcomes[index]! as _ResourceOutcome;

    final diagnostics = <String>[
      if (surface.diagnostic != null) surface.diagnostic!,
      if (resource.diagnostic != null) resource.diagnostic!,
    ];
    return PresenterWarmupResult(
      surfaceStatus: surface.status,
      resourceStatus: resource.status,
      presenterMode: resource.mode ?? request.presenterMode,
      diagnostic: diagnostics.isEmpty ? null : diagnostics.join('\n'),
    );
  }

  Future<_SurfaceOutcome> _ensureSurfaceWarm() {
    if (_surfaceReady) {
      return Future<_SurfaceOutcome>.value(
        const _SurfaceOutcome(PresenterWarmupSurfaceStatus.ready),
      );
    }
    final running = _surfaceFuture;
    if (running != null) return running;

    late final Future<_SurfaceOutcome> future;
    future =
        () async {
          try {
            final ready = await _warmSurface();
            if (ready) _surfaceReady = true;
            return _SurfaceOutcome(
              ready
                  ? PresenterWarmupSurfaceStatus.ready
                  : PresenterWarmupSurfaceStatus.failed,
              ready ? null : 'headlessSurfaceUnavailable',
            );
          } catch (error) {
            return _SurfaceOutcome(
              PresenterWarmupSurfaceStatus.failed,
              error.toString(),
            );
          }
        }().whenComplete(() {
          if (identical(_surfaceFuture, future)) {
            _surfaceFuture = null;
          }
        });
    _surfaceFuture = future;
    return future;
  }

  Future<_ResourceOutcome> _prepareResources(ReportOpenRequest request) async {
    late final PresenterModePreference mode;
    try {
      mode = await _resolveMode(request);
    } catch (error) {
      return _ResourceOutcome(
        PresenterWarmupResourceStatus.failed,
        request.presenterMode,
        error.toString(),
      );
    }

    if (_disposed) {
      return _ResourceOutcome(
        PresenterWarmupResourceStatus.failed,
        mode,
        'disposed',
      );
    }

    final sync = request.templateSyncRequest;
    final identity = sync.identity;
    final key = _ResourceKey(
      systemCode: sync.systemCode.value,
      filterFingerprint: sync.filter.fingerprint,
      extraFingerprint: canonicalJsonFingerprint(sync.extra),
      userId: identity.userId,
      branchId: identity.branchId,
      systemUnit: identity.systemUnit,
      mode: mode,
    );
    final running = _resourceFutures[key];
    if (running != null) return running;

    late final Future<_ResourceOutcome> future;
    future =
        () async {
          try {
            await _refreshResources(request, mode);
            return _ResourceOutcome(
              PresenterWarmupResourceStatus.refreshed,
              mode,
            );
          } catch (error) {
            return _ResourceOutcome(
              PresenterWarmupResourceStatus.failed,
              mode,
              error.toString(),
            );
          }
        }().whenComplete(() {
          if (identical(_resourceFutures[key], future)) {
            _resourceFutures.remove(key);
          }
        });
    _resourceFutures[key] = future;
    return future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _resourceFutures.clear();
    _surfaceFuture = null;
    _surfaceReady = false;
  }
}

final class _SurfaceOutcome {
  const _SurfaceOutcome(this.status, [this.diagnostic]);

  final PresenterWarmupSurfaceStatus status;
  final String? diagnostic;
}

final class _ResourceOutcome {
  const _ResourceOutcome(this.status, this.mode, [this.diagnostic]);

  final PresenterWarmupResourceStatus status;
  final PresenterModePreference? mode;
  final String? diagnostic;
}

final class _ResourceKey {
  const _ResourceKey({
    required this.systemCode,
    required this.filterFingerprint,
    required this.extraFingerprint,
    required this.userId,
    required this.branchId,
    required this.systemUnit,
    required this.mode,
  });

  final String systemCode;
  final String filterFingerprint;
  final String extraFingerprint;
  final String? userId;
  final String? branchId;
  final String? systemUnit;
  final PresenterModePreference mode;

  @override
  bool operator ==(Object other) =>
      other is _ResourceKey &&
      other.systemCode == systemCode &&
      other.filterFingerprint == filterFingerprint &&
      other.extraFingerprint == extraFingerprint &&
      other.userId == userId &&
      other.branchId == branchId &&
      other.systemUnit == systemUnit &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(
    systemCode,
    filterFingerprint,
    extraFingerprint,
    userId,
    branchId,
    systemUnit,
    mode,
  );
}
