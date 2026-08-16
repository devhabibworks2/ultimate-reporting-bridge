import 'package:flutter/material.dart';
import 'package:reporting_bridge/reporting_bridge.dart';

import '../contracts/report_contract_values.dart';
import '../flow/report_template_metadata.dart';
import '../flow/urb_identifiers.dart';
import '../localization/report_flow_strings.dart';

enum TemplateThumbnailFamily {
  salesInvoice,
  salesReturn,
  customerOrder,
  receiptVoucher,
  paymentVoucher,
  quotation,
  accountStatement,
  report,
  fallback,
}

enum TemplateThumbnailLayoutShape { pages, thermal }

final class TemplateThumbnailSpec {
  const TemplateThumbnailSpec({
    required this.family,
    required this.layoutShape,
    required this.size,
    required this.orientation,
    required this.width,
    required this.height,
  });

  final TemplateThumbnailFamily family;
  final TemplateThumbnailLayoutShape layoutShape;
  final ReportPageSize size;
  final ReportOrientation orientation;
  final double width;
  final double height;

  bool get landscape => orientation == ReportOrientation.landscape;

  IconData get familyIcon => switch (family) {
    TemplateThumbnailFamily.salesInvoice => Icons.receipt_long,
    TemplateThumbnailFamily.salesReturn => Icons.assignment_return,
    TemplateThumbnailFamily.customerOrder => Icons.shopping_cart,
    TemplateThumbnailFamily.receiptVoucher => Icons.move_to_inbox,
    TemplateThumbnailFamily.paymentVoucher => Icons.outbox,
    TemplateThumbnailFamily.quotation => Icons.request_quote,
    TemplateThumbnailFamily.accountStatement => Icons.account_balance,
    TemplateThumbnailFamily.report => Icons.analytics,
    TemplateThumbnailFamily.fallback => Icons.description,
  };

  static TemplateThumbnailSpec resolve({
    required UrbReportTypeCode reportType,
    required ReportLayout layout,
    required ReportPageSize size,
    required ReportOrientation orientation,
    required double width,
    required double height,
  }) => TemplateThumbnailSpec(
    family: switch (reportType.value) {
      'sales_invoice' => TemplateThumbnailFamily.salesInvoice,
      'sales_return' => TemplateThumbnailFamily.salesReturn,
      'customer_order' => TemplateThumbnailFamily.customerOrder,
      'receipt_voucher' => TemplateThumbnailFamily.receiptVoucher,
      'payment_voucher' => TemplateThumbnailFamily.paymentVoucher,
      'quotation' => TemplateThumbnailFamily.quotation,
      'account_statement' => TemplateThumbnailFamily.accountStatement,
      'report' => TemplateThumbnailFamily.report,
      _ => TemplateThumbnailFamily.fallback,
    },
    layoutShape: switch (layout) {
      ReportLayout.pages => TemplateThumbnailLayoutShape.pages,
      ReportLayout.thermal => TemplateThumbnailLayoutShape.thermal,
    },
    size: size,
    orientation: orientation,
    width: width,
    height: height,
  );
}

class TemplatePresentationMetadata {
  const TemplatePresentationMetadata({
    required this.reportType,
    required this.layout,
    required this.size,
    required this.orientation,
    required this.unit,
    required this.width,
    required this.height,
    required this.description,
    required this.reportTypeLabel,
    required this.languageLabel,
    required this.layoutLabel,
    required this.sizeLabel,
    required this.thumbnailSizeLabel,
    required this.orientationLabel,
    required this.version,
    required this.versionLabel,
  });

  final UrbReportTypeCode reportType;
  final ReportLayout layout;
  final ReportPageSize size;
  final ReportOrientation orientation;
  final ReportMeasurementUnit unit;
  final double width;
  final double height;
  final String description;
  final String reportTypeLabel;
  final String languageLabel;
  final String layoutLabel;
  final String sizeLabel;
  final String thumbnailSizeLabel;
  final String orientationLabel;
  final String version;
  final String versionLabel;

  TemplateThumbnailSpec get thumbnailSpec => TemplateThumbnailSpec.resolve(
    reportType: reportType,
    layout: layout,
    size: size,
    orientation: orientation,
    width: width,
    height: height,
  );

  factory TemplatePresentationMetadata.fromReportMetadata(
    ReportTemplateMetadata metadata, {
    required CachedTemplate template,
    required ReportFlowStrings strings,
  }) {
    final description = strings.arabic
        ? 'قالب تقرير جاهز'
        : 'Ready report template';
    final resolvedVersion = template.version?.trim().isNotEmpty == true
        ? template.version!.trim()
        : '1';
    final sizeLabel = metadata.size == ReportPageSize.custom
        ? strings.customSizeValueLabel(
            width: metadata.width,
            height: metadata.height,
            unit: metadata.unit,
          )
        : strings.sizeValueLabel(metadata.size);
    final thumbnailSizeLabel = metadata.size == ReportPageSize.custom
        ? strings.customThumbnailSizeValueLabel(
            width: metadata.width,
            height: metadata.height,
            unit: metadata.unit,
          )
        : strings.thumbnailSizeValueLabel(metadata.size);
    return TemplatePresentationMetadata(
      reportType: metadata.reportType,
      layout: metadata.layout,
      size: metadata.size,
      orientation: metadata.orientation,
      unit: metadata.unit,
      width: metadata.width,
      height: metadata.height,
      description: description,
      reportTypeLabel: strings.reportTypeLabel(metadata.reportType),
      languageLabel: strings.languageValueLabel(metadata.language),
      layoutLabel: strings.layoutValueLabel(metadata.layout),
      sizeLabel: sizeLabel,
      thumbnailSizeLabel: thumbnailSizeLabel,
      orientationLabel: strings.orientationValueLabel(metadata.orientation),
      version: resolvedVersion,
      versionLabel: strings.arabic
          ? 'الإصدار $resolvedVersion'
          : 'Version $resolvedVersion',
    );
  }

  /// Parses canonical metadata and builds presentation fields.
  ///
  /// Returns null when the template document is not schema-canonical.
  static TemplatePresentationMetadata? tryFromTemplate(
    CachedTemplate template, {
    required ReportFlowStrings strings,
  }) {
    final metadata = ReportTemplateMetadata.tryFromTemplate(template);
    if (metadata == null) return null;
    return TemplatePresentationMetadata.fromReportMetadata(
      metadata,
      template: template,
      strings: strings,
    );
  }
}

class TemplatePreview extends StatelessWidget {
  const TemplatePreview({
    super.key,
    required this.metadata,
    this.width = 92,
    this.height = 116,
  });

  final TemplatePresentationMetadata metadata;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spec = metadata.thumbnailSpec;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.025),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 9, 9, 30),
              child: _TemplateLayoutSilhouette(spec: spec),
            ),
          ),
          Positioned(
            left: 7,
            right: 7,
            bottom: 7,
            child: _SizeBadge(
              label: metadata.thumbnailSizeLabel,
              size: metadata.size,
              maxWidth: (width - 14).clamp(30.0, 120.0).toDouble(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeBadge extends StatelessWidget {
  const _SizeBadge({
    required this.label,
    required this.size,
    required this.maxWidth,
  });

  final String label;
  final ReportPageSize size;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey<String>('template-size-${size.value}'),
      width: maxWidth,
      constraints: BoxConstraints(minWidth: 26, maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _TemplateLayoutSilhouette extends StatelessWidget {
  const _TemplateLayoutSilhouette({required this.spec});

  final TemplateThumbnailSpec spec;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = Size(
        constraints.maxWidth.isFinite ? constraints.maxWidth : 58,
        constraints.maxHeight.isFinite ? constraints.maxHeight : 64,
      );
      return switch (spec.layoutShape) {
        TemplateThumbnailLayoutShape.pages => _PagesSilhouette(
          spec: spec,
          available: available,
        ),
        TemplateThumbnailLayoutShape.thermal => _ThermalSilhouette(
          spec: spec,
          available: available,
        ),
      };
    },
  );
}

class _PagesSilhouette extends StatelessWidget {
  const _PagesSilhouette({required this.spec, required this.available});

  final TemplateThumbnailSpec spec;
  final Size available;

  Size _size() {
    final rawRatio = spec.width / spec.height;
    final normalizedRatio = !rawRatio.isFinite || rawRatio <= 0
        ? (spec.landscape ? 1.45 : 0.7)
        : spec.landscape
        ? (rawRatio >= 1 ? rawRatio : 1 / rawRatio)
        : (rawRatio <= 1 ? rawRatio : 1 / rawRatio);

    final maxWidth = available.width.clamp(1.0, double.infinity).toDouble();
    final maxHeight = available.height.clamp(1.0, double.infinity).toDouble();
    if (normalizedRatio >= 1) {
      var width = maxWidth;
      var height = width / normalizedRatio;
      if (height > maxHeight) {
        height = maxHeight;
        width = height * normalizedRatio;
      }
      return Size(width, height);
    }

    var height = maxHeight;
    var width = height * normalizedRatio;
    if (width > maxWidth) {
      width = maxWidth;
      height = width / normalizedRatio;
    }
    return Size(width, height);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = _size();
    final horizontalPadding = size.width < 38 ? 4.0 : 6.0;
    final verticalPadding = size.height < 44 ? 3.0 : 7.0;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        key: ValueKey<String>(
          'template-layout-pages-${spec.orientation.value}',
        ),
        width: size.width,
        height: size.height,
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          verticalPadding,
          horizontalPadding,
          verticalPadding - 1,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.07),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: _DocumentContentMarks(spec: spec, thermal: false),
      ),
    );
  }
}

class _ThermalSilhouette extends StatelessWidget {
  const _ThermalSilhouette({required this.spec, required this.available});

  final TemplateThumbnailSpec spec;
  final Size available;

  double _width() {
    final factor = switch (spec.size) {
      ReportPageSize.thermal58 => 0.34,
      ReportPageSize.thermal80 => 0.46,
      _ => 0.4,
    };
    final maxWidth = available.width.clamp(1.0, double.infinity).toDouble();
    final minWidth = maxWidth < 16 ? maxWidth : 16.0;
    return (maxWidth * factor).clamp(minWidth, maxWidth).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        key: const ValueKey<String>('template-layout-thermal'),
        width: _width(),
        height: available.height.clamp(1.0, double.infinity).toDouble(),
        padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.34)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.07),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: <Widget>[
            _ThermalPerforation(
              key: const ValueKey<String>('template-thermal-perforation-top'),
            ),
            const SizedBox(height: 3),
            Expanded(child: _DocumentContentMarks(spec: spec, thermal: true)),
            const SizedBox(height: 3),
            _ThermalPerforation(
              key: const ValueKey<String>(
                'template-thermal-perforation-bottom',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThermalPerforation extends StatelessWidget {
  const _ThermalPerforation({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List<Widget>.generate(
        5,
        (_) => Container(
          width: 2,
          height: 2,
          decoration: BoxDecoration(
            color: scheme.outlineVariant,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _DocumentContentMarks extends StatelessWidget {
  const _DocumentContentMarks({required this.spec, required this.thermal});

  final TemplateThumbnailSpec spec;
  final bool thermal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (thermal)
          Center(
            child: Icon(
              spec.familyIcon,
              key: ValueKey<String>('template-family-${spec.family.name}'),
              size: 10,
              color: scheme.primary.withValues(alpha: 0.9),
            ),
          )
        else
          Row(
            children: <Widget>[
              Icon(
                spec.familyIcon,
                key: ValueKey<String>('template-family-${spec.family.name}'),
                size: 13,
                color: scheme.primary.withValues(alpha: 0.86),
              ),
              const SizedBox(width: 3),
              Expanded(child: _line(scheme, 1)),
            ],
          ),
        SizedBox(height: thermal ? 3 : 4),
        Expanded(
          child: _FamilyBodyMotif(
            family: spec.family,
            compact: thermal || spec.landscape,
          ),
        ),
        SizedBox(height: thermal ? 2 : 3),
        Container(
          height: thermal ? 3 : 4,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _line(ColorScheme scheme, double widthFactor) => FractionallySizedBox(
    widthFactor: widthFactor,
    alignment: AlignmentDirectional.centerStart,
    child: Container(
      height: 2,
      decoration: BoxDecoration(
        color: scheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _FamilyBodyMotif extends StatelessWidget {
  const _FamilyBodyMotif({required this.family, required this.compact});

  final TemplateThumbnailFamily family;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (compact) {
      return Center(
        child: Icon(
          _compactIcon(family),
          size: 9,
          color: scheme.primary.withValues(alpha: 0.58),
        ),
      );
    }
    return switch (family) {
      TemplateThumbnailFamily.salesInvoice => _PurposeTableMotif(
        scheme: scheme,
        icon: Icons.attach_money,
      ),
      TemplateThumbnailFamily.salesReturn => _PurposeTableMotif(
        scheme: scheme,
        icon: Icons.assignment_return,
      ),
      TemplateThumbnailFamily.customerOrder => _PurposeTableMotif(
        scheme: scheme,
        icon: Icons.shopping_cart,
      ),
      TemplateThumbnailFamily.report => _MiniBars(scheme: scheme),
      TemplateThumbnailFamily.accountStatement => _MiniGrid(scheme: scheme),
      TemplateThumbnailFamily.receiptVoucher => _ArrowMotif(
        scheme: scheme,
        icon: Icons.south,
      ),
      TemplateThumbnailFamily.paymentVoucher => _ArrowMotif(
        scheme: scheme,
        icon: Icons.north,
      ),
      TemplateThumbnailFamily.quotation => _QuotationMotif(scheme: scheme),
      TemplateThumbnailFamily.fallback => _MiniTable(
        scheme: scheme,
        compact: false,
      ),
    };
  }

  IconData _compactIcon(TemplateThumbnailFamily family) => switch (family) {
    TemplateThumbnailFamily.salesInvoice => Icons.receipt_long,
    TemplateThumbnailFamily.salesReturn => Icons.assignment_return,
    TemplateThumbnailFamily.customerOrder => Icons.shopping_cart,
    TemplateThumbnailFamily.report => Icons.bar_chart,
    TemplateThumbnailFamily.accountStatement => Icons.table_rows_outlined,
    TemplateThumbnailFamily.receiptVoucher => Icons.south,
    TemplateThumbnailFamily.paymentVoucher => Icons.north,
    TemplateThumbnailFamily.quotation => Icons.sell_outlined,
    TemplateThumbnailFamily.fallback => Icons.description_outlined,
  };
}

class _PurposeTableMotif extends StatelessWidget {
  const _PurposeTableMotif({required this.scheme, required this.icon});

  final ColorScheme scheme;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Expanded(child: _MiniTable(scheme: scheme, compact: true)),
      const SizedBox(width: 3),
      Center(
        child: Icon(
          icon,
          size: 12,
          color: scheme.primary.withValues(alpha: 0.68),
        ),
      ),
    ],
  );
}

class _MiniTable extends StatelessWidget {
  const _MiniTable({required this.scheme, required this.compact});

  final ColorScheme scheme;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _mark(1),
      const SizedBox(height: 2),
      _mark(0.72),
      const Spacer(),
      Row(
        children: <Widget>[
          Expanded(child: _cell()),
          if (!compact) ...<Widget>[
            const SizedBox(width: 2),
            Expanded(child: _cell()),
          ],
        ],
      ),
    ],
  );

  Widget _mark(double widthFactor) => FractionallySizedBox(
    widthFactor: widthFactor,
    alignment: AlignmentDirectional.centerStart,
    child: Container(
      height: 2,
      decoration: BoxDecoration(
        color: scheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _cell() => Container(
    height: 7,
    decoration: BoxDecoration(
      border: Border.all(color: scheme.outlineVariant),
      borderRadius: BorderRadius.circular(1),
    ),
  );
}

class _MiniGrid extends StatelessWidget {
  const _MiniGrid({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Expanded(child: _row()),
      const SizedBox(height: 2),
      Expanded(child: _row()),
    ],
  );

  Widget _row() => Row(
    children: <Widget>[
      Expanded(child: _cell()),
      const SizedBox(width: 2),
      Expanded(child: _cell()),
    ],
  );

  Widget _cell() => DecoratedBox(
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      border: Border.all(color: scheme.outlineVariant),
      borderRadius: BorderRadius.circular(1),
    ),
  );
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      Expanded(child: _bar(0.45)),
      const SizedBox(width: 2),
      Expanded(child: _bar(0.7)),
      const SizedBox(width: 2),
      Expanded(child: _bar(1)),
    ],
  );

  Widget _bar(double factor) => FractionallySizedBox(
    heightFactor: factor,
    alignment: Alignment.bottomCenter,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(1),
      ),
    ),
  );
}

class _ArrowMotif extends StatelessWidget {
  const _ArrowMotif({required this.scheme, required this.icon});

  final ColorScheme scheme;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(icon, size: 16, color: scheme.primary.withValues(alpha: 0.65)),
  );
}

class _QuotationMotif extends StatelessWidget {
  const _QuotationMotif({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(
        Icons.sell_outlined,
        size: 13,
        color: scheme.primary.withValues(alpha: 0.65),
      ),
      const Spacer(),
      Container(
        height: 2,
        decoration: BoxDecoration(
          color: scheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ],
  );
}
