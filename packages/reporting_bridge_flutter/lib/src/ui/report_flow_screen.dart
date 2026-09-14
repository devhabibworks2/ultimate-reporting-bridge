import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../flow/report_flow_controller.dart';
import '../flow/report_flow_event.dart';
import '../flow/report_flow_failure.dart';
import '../flow/report_flow_state.dart';
import '../contracts/report_open_request.dart';
import '../flow/report_result.dart';
import '../localization/report_flow_strings.dart';
import '../printing/thermal_printer_controller.dart';
import '../printing/thermal_printer_models.dart';
import 'bridge_presenter_view.dart';
import 'bridge_ui_config.dart';
import 'bridge_ui_features.dart';
import 'presenter_action_dock.dart';
import 'template_presentation.dart';
import 'thermal_printer_settings_screen.dart';

TextDirection _contentTextDirection(String value, TextDirection fallback) {
  final arabic = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]',
  ).firstMatch(value);
  final latin = RegExp(r'[A-Za-z]').firstMatch(value);
  if (arabic == null && latin == null) return fallback;
  if (arabic == null) return TextDirection.ltr;
  if (latin == null) return TextDirection.rtl;
  return arabic.start < latin.start ? TextDirection.rtl : TextDirection.ltr;
}

String _failureCodeValue(ReportFlowFailure failure) {
  final technical = failure.technicalCode?.trim();
  return technical == null || technical.isEmpty ? failure.code.name : technical;
}

String _failureCombinedMessage(
  ReportFlowFailure failure,
  ReportFlowStrings strings,
) {
  const isolateStart = '\u2068';
  const isolateEnd = '\u2069';
  final parts = <String>[];
  final seenRawValues = <String>{};

  String? normalize(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void addRaw(Object? value) {
    final normalized = normalize(value);
    if (normalized != null && seenRawValues.add(normalized)) {
      parts.add(normalized);
    }
  }

  void addTechnical(String label, Object? value) {
    final normalized = normalize(value);
    if (normalized != null && seenRawValues.add(normalized)) {
      parts.add('$label: $isolateStart$normalized$isolateEnd');
    }
  }

  addRaw(failure.diagnostic);
  addTechnical(strings.technicalCategory, failure.technicalCategory);
  addTechnical(strings.technicalPath, failure.technicalPath);
  for (final entry in failure.details.entries) {
    addTechnical(entry.key, entry.value);
  }
  if (parts.isEmpty) addRaw(strings.failure(failure));
  return parts.join('\n');
}

bool _templateQueryScopeLimited(TemplateSyncFilter filter) {
  bool limited(List<String> values) => !values.contains('all');
  return limited(filter.reportTypes) ||
      limited(filter.layouts) ||
      limited(filter.sizes) ||
      limited(filter.languages) ||
      limited(filter.units) ||
      limited(filter.orientations);
}

class ReportFlowScreen extends StatefulWidget {
  const ReportFlowScreen({
    super.key,
    required this.controller,
    required this.ui,
  });

  final ReportFlowController controller;
  final BridgeUiConfig ui;

  @override
  State<ReportFlowScreen> createState() => _ReportFlowScreenState();
}

class _ReportFlowScreenState extends State<ReportFlowScreen> {
  final TextEditingController _searchController = TextEditingController();
  ReportFlowStage? _previousStage;
  TemplateSelectionOrigin? _previousSelectionOrigin;
  StreamSubscription<ReportFlowEvent>? _eventSubscription;
  bool _allowRoutePop = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleStateChange);
    _eventSubscription = widget.controller.events.listen(_handleEvent);
    unawaited(widget.controller.initialize());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleStateChange);
    unawaited(_eventSubscription?.cancel());
    _searchController.dispose();
    unawaited(widget.controller.dispose());
    super.dispose();
  }

  void _handleStateChange() {
    final stage = widget.controller.value.stage;
    final enteringSelection = stage == ReportFlowStage.selectingTemplate;
    final selectionOrigin = widget.controller.value.selectionOrigin;
    if (enteringSelection &&
        (stage != _previousStage ||
            selectionOrigin != _previousSelectionOrigin)) {
      _searchController.clear();
    }
    _previousStage = stage;
    _previousSelectionOrigin = selectionOrigin;
    if (mounted) setState(() {});
  }

  void _handleEvent(ReportFlowEvent event) {
    if (!mounted) return;
    final strings = ReportFlowStrings.of(
      context,
      override: widget.controller.request.localeOverride,
    );
    final String? message;
    switch (event.type) {
      case ReportFlowEventType.exportCompleted:
        message = switch (event.detail) {
          'share' => strings.pdfShared,
          'print' => strings.printSubmitted,
          _ => strings.pdfSaved,
        };
      case ReportFlowEventType.exportCancelled:
        message = event.detail == 'print' ? strings.printCancelled : null;
      default:
        message = null;
    }
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.value;
    final strings = ReportFlowStrings.of(
      context,
      override: widget.controller.request.localeOverride,
    );
    final theme = widget.ui.resolve(Theme.of(context));
    final features =
        widget.controller.request.featuresOverride ?? widget.ui.features;
    return Theme(
      data: theme,
      child: Directionality(
        textDirection: strings.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: PopScope<Object?>(
          canPop: _allowRoutePop,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || state.busy) return;
            if (state.stage == ReportFlowStage.selectingTemplate) {
              widget.controller.backToPreparation();
            } else if (state.stage == ReportFlowStage.editingSettings) {
              widget.controller.cancelSettings();
            } else if (state.stage == ReportFlowStage.preparingResources &&
                state.resourceOrigin !=
                    ResourcePreparationOrigin.initialSetup) {
              widget.controller.returnFromResourcePreparation();
            } else {
              unawaited(_close());
            }
          },
          child: _keepsPresenterMounted(state)
              ? _PersistentPreviewFlow(
                  state: state,
                  controller: widget.controller,
                  strings: strings,
                  features: features,
                  searchController: _searchController,
                  onClose: _close,
                )
              : switch (state.stage) {
                  ReportFlowStage.initializing => _BootstrapPage(
                    message: strings.loading,
                  ),
                  ReportFlowStage.preparingResources => _PreparationPage(
                    state: state,
                    controller: widget.controller,
                    strings: strings,
                    features: features,
                    onClose: _close,
                  ),
                  ReportFlowStage.selectingTemplate => _SelectionPage(
                    state: state,
                    controller: widget.controller,
                    strings: strings,
                    features: features,
                    searchController: _searchController,
                  ),
                  ReportFlowStage.editingSettings => _SettingsPage(
                    state: state,
                    controller: widget.controller,
                    strings: strings,
                    features: features,
                  ),
                  ReportFlowStage.preparingPreview => _ProgressPage(
                    message: strings.preparingPreview,
                  ),
                  ReportFlowStage.previewing => _PreviewPage(
                    state: state,
                    controller: widget.controller,
                    strings: strings,
                    features: features,
                    onClose: _close,
                  ),
                  ReportFlowStage.failed => _FailurePage(
                    strings: strings,
                    failure: state.failure,
                    onRetry: widget.controller.retry,
                    onClose: _close,
                  ),
                  ReportFlowStage.closing || ReportFlowStage.closed =>
                    _ProgressPage(message: strings.loading),
                },
        ),
      ),
    );
  }

  bool _keepsPresenterMounted(ReportFlowState state) {
    if (state.presenterLaunch == null) return false;
    return switch (state.stage) {
      ReportFlowStage.previewing || ReportFlowStage.failed => true,
      ReportFlowStage.editingSettings => true,
      ReportFlowStage.selectingTemplate =>
        state.selectionOrigin == TemplateSelectionOrigin.reportSettings ||
            state.selectionOrigin == TemplateSelectionOrigin.previewRecovery,
      ReportFlowStage.preparingResources =>
        state.resourceOrigin == ResourcePreparationOrigin.reportSettings ||
            state.resourceOrigin == ResourcePreparationOrigin.previewRecovery,
      _ => false,
    };
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    final strings = ReportFlowStrings.of(
      context,
      override: widget.controller.request.localeOverride,
    );
    if (widget.controller.value.exportAction != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.failure(
              const ReportFlowFailure(
                code: ReportFlowFailureCode.exportInProgress,
              ),
            ),
          ),
        ),
      );
      return;
    }
    _closing = true;
    try {
      final result = await widget.controller.close();
      if (!mounted) return;
      setState(() => _allowRoutePop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop<ReportResult>(result);
      });
    } catch (error) {
      _closing = false;
      if (!mounted) return;
      final failure = error is ReportFlowFailure
          ? error
          : ReportFlowFailure(
              code: ReportFlowFailureCode.unknown,
              diagnostic: error.toString(),
            );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.failure(failure))));
    }
  }
}

class _PersistentPreviewFlow extends StatelessWidget {
  const _PersistentPreviewFlow({
    required this.state,
    required this.controller,
    required this.strings,
    required this.features,
    required this.searchController,
    required this.onClose,
  });

  final ReportFlowState state;
  final ReportFlowController controller;
  final ReportFlowStrings strings;
  final BridgeUiFeatures features;
  final TextEditingController searchController;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final overlay = switch (state.stage) {
      ReportFlowStage.editingSettings => _SettingsPage(
        state: state,
        controller: controller,
        strings: strings,
        features: features,
      ),
      ReportFlowStage.selectingTemplate
          when state.selectionOrigin ==
                  TemplateSelectionOrigin.reportSettings ||
              state.selectionOrigin ==
                  TemplateSelectionOrigin.previewRecovery =>
        _SelectionPage(
          state: state,
          controller: controller,
          strings: strings,
          features: features,
          searchController: searchController,
        ),
      ReportFlowStage.preparingResources
          when state.resourceOrigin ==
                  ResourcePreparationOrigin.reportSettings ||
              state.resourceOrigin ==
                  ResourcePreparationOrigin.previewRecovery =>
        _PreparationPage(
          state: state,
          controller: controller,
          strings: strings,
          features: features,
          onClose: onClose,
        ),
      _ => null,
    };

    final preview = _PreviewPage(
      state: state,
      controller: controller,
      strings: strings,
      features: features,
      onClose: onClose,
    );
    final overlayActive = overlay != null;

    // Always keep the same Stack/preview subtree shape across Preview and
    // settings-owned stages. Changing from `_PreviewPage` directly to a Stack
    // would dispose the platform WebView before the overlay even appeared.
    // The opaque overlay owns input and semantics while the Presenter stays
    // mounted underneath with its current page/zoom state intact.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ExcludeSemantics(
          excluding: overlayActive,
          child: IgnorePointer(ignoring: overlayActive, child: preview),
        ),
        if (overlay != null) overlay,
      ],
    );
  }
}

class _BootstrapPage extends StatelessWidget {
  const _BootstrapPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Scaffold(
      appBar: AppBar(title: Text(message)),
      body: SafeArea(
        child: Semantics(
          label: message,
          liveRegion: true,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Container(
                    height: 28,
                    width: 180,
                    decoration: BoxDecoration(
                      color: placeholder,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (var index = 0; index < 2; index++) ...<Widget>[
                    Container(
                      height: 132,
                      decoration: BoxDecoration(
                        color: placeholder,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressPage extends StatelessWidget {
  const _ProgressPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PreparationPage extends StatelessWidget {
  const _PreparationPage({
    required this.state,
    required this.controller,
    required this.strings,
    required this.features,
    required this.onClose,
  });

  final ReportFlowState state;
  final ReportFlowController controller;
  final ReportFlowStrings strings;
  final BridgeUiFeatures features;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final templateBusy = state.templateSync == ReportOperationStatus.running;
    final presenterBusy = state.presenterSync == ReportOperationStatus.running;
    final offline = state.selectedMode == PresenterModePreference.offline;
    final syncRequest = controller.request.templateSyncRequest;
    final queryScopeLimited =
        _templateQueryScopeLimited(syncRequest.filter) ||
        syncRequest.extra.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.title),
        leading: IconButton(
          tooltip:
              state.resourceOrigin == ResourcePreparationOrigin.initialSetup
              ? strings.close
              : strings.back,
          onPressed: state.resourcesBusy
              ? null
              : state.resourceOrigin == ResourcePreparationOrigin.initialSetup
              ? onClose
              : controller.returnFromResourcePreparation,
          icon: state.resourceOrigin == ResourcePreparationOrigin.initialSetup
              ? const Icon(Icons.close)
              : const BackButtonIcon(),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: <Widget>[
                _StepHeader(
                  stepLabel:
                      state.resourceOrigin ==
                          ResourcePreparationOrigin.initialSetup
                      ? strings.stepOneOfTwo
                      : strings.resources,
                  title: strings.preparation,
                  description: strings.preparationDescription,
                ),
                const SizedBox(height: 14),
                if (state.entryFallbackReason != null &&
                    state.resourceOrigin ==
                        ResourcePreparationOrigin.initialSetup) ...<Widget>[
                  _EntryFallback(
                    message: strings.entryFallback(state.entryFallbackReason!),
                  ),
                  const SizedBox(height: 14),
                ],
                if (features.allowOfflineMode) ...<Widget>[
                  _ModeControl(
                    selected: state.selectedMode,
                    enabled: !state.resourcesBusy,
                    offlineAvailable: state.presenterCached,
                    strings: strings,
                    onChanged: controller.selectMode,
                  ),
                  const SizedBox(height: 14),
                ],
                _ResourceCard(
                  icon: Icons.description_outlined,
                  title: strings.templatesResource,
                  status:
                      (state.templateCatalogCount > 0 || state.templatesReady)
                      ? strings.ready
                      : strings.notReady,
                  ready: state.templateCatalogCount > 0 || state.templatesReady,
                  description: strings.templatesHelp(
                    queryScopeLimited: queryScopeLimited,
                  ),
                  detail: _templateResourceDetail(
                    context,
                    state,
                    strings,
                    queryScopeLimited: queryScopeLimited,
                  ),
                  busy: templateBusy,
                  actionLabel: templateBusy
                      ? strings.syncingTemplates
                      : strings.updateTemplates,
                  onAction: state.resourcesBusy
                      ? null
                      : controller.syncTemplates,
                  failure: state.templateSyncFailure,
                  failureKeyPrefix: 'templates',
                  strings: strings,
                ),
                const SizedBox(height: 12),
                _ResourceCard(
                  icon: Icons.phone_android_outlined,
                  title: strings.presenterResource,
                  status: state.presenterCached
                      ? strings.ready
                      : offline
                      ? strings.downloadRequired
                      : strings.optional,
                  ready: state.presenterCached || !offline,
                  description: offline
                      ? strings.presenterOfflineHelp
                      : strings.presenterOnlineHelp,
                  detail: _presenterResourceDetail(context, state, strings),
                  busy: presenterBusy,
                  progress: presenterBusy
                      ? state.presenterDownloadProgress
                      : null,
                  actionLabel: presenterBusy
                      ? strings.syncingPresenter
                      : state.presenterCached
                      ? strings.refreshPresenter
                      : strings.updatePresenter,
                  onAction: state.resourcesBusy
                      ? null
                      : controller.syncPresenter,
                  failure: state.presenterSyncFailure,
                  failureKeyPrefix: 'presenter',
                  strings: strings,
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: state.preparationReady
                ? controller.continueFromPreparation
                : null,
            icon: const Icon(Icons.arrow_forward),
            label: Text(strings.continueLabel),
          ),
        ),
      ),
    );
  }

  String _templateResourceDetail(
    BuildContext context,
    ReportFlowState state,
    ReportFlowStrings strings, {
    required bool queryScopeLimited,
  }) {
    final catalogCount = state.templateCatalogCount > 0
        ? state.templateCatalogCount
        : state.templates.length;
    final details = <String>[
      strings.templateCatalogDetail(
        cachedCount: catalogCount,
        compatibleCount: state.templates.length,
        queryScopeLimited: queryScopeLimited,
      ),
    ];
    final syncedAt = state.templatesSyncedAt;
    if (syncedAt != null) {
      details.add(
        strings.lastSynchronized(
          MaterialLocalizations.of(context).formatMediumDate(syncedAt),
        ),
      );
    }
    return details.join('\n');
  }

  String? _presenterResourceDetail(
    BuildContext context,
    ReportFlowState state,
    ReportFlowStrings strings,
  ) {
    final manifest = state.presenterManifest;
    if (manifest == null) return null;
    final updatedAt = manifest.updatedAt ?? manifest.syncedAt;
    return strings.presenterBundleDetails(
      presenterVersion: manifest.presenterVersion ?? strings.notReady,
      bundleVersion: manifest.bundleVersion,
      updatedDate: updatedAt == null
          ? null
          : MaterialLocalizations.of(context).formatMediumDate(updatedAt),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.stepLabel,
    required this.title,
    required this.description,
  });

  final String stepLabel;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            stepLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.icon,
    required this.title,
    required this.status,
    required this.ready,
    required this.description,
    required this.busy,
    required this.actionLabel,
    required this.onAction,
    required this.strings,
    required this.failureKeyPrefix,
    this.detail,
    this.progress,
    this.failure,
  });

  final IconData icon;
  final String title;
  final String status;
  final bool ready;
  final String description;
  final bool busy;
  final String? detail;
  final double? progress;
  final String actionLabel;
  final Future<void> Function()? onAction;
  final ReportFlowFailure? failure;
  final ReportFlowStrings strings;
  final String failureKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final heading = Row(
                  children: <Widget>[
                    Icon(icon, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                );
                final pill = _StatusPill(label: status, ready: ready);
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      heading,
                      const SizedBox(height: 8),
                      pill,
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    Expanded(child: heading),
                    const SizedBox(width: 8),
                    pill,
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Text(description, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                detail!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (busy) ...<Widget>[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                borderRadius: BorderRadius.circular(999),
              ),
              if (progress != null) ...<Widget>[
                const SizedBox(height: 5),
                Text('${(progress! * 100).round()}%'),
              ],
            ],
            if (failure != null) ...<Widget>[
              const SizedBox(height: 12),
              _ResourceFailureSection(
                failure: failure!,
                summary: strings.failure(failure),
                strings: strings,
                keyPrefix: failureKeyPrefix,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAction == null
                    ? null
                    : () => unawaited(onAction!()),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.ready});

  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ready ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: ready ? scheme.onPrimaryContainer : scheme.onErrorContainer,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ResourceFailureSection extends StatefulWidget {
  const _ResourceFailureSection({
    required this.failure,
    required this.summary,
    required this.strings,
    required this.keyPrefix,
  });

  final ReportFlowFailure failure;
  final String summary;
  final ReportFlowStrings strings;
  final String keyPrefix;

  @override
  State<_ResourceFailureSection> createState() =>
      _ResourceFailureSectionState();
}

class _ResourceFailureSectionState extends State<_ResourceFailureSection> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ResourceFailureSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.failure, widget.failure)) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = _failureCombinedMessage(widget.failure, widget.strings);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.summary,
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (_expanded) ...<Widget>[
              const SizedBox(height: 10),
              Divider(color: scheme.onErrorContainer.withValues(alpha: 0.22)),
              const SizedBox(height: 4),
              _FailureValueBlock(
                label: widget.strings.errorCode,
                labelColor: scheme.onErrorContainer.withValues(alpha: 0.78),
                child: SelectableText(
                  _failureCodeValue(widget.failure),
                  textDirection: TextDirection.ltr,
                  textAlign: Directionality.of(context) == TextDirection.rtl
                      ? TextAlign.right
                      : TextAlign.left,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _FailureValueBlock(
                label: widget.strings.errorMessage,
                labelColor: scheme.onErrorContainer.withValues(alpha: 0.78),
                child: SelectableText(
                  message,
                  textDirection: _contentTextDirection(
                    message,
                    Directionality.of(context),
                  ),
                  textAlign: Directionality.of(context) == TextDirection.rtl
                      ? TextAlign.right
                      : TextAlign.left,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.35,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey<String>(
                  '${widget.keyPrefix}-resource-error-${_expanded ? 'less' : 'more'}',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(
                  _expanded ? widget.strings.less : widget.strings.more,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureValueBlock extends StatelessWidget {
  const _FailureValueBlock({
    required this.label,
    required this.child,
    this.labelColor,
  });

  final String label;
  final Widget child;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$label :',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: labelColor ?? scheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: child),
      ],
    );
  }
}

class _ExpandableFailureMessage extends StatefulWidget {
  const _ExpandableFailureMessage({
    required this.message,
    required this.strings,
  });

  final String message;
  final ReportFlowStrings strings;

  @override
  State<_ExpandableFailureMessage> createState() =>
      _ExpandableFailureMessageState();
}

class _ExpandableFailureMessageState extends State<_ExpandableFailureMessage> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ExpandableFailureMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(height: 1.45);
    final direction = _contentTextDirection(
      widget.message,
      Directionality.of(context),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.message, style: style),
          maxLines: 2,
          textDirection: direction,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final canExpand = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.message,
              key: const ValueKey<String>('render-failure-message'),
              textDirection: direction,
              textAlign: Directionality.of(context) == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left,
              maxLines: _expanded ? null : 2,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: style,
            ),
            if (canExpand || _expanded)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: ValueKey<String>(
                    _expanded ? 'render-failure-less' : 'render-failure-more',
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(
                    _expanded ? widget.strings.less : widget.strings.more,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Rect? _sharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return null;
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

Future<void> _shareDevelopmentSupport(
  BuildContext context,
  ReportFlowController controller,
  ReportFlowStrings strings,
) async {
  final shareOrigin = _sharePositionOrigin(context);
  try {
    await controller.shareDevelopmentSupportPackage(
      sharePositionOrigin: shareOrigin,
    );
  } catch (error) {
    if (!context.mounted) return;
    final failure = error is ReportFlowFailure
        ? error
        : ReportFlowFailure(
            code: ReportFlowFailureCode.developmentSupportFailed,
            diagnostic: error.toString(),
          );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(strings.failure(failure))));
  }
}

Future<void> _confirmAndClearCachedResources(
  BuildContext context,
  ReportFlowController controller,
  ReportFlowStrings strings,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: Text(
        strings.clearCacheWarningTitle,
        style: Theme.of(
          dialogContext,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      content: Text(
        strings.clearCacheWarningBody,
        style: Theme.of(dialogContext).textTheme.bodyMedium,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(strings.deleteCache),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await controller.clearCachedResources();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(strings.cacheCleared)));
  } catch (error) {
    if (!context.mounted) return;
    final failure = error is ReportFlowFailure
        ? error
        : ReportFlowFailure(
            code: ReportFlowFailureCode.cacheClearFailed,
            diagnostic: error.toString(),
          );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(strings.failure(failure))));
  }
}

class _InlineFailure extends StatelessWidget {
  const _InlineFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryFallback extends StatelessWidget {
  const _EntryFallback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TemplateQuickFilter { all, pages, thermal, a4, thermal80 }

String _templateQuickFilterLabel(
  _TemplateQuickFilter filter,
  ReportFlowStrings strings,
) => switch (filter) {
  _TemplateQuickFilter.all => strings.all,
  _TemplateQuickFilter.pages => strings.templateFilterPages,
  _TemplateQuickFilter.thermal => strings.templateFilterThermal,
  _TemplateQuickFilter.a4 => strings.templateFilterA4,
  _TemplateQuickFilter.thermal80 => strings.templateFilter80mm,
};

IconData? _templateQuickFilterIcon(_TemplateQuickFilter filter) =>
    switch (filter) {
      _TemplateQuickFilter.all => null,
      _TemplateQuickFilter.pages => Icons.description_outlined,
      _TemplateQuickFilter.thermal => Icons.receipt_long_outlined,
      _TemplateQuickFilter.a4 => null,
      _TemplateQuickFilter.thermal80 => null,
    };

bool _matchesTemplateQuickFilter(
  TemplatePresentationMetadata metadata,
  _TemplateQuickFilter filter,
) => switch (filter) {
  _TemplateQuickFilter.all => true,
  _TemplateQuickFilter.pages => metadata.layout.name == 'pages',
  _TemplateQuickFilter.thermal => metadata.layout.name == 'thermal',
  _TemplateQuickFilter.a4 => metadata.size.name == 'a4',
  _TemplateQuickFilter.thermal80 => metadata.size.name == 'thermal80',
};

String _displayTemplateName(String value) => value
    .replaceAll(
      RegExp(r'\s*\(\s*case\s*\d+\s*\)\s*', caseSensitive: false),
      ' ',
    )
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .trim();

class _SelectionPage extends StatefulWidget {
  const _SelectionPage({
    required this.state,
    required this.controller,
    required this.strings,
    required this.features,
    required this.searchController,
  });

  final ReportFlowState state;
  final ReportFlowController controller;
  final ReportFlowStrings strings;
  final BridgeUiFeatures features;
  final TextEditingController searchController;

  @override
  State<_SelectionPage> createState() => _SelectionPageState();
}

class _SelectionPageState extends State<_SelectionPage> {
  _TemplateQuickFilter _quickFilter = _TemplateQuickFilter.all;

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _SelectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.selectionOrigin != widget.state.selectionOrigin) {
      _quickFilter = _TemplateQuickFilter.all;
    }
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _selectQuickFilter(_TemplateQuickFilter filter) {
    if (_quickFilter == filter) return;
    setState(() => _quickFilter = filter);
  }

  void _clearLocalFilters() {
    widget.searchController.clear();
    if (_quickFilter != _TemplateQuickFilter.all) {
      setState(() => _quickFilter = _TemplateQuickFilter.all);
    }
  }

  List<CachedTemplate> _visibleTemplates() {
    final query = widget.searchController.text.trim().toLowerCase();
    return widget.state.templates
        .where((template) {
          final metadata = TemplatePresentationMetadata.tryFromTemplate(
            template,
            strings: widget.strings,
          );
          if (metadata == null) return false;
          if (!_matchesTemplateQuickFilter(metadata, _quickFilter)) {
            return false;
          }
          if (query.isEmpty) return true;
          final displayName = _displayTemplateName(template.templateName);
          return template.searchableMetadata.contains(query) ||
              displayName.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final settingsMode =
        widget.state.selectionOrigin == TemplateSelectionOrigin.reportSettings;
    final recoveryMode =
        widget.state.selectionOrigin == TemplateSelectionOrigin.previewRecovery;
    final templates = _visibleTemplates();
    final hasLocalFilters =
        widget.searchController.text.trim().isNotEmpty ||
        _quickFilter != _TemplateQuickFilter.all;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          settingsMode ? widget.strings.settings : widget.strings.title,
        ),
        leading: IconButton(
          tooltip: settingsMode ? widget.strings.cancel : widget.strings.back,
          onPressed: widget.controller.backToPreparation,
          icon: const BackButtonIcon(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!settingsMode) ...<Widget>[
                    _StepHeader(
                      stepLabel: widget.strings.stepTwoOfTwo,
                      title: widget.strings.selectTemplate,
                      description: widget.strings.templateSelectionHelp(
                        widget.state.templates.length,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    key: const ValueKey<String>('template-search-field'),
                    controller: widget.searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: widget.strings.searchTemplates,
                      prefixIcon: widget.strings.arabic
                          ? null
                          : const Icon(Icons.search),
                      suffixIcon: widget.strings.arabic
                          ? const Icon(Icons.search)
                          : null,
                      filled: true,
                      fillColor: scheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: scheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.strings.templateSelectionPrompt,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (final filter in _TemplateQuickFilter.values) ...[
                          _TemplateFilterChip(
                            filter: filter,
                            selected: _quickFilter == filter,
                            strings: widget.strings,
                            enabled: !widget.state.busy,
                            onSelected: () => _selectQuickFilter(filter),
                          ),
                          if (filter != _TemplateQuickFilter.values.last)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.state.failure != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _InlineFailure(
                  message: widget.strings.failure(widget.state.failure),
                ),
              ),
            if (templates.isEmpty)
              _TemplateEmptyState(
                strings: widget.strings,
                showClearAction: hasLocalFilters,
                onClear: _clearLocalFilters,
              )
            else
              for (final template in templates)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 5, 16, 7),
                  child: _TemplateCard(
                    template: template,
                    selected: widget.state.selectedTemplateId == template.id,
                    showMetadata: widget.features.showTemplateMetadata,
                    strings: widget.strings,
                    onTap: widget.state.busy
                        ? null
                        : () => widget.controller.selectTemplate(template.id),
                  ),
                ),
          ],
        ),
      ),
      bottomNavigationBar: _SelectionActions(
        settingsMode: settingsMode,
        recoveryMode: recoveryMode,
        busy: widget.state.busy,
        canContinue: widget.state.selectedTemplate != null,
        strings: widget.strings,
        onCancel: widget.controller.backToPreparation,
        onContinue: settingsMode
            ? () async => widget.controller.confirmTemplateSelection()
            : widget.controller.preparePreview,
      ),
    );
  }
}

class _TemplateFilterChip extends StatelessWidget {
  const _TemplateFilterChip({
    required this.filter,
    required this.selected,
    required this.strings,
    required this.enabled,
    required this.onSelected,
  });

  final _TemplateQuickFilter filter;
  final bool selected;
  final ReportFlowStrings strings;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final icon = _templateQuickFilterIcon(filter);
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      key: ValueKey<String>('template-filter-${filter.name}'),
      selected: selected,
      showCheckmark: false,
      onSelected: enabled ? (_) => onSelected() : null,
      avatar: icon == null ? null : Icon(icon, size: 17),
      label: Text(_templateQuickFilterLabel(filter, strings)),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: scheme.primaryContainer.withValues(alpha: 0.55),
      backgroundColor: scheme.surface,
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
      ),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _TemplateEmptyState extends StatelessWidget {
  const _TemplateEmptyState({
    required this.strings,
    required this.showClearAction,
    required this.onClear,
  });

  final ReportFlowStrings strings;
  final bool showClearAction;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.search_off_outlined,
                size: 34,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                strings.noSearchResults,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                strings.adjustTemplateSearchOrFilters,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (showClearAction) ...<Widget>[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  key: const ValueKey<String>('template-clear-filters'),
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: Text(strings.clearTemplateFilters),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionActions extends StatelessWidget {
  const _SelectionActions({
    required this.settingsMode,
    required this.recoveryMode,
    required this.busy,
    required this.canContinue,
    required this.strings,
    required this.onCancel,
    required this.onContinue,
  });

  final bool settingsMode;
  final bool recoveryMode;
  final bool busy;
  final bool canContinue;
  final ReportFlowStrings strings;
  final VoidCallback onCancel;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return Material(
      elevation: 8,
      color: scheme.surface,
      surfaceTintColor: scheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(1) >= 1.3;
            final secondary = OutlinedButton(
              onPressed: busy ? null : onCancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 54),
                shape: shape,
              ),
              child: Text(
                settingsMode || recoveryMode ? strings.cancel : strings.back,
              ),
            );
            final primary = FilledButton(
              onPressed: busy || !canContinue
                  ? null
                  : () => unawaited(onContinue()),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 54),
                shape: shape,
              ),
              child: Text(
                settingsMode || recoveryMode
                    ? strings.useTemplate
                    : strings.adoptAndOpenReport,
                maxLines: stacked ? null : 1,
                overflow: stacked
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                softWrap: stacked,
                textAlign: TextAlign.center,
              ),
            );
            if (stacked) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  secondary,
                  const SizedBox(height: 8),
                  primary,
                ],
              );
            }
            return SizedBox(
              height: 54,
              child: Row(
                children: <Widget>[
                  Expanded(flex: 4, child: secondary),
                  const SizedBox(width: 10),
                  Expanded(flex: 6, child: primary),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.state,
    required this.controller,
    required this.strings,
    required this.features,
  });

  final ReportFlowState state;
  final ReportFlowController controller;
  final ReportFlowStrings strings;
  final BridgeUiFeatures features;

  @override
  Widget build(BuildContext context) {
    final template = state.selectedTemplate ?? state.committedTemplate;
    final scheme = Theme.of(context).colorScheme;
    final openTemplateSelection = state.busy
        ? null
        : () => controller.openTemplateSelection(
            origin: TemplateSelectionOrigin.reportSettings,
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.settings),
        leading: IconButton(
          tooltip: strings.cancel,
          onPressed: state.busy ? null : controller.cancelSettings,
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
              children: <Widget>[
                _SettingsSectionTitle(strings.defaultTemplate),
                const SizedBox(height: 8),
                if (template != null && features.showCurrentTemplate)
                  _CurrentTemplateCard(
                    key: const ValueKey<String>('settings-current-template'),
                    template: template,
                    strings: strings,
                    onChangeTemplate: openTemplateSelection,
                  )
                else
                  _SettingsSurface(
                    child: _SettingsActionTile(
                      key: const ValueKey<String>('settings-change-template'),
                      icon: Icons.description_outlined,
                      title: strings.changeTemplate,
                      onTap: openTemplateSelection,
                    ),
                  ),
                if (features.showPrint &&
                    controller.thermalPrinterSettings != null) ...<Widget>[
                  const SizedBox(height: 16),
                  const _SettingsSectionTitle('الطباعة'),
                  const SizedBox(height: 8),
                  _SettingsSurface(
                    child: ValueListenableBuilder<ThermalPrinterSettingsState>(
                      valueListenable: controller.thermalPrinterSettings!,
                      builder: (context, printerState, _) =>
                          _SettingsActionTile(
                            key: const ValueKey<String>(
                              'settings-thermal-printer-row',
                            ),
                            icon: Icons.print_outlined,
                            title: printerState.profile == null
                                ? 'إعداد الطابعة الحرارية'
                                : printerState.profile!.displayName,
                            description: printerState.profile == null
                                ? 'لم يتم إعداد طابعة افتراضية.'
                                : 'تغيير الاتصال، عرض الطباعة، وخيارات الورق.',
                            onTap: state.busy
                                ? null
                                : () => Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          ThermalPrinterSettingsScreen(
                                            controller: controller
                                                .thermalPrinterSettings!,
                                          ),
                                    ),
                                  ),
                          ),
                    ),
                  ),
                ],
                if (features.allowOfflineMode) ...<Widget>[
                  const SizedBox(height: 16),
                  _SettingsSectionTitle(strings.presenterMode),
                  const SizedBox(height: 8),
                  _ModeControl(
                    selected: state.settingsDraft?.mode ?? state.selectedMode,
                    enabled: !state.busy,
                    offlineAvailable: state.presenterCached,
                    strings: strings,
                    onChanged: controller.selectMode,
                  ),
                ],
                const SizedBox(height: 16),
                _SettingsSectionTitle(strings.resources),
                const SizedBox(height: 8),
                _SettingsSurface(
                  child: _SettingsActionTile(
                    key: const ValueKey<String>('settings-resource-row'),
                    icon: Icons.sync_rounded,
                    title: strings.prepareAndSynchronize,
                    description: strings.prepareAndSynchronizeDescription,
                    onTap: state.busy
                        ? null
                        : () => controller.openResourcePreparation(
                            ResourcePreparationOrigin.reportSettings,
                          ),
                  ),
                ),
                if (controller.supportActionsAvailable) ...<Widget>[
                  const SizedBox(height: 16),
                  _SettingsSectionTitle(strings.maintenanceAndSupport),
                  const SizedBox(height: 8),
                  _SettingsSupportActions(
                    state: state,
                    controller: controller,
                    strings: strings,
                    showDevelopmentSupport: features.showDevelopmentSupport,
                  ),
                ],
                if (state.failure != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _InlineFailure(message: strings.failure(state.failure)),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Material(
        elevation: 2,
        color: scheme.surface,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(1) >= 1.3;
              final cancel = OutlinedButton(
                onPressed: state.busy ? null : controller.cancelSettings,
                child: Text(
                  strings.cancel,
                  maxLines: stacked ? null : 1,
                  overflow: stacked
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: stacked,
                  textAlign: TextAlign.center,
                ),
              );
              final save = FilledButton(
                onPressed: state.busy || template == null
                    ? null
                    : () => unawaited(controller.commitSettings()),
                child: Text(
                  strings.saveAndRefresh,
                  maxLines: stacked ? null : 1,
                  overflow: stacked
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: stacked,
                  textAlign: TextAlign.center,
                ),
              );
              if (stacked) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[cancel, const SizedBox(height: 8), save],
                );
              }
              return SizedBox(
                height: 52,
                child: Row(
                  children: <Widget>[
                    Expanded(flex: 4, child: cancel),
                    const SizedBox(width: 8),
                    Expanded(flex: 6, child: save),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
  );
}

class _SettingsSurface extends StatelessWidget {
  const _SettingsSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.012),
        scheme.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.78)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _SettingsLeadingIcon extends StatelessWidget {
  const _SettingsLeadingIcon({required this.icon, this.destructive = false});

  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = destructive ? scheme.error : scheme.primary;
    final background = destructive
        ? scheme.errorContainer.withValues(alpha: 0.62)
        : scheme.primaryContainer.withValues(alpha: 0.58);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, color: foreground, size: 22),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.description,
    this.destructive = false,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String? description;
  final VoidCallback? onTap;
  final bool destructive;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleColor = destructive ? scheme.error : scheme.onSurface;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      minVerticalPadding: 8,
      leading: loading
          ? Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.58),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(11),
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: scheme.primary,
              ),
            )
          : _SettingsLeadingIcon(icon: icon, destructive: destructive),
      title: Text(
        title,
        style: TextStyle(color: titleColor, fontWeight: FontWeight.w800),
      ),
      subtitle: description == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                description!,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: destructive
            ? scheme.error.withValues(alpha: 0.82)
            : scheme.onSurfaceVariant,
      ),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}

class _SettingsSupportActions extends StatelessWidget {
  const _SettingsSupportActions({
    required this.state,
    required this.controller,
    required this.strings,
    required this.showDevelopmentSupport,
  });

  final ReportFlowState state;
  final ReportFlowController controller;
  final ReportFlowStrings strings;
  final bool showDevelopmentSupport;

  @override
  Widget build(BuildContext context) {
    final sharingSupport = state.supportShare == ReportOperationStatus.running;
    final actions = <Widget>[
      if (showDevelopmentSupport)
        _SettingsActionTile(
          key: const ValueKey<String>('settings-support-share-row'),
          icon: Icons.ios_share_outlined,
          title: sharingSupport
              ? strings.preparingDevelopmentSupportShare
              : strings.sendReportDataToDevelopment,
          description: strings.developmentSupportDescription,
          loading: sharingSupport,
          onTap: state.busy
              ? null
              : () => unawaited(
                  _shareDevelopmentSupport(context, controller, strings),
                ),
        ),
      _SettingsActionTile(
        key: const ValueKey<String>('settings-clear-cache-row'),
        icon: Icons.delete_outline_rounded,
        title: strings.clearCacheFiles,
        description: strings.clearCacheFilesDescription,
        destructive: true,
        onTap: state.busy
            ? null
            : () => unawaited(
                _confirmAndClearCachedResources(context, controller, strings),
              ),
      ),
    ];
    return _SettingsSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < actions.length; index++) ...<Widget>[
            actions[index],
            if (index != actions.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.62),
              ),
          ],
        ],
      ),
    );
  }
}

class _ModeControl extends StatelessWidget {
  const _ModeControl({
    required this.selected,
    required this.enabled,
    required this.offlineAvailable,
    required this.strings,
    required this.onChanged,
  });

  final PresenterModePreference selected;
  final bool enabled;
  final bool offlineAvailable;
  final ReportFlowStrings strings;
  final ValueChanged<PresenterModePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final offline = selected == PresenterModePreference.offline;
    return _SettingsSurface(
      child: SwitchListTile.adaptive(
        key: const ValueKey<String>('settings-offline-mode-row'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        secondary: _SettingsLeadingIcon(
          icon: offline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
        ),
        title: Text(
          strings.usePresenterOffline,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          !offlineAvailable
              ? strings.presenterOfflineUnavailableHelp
              : offline
              ? strings.presenterOfflineHelp
              : strings.presenterOnlineHelp,
        ),
        value: offline,
        onChanged: !enabled || (!offline && !offlineAvailable)
            ? null
            : (value) => onChanged(
                value
                    ? PresenterModePreference.offline
                    : PresenterModePreference.online,
              ),
      ),
    );
  }
}

class _CurrentTemplateCard extends StatelessWidget {
  const _CurrentTemplateCard({
    super.key,
    required this.template,
    required this.strings,
    required this.onChangeTemplate,
  });

  final CachedTemplate template;
  final ReportFlowStrings strings;
  final VoidCallback? onChangeTemplate;

  @override
  Widget build(BuildContext context) {
    final metadata = TemplatePresentationMetadata.tryFromTemplate(
      template,
      strings: strings,
    );
    if (metadata == null) {
      return const SizedBox.shrink();
    }
    final displayName = _displayTemplateName(template.templateName);
    final label =
        '${strings.currentTemplate}: $displayName, '
        '${metadata.reportTypeLabel}, ${metadata.languageLabel}, '
        '${metadata.layoutLabel}, ${metadata.sizeLabel}, '
        '${metadata.orientationLabel}, ${metadata.versionLabel}';
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      selected: true,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          key: const ValueKey<String>('settings-current-template-surface'),
          color: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.018),
            scheme.surface,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.primary.withValues(alpha: 0.78),
              width: 1.2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TemplatePreview(metadata: metadata, width: 82, height: 104),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textDirection: _contentTextDirection(
                                displayName,
                                Directionality.of(context),
                              ),
                              textAlign: TextAlign.start,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.check_circle,
                            color: scheme.primary,
                            size: 28,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.055),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Text(
                            strings.currentTemplate,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          _MetadataChip(metadata.reportTypeLabel),
                          _MetadataChip(metadata.languageLabel),
                          _MetadataChip(metadata.layoutLabel),
                          _MetadataChip(metadata.sizeLabel),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: OutlinedButton.icon(
                          key: const ValueKey<String>(
                            'settings-change-template-action',
                          ),
                          onPressed: onChangeTemplate,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: Text(
                            strings.changeTemplate,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.showMetadata,
    required this.strings,
    required this.onTap,
  });

  final CachedTemplate template;
  final bool selected;
  final bool showMetadata;
  final ReportFlowStrings strings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final metadata = TemplatePresentationMetadata.tryFromTemplate(
      template,
      strings: strings,
    );
    if (metadata == null) {
      return const SizedBox.shrink();
    }
    final displayName = _displayTemplateName(template.templateName);
    final label =
        '$displayName, ${metadata.description}, '
        '${metadata.reportTypeLabel}, ${metadata.languageLabel}, '
        '${metadata.layoutLabel}, ${metadata.sizeLabel}, '
        '${metadata.orientationLabel}, ${metadata.versionLabel}';
    final scheme = Theme.of(context).colorScheme;
    final selectedSurface = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.08),
      scheme.surface,
    );

    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          key: ValueKey<String>('template-card-${template.id}'),
          color: selected ? selectedSurface : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.8 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final compact = constraints.maxWidth < 360 || textScale >= 1.6;
                final previewWidth = compact ? 86.0 : 94.0;
                final previewHeight = compact ? 108.0 : 118.0;
                return Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TemplatePreview(
                        metadata: metadata,
                        width: previewWidth,
                        height: previewHeight,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textDirection: _contentTextDirection(
                                displayName,
                                Directionality.of(context),
                              ),
                              textAlign: TextAlign.start,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (showMetadata) ...<Widget>[
                              const SizedBox(height: 5),
                              Text(
                                metadata.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: _contentTextDirection(
                                  metadata.description,
                                  Directionality.of(context),
                                ),
                                textAlign: TextAlign.start,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: <Widget>[
                                  _MetadataChip(metadata.reportTypeLabel),
                                  _MetadataChip(metadata.languageLabel),
                                  _MetadataChip(metadata.layoutLabel),
                                  _MetadataChip(metadata.sizeLabel),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 34),
                        child: _TemplateSelectionIndicator(
                          templateId: template.id,
                          selected: selected,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateSelectionIndicator extends StatelessWidget {
  const _TemplateSelectionIndicator({
    required this.templateId,
    required this.selected,
  });

  final String templateId;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey<String>('template-selection-$templateId'),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: selected ? 1.5 : 2,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Icon(Icons.check, size: 18, color: scheme.onPrimary)
          : null,
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PreviewPage extends StatelessWidget {
  const _PreviewPage({
    required this.state,
    required this.controller,
    required this.strings,
    required this.features,
    required this.onClose,
  });

  final ReportFlowState state;
  final ReportFlowController controller;
  final ReportFlowStrings strings;
  final BridgeUiFeatures features;
  final Future<void> Function() onClose;

  Future<void> _print(BuildContext context) async {
    try {
      await controller.printPdf();
    } catch (error) {
      if (!context.mounted) return;
      final failure = error is ReportFlowFailure
          ? error
          : ReportFlowFailure(
              code: ReportFlowFailureCode.printFailed,
              diagnostic: error.toString(),
            );
      final printerSettings = controller.thermalPrinterSettings;
      if (failure.code == ReportFlowFailureCode.printSetupRequired &&
          printerSettings != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                ThermalPrinterSettingsScreen(controller: printerSettings),
          ),
        );
        return;
      }
      final needsPrinterSettings =
          failure.code ==
              ReportFlowFailureCode.savedBluetoothPrinterUnavailable ||
          failure.code == ReportFlowFailureCode.bluetoothPermissionDenied;
      if (needsPrinterSettings && printerSettings != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(strings.failure(failure)),
              action: SnackBarAction(
                label: strings.settings,
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ThermalPrinterSettingsScreen(
                        controller: printerSettings,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.failure(failure))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final closeFab = Positioned(
      right: 12,
      top: 12,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          button: true,
          label: strings.close,
          child: ExcludeSemantics(
            child: IconButton(
              key: const ValueKey<String>('bridge-report-close'),
              tooltip: strings.close,
              onPressed: state.exportAction == null ? onClose : null,
              style: IconButton.styleFrom(
                backgroundColor: scheme.surface.withValues(alpha: 0.92),
                foregroundColor: scheme.onSurfaceVariant,
                side: BorderSide(color: scheme.outlineVariant),
                minimumSize: const Size.square(44),
              ),
              icon: const Icon(Icons.close, size: 22),
            ),
          ),
        ),
      ),
    );

    final failed = state.stage == ReportFlowStage.failed;
    final launch = state.presenterLaunch!;
    final template = state.committedTemplate ?? state.selectedTemplate!;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: BridgePresenterView(
              launch: launch,
              templateName: template.templateName,
              controller: controller,
              surfaceBinding: controller.presenterSurface,
            ),
          ),
          if (!failed && state.renderStatus == PresenterRenderStatus.loading)
            PositionedDirectional(
              start: 0,
              end: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: LinearProgressIndicator(
                  value: state.webViewLoadProgress < 1
                      ? state.webViewLoadProgress
                      : null,
                  minHeight: 3,
                ),
              ),
            ),
          if (failed)
            Positioned.fill(
              child: _RenderFailureOverlay(
                state: state,
                controller: controller,
                strings: strings,
              ),
            ),
          closeFab,
        ],
      ),
      bottomNavigationBar: failed
          ? null
          : PresenterActionDock(
              saveLabel: strings.savePdf,
              shareLabel: strings.share,
              printLabel: switch (state.printProgress?.phase) {
                ThermalPrintPhase.preparing => strings.preparingPrint,
                ThermalPrintPhase.connecting => strings.connectingPrinter,
                ThermalPrintPhase.printing => strings.sendingToPrinter,
                null => strings.print,
              },
              settingsLabel: strings.settings,
              showSavePdf: features.showSavePdf,
              showSharePdf: features.showSharePdf,
              showPrint: features.showPrint,
              showSettings: features.showSettings,
              outputEnabled:
                  state.exportReady ||
                  (features.allowLegacyPresenterFallback &&
                      state.stage == ReportFlowStage.previewing &&
                      state.presenterLaunch != null &&
                      state.renderStatus == PresenterRenderStatus.ready &&
                      state.webViewLoadProgress >= 1 &&
                      state.exportAction == null),
              busyAction: state.exportAction,
              onSave: () => unawaited(controller.savePdf()),
              onShare: () => unawaited(controller.sharePdf()),
              onPrint: () => unawaited(_print(context)),
              onSettings: controller.editSettings,
            ),
    );
  }
}

class _RenderFailureOverlay extends StatelessWidget {
  const _RenderFailureOverlay({
    required this.state,
    required this.controller,
    required this.strings,
  });

  final ReportFlowState state;
  final ReportFlowController controller;
  final ReportFlowStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failure =
        state.failure ??
        const ReportFlowFailure(code: ReportFlowFailureCode.unknown);
    final code = _failureCodeValue(failure);
    final message = _failureCombinedMessage(failure, strings);

    return ColoredBox(
      color: scheme.scrim.withValues(alpha: 0.58),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final centeredHeight = (constraints.maxHeight - 88)
                .clamp(0.0, double.infinity)
                .toDouble();
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 64, 0, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: centeredHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Card(
                      key: const ValueKey<String>('render-failure-card'),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Center(
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: scheme.errorContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: <Widget>[
                                    Icon(
                                      Icons.description_outlined,
                                      size: 36,
                                      color: scheme.onErrorContainer,
                                    ),
                                    Positioned(
                                      bottom: 8,
                                      child: Icon(
                                        Icons.warning_rounded,
                                        size: 22,
                                        color: scheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              strings.renderFailureTitle,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 18),
                            _FailureValueBlock(
                              label: strings.errorCode,
                              child: SelectableText(
                                code,
                                key: const ValueKey<String>(
                                  'render-failure-code',
                                ),
                                textDirection: TextDirection.ltr,
                                textAlign:
                                    Directionality.of(context) ==
                                        TextDirection.rtl
                                    ? TextAlign.right
                                    : TextAlign.left,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _FailureValueBlock(
                              label: strings.errorMessage,
                              child: _ExpandableFailureMessage(
                                message: message,
                                strings: strings,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Divider(color: scheme.outlineVariant),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stacked =
                                    constraints.maxWidth < 360 ||
                                    MediaQuery.textScalerOf(context).scale(1) >=
                                        1.3;
                                final update = FilledButton.icon(
                                  key: const ValueKey<String>(
                                    'render-failure-update-templates',
                                  ),
                                  onPressed: state.busy
                                      ? null
                                      : () {
                                          controller.openResourcePreparation(
                                            ResourcePreparationOrigin
                                                .previewRecovery,
                                          );
                                          unawaited(controller.syncTemplates());
                                        },
                                  icon: const Icon(Icons.refresh),
                                  label: Text(
                                    strings.updateTemplates,
                                    textAlign: TextAlign.center,
                                  ),
                                );
                                final change = OutlinedButton.icon(
                                  key: const ValueKey<String>(
                                    'render-failure-change-template',
                                  ),
                                  onPressed: state.busy
                                      ? null
                                      : () => controller.openTemplateSelection(
                                          origin: TemplateSelectionOrigin
                                              .previewRecovery,
                                        ),
                                  icon: const Icon(Icons.description_outlined),
                                  label: Text(
                                    strings.changeTemplate,
                                    textAlign: TextAlign.center,
                                  ),
                                );
                                if (stacked) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minHeight: 52,
                                        ),
                                        child: update,
                                      ),
                                      const SizedBox(height: 10),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minHeight: 52,
                                        ),
                                        child: change,
                                      ),
                                    ],
                                  );
                                }
                                return SizedBox(
                                  height: 52,
                                  child: Row(
                                    children: <Widget>[
                                      Expanded(child: update),
                                      const SizedBox(width: 8),
                                      Expanded(child: change),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FailurePage extends StatelessWidget {
  const _FailurePage({
    required this.strings,
    required this.failure,
    required this.onRetry,
    required this.onClose,
  });

  final ReportFlowStrings strings;
  final ReportFlowFailure? failure;
  final Future<void> Function() onRetry;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: strings.close,
        onPressed: onClose,
        icon: const Icon(Icons.close),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text(strings.failure(failure), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(strings.retry)),
            ],
          ),
        ),
      ),
    ),
  );
}
