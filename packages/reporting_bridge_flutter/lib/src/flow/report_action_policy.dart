enum ReportAction { printPdf, savePdf, sharePdf }

final class ReportActionPolicy {
  const ReportActionPolicy({
    this.canPrintPdf = true,
    this.canSavePdf = true,
    this.canSharePdf = true,
  });

  const ReportActionPolicy.readOnly()
    : canPrintPdf = false,
      canSavePdf = false,
      canSharePdf = false;

  final bool canPrintPdf;
  final bool canSavePdf;
  final bool canSharePdf;

  bool allows(ReportAction action) => switch (action) {
    ReportAction.printPdf => canPrintPdf,
    ReportAction.savePdf => canSavePdf,
    ReportAction.sharePdf => canSharePdf,
  };

  bool get allowsAnyOutput => canPrintPdf || canSavePdf || canSharePdf;

  ReportActionPolicy copyWith({
    bool? canPrintPdf,
    bool? canSavePdf,
    bool? canSharePdf,
  }) => ReportActionPolicy(
    canPrintPdf: canPrintPdf ?? this.canPrintPdf,
    canSavePdf: canSavePdf ?? this.canSavePdf,
    canSharePdf: canSharePdf ?? this.canSharePdf,
  );
}
