import 'package:flutter/material.dart';

import '../flow/report_flow_state.dart';

class PresenterActionDock extends StatelessWidget {
  const PresenterActionDock({
    super.key,
    required this.saveLabel,
    required this.shareLabel,
    required this.printLabel,
    required this.settingsLabel,
    required this.showSavePdf,
    required this.showSharePdf,
    required this.showPrint,
    required this.showSettings,
    required this.outputEnabled,
    required this.busyAction,
    required this.onSave,
    required this.onShare,
    required this.onPrint,
    required this.onSettings,
  });

  final String saveLabel;
  final String shareLabel;
  final String printLabel;
  final String settingsLabel;
  final bool showSavePdf;
  final bool showSharePdf;
  final bool showPrint;
  final bool showSettings;
  final bool outputEnabled;
  final ReportExportAction? busyAction;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onPrint;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final items = <_DockItem>[];
    final outputReady = outputEnabled && busyAction == null;
    final printIsPrimary = showPrint;

    if (showSavePdf) {
      items.add(
        _DockItem(
          child: _DockAction(
            key: const ValueKey<String>('bridge-save-pdf'),
            label: saveLabel,
            icon: Icons.download_outlined,
            emphasis: printIsPrimary
                ? _DockEmphasis.tonal
                : _DockEmphasis.primary,
            busy: busyAction == ReportExportAction.save,
            onPressed: outputReady ? onSave : null,
          ),
        ),
      );
    }
    if (showSharePdf) {
      items.add(
        _DockItem(
          child: _DockAction(
            key: const ValueKey<String>('bridge-share-pdf'),
            label: shareLabel,
            icon: Icons.share_outlined,
            emphasis: _DockEmphasis.tonal,
            busy: busyAction == ReportExportAction.share,
            onPressed: outputReady ? onShare : null,
          ),
        ),
      );
    }
    if (showPrint) {
      items.add(
        _DockItem(
          child: _DockAction(
            key: const ValueKey<String>('bridge-print-pdf'),
            label: printLabel,
            icon: Icons.print_outlined,
            emphasis: _DockEmphasis.primary,
            busy: busyAction == ReportExportAction.print,
            onPressed: outputReady ? onPrint : null,
          ),
        ),
      );
    }
    if (showSettings) {
      items.add(
        _DockItem(
          child: _DockAction(
            key: const ValueKey<String>('bridge-report-settings'),
            label: settingsLabel,
            icon: Icons.settings_outlined,
            emphasis: _DockEmphasis.secondary,
            busy: false,
            onPressed: busyAction == null ? onSettings : null,
          ),
        ),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.96),
      elevation: 16,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 380 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            if (compact) {
              return _CompactDockGrid(items: items);
            }
            return Row(
              children: <Widget>[
                for (var index = 0; index < items.length; index++) ...<Widget>[
                  if (index != 0) const SizedBox(width: 8),
                  Expanded(child: items[index].child),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompactDockGrid extends StatelessWidget {
  const _CompactDockGrid({required this.items});

  final List<_DockItem> items;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < items.length; index += 2) {
      if (index != 0) rows.add(const SizedBox(height: 8));
      final first = items[index].child;
      if (index + 1 < items.length) {
        rows.add(
          Row(
            children: <Widget>[
              Expanded(child: first),
              const SizedBox(width: 8),
              Expanded(child: items[index + 1].child),
            ],
          ),
        );
      } else {
        rows.add(SizedBox(width: double.infinity, child: first));
      }
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _DockItem {
  const _DockItem({required this.child});

  final Widget child;
}

enum _DockEmphasis { primary, tonal, secondary }

class _DockAction extends StatelessWidget {
  const _DockAction({
    super.key,
    required this.label,
    required this.icon,
    required this.emphasis,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final _DockEmphasis emphasis;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = switch (emphasis) {
      _DockEmphasis.primary => (
        background: scheme.primary,
        foreground: scheme.onPrimary,
        border: scheme.primary,
      ),
      _DockEmphasis.tonal => (
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        border: scheme.primary.withValues(alpha: 0.45),
      ),
      _DockEmphasis.secondary => (
        background: scheme.surfaceContainerLow,
        foreground: scheme.onSurface,
        border: scheme.outlineVariant,
      ),
    };
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: enabled
              ? colors.background
              : colors.background.withValues(alpha: 0.52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (busy)
                      SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.foreground,
                        ),
                      )
                    else
                      Icon(icon, size: 21, color: colors.foreground),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: enabled
                            ? colors.foreground
                            : colors.foreground.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
