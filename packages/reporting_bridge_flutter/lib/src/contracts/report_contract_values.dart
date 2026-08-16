enum ReportLanguage {
  ar('ar', 1),
  en('en', 2);

  const ReportLanguage(this.value, this.legacyExternalValue);

  final String value;
  final int legacyExternalValue;

  static ReportLanguage parseCanonical(String raw) => switch (raw.trim()) {
    'ar' => ReportLanguage.ar,
    'en' => ReportLanguage.en,
    _ => throw ArgumentError.value(raw, 'language', 'Expected ar or en.'),
  };

  static ReportLanguage fromLegacyExternal(Object raw) => switch (raw
      .toString()
      .trim()) {
    '1' => ReportLanguage.ar,
    '2' => ReportLanguage.en,
    _ => throw ArgumentError.value(raw, 'language', 'Expected legacy 1 or 2.'),
  };
}

enum ReportLayout {
  pages('Pages'),
  thermal('Thermal');

  const ReportLayout(this.value);

  final String value;

  static ReportLayout parseCanonical(String raw) => switch (raw.trim()) {
    'Pages' => ReportLayout.pages,
    'Thermal' => ReportLayout.thermal,
    _ => throw ArgumentError.value(raw, 'layout', 'Expected Pages or Thermal.'),
  };
}

enum ReportPageSize {
  a4('A4'),
  a5('A5'),
  letter('Letter'),
  thermal80('80mm'),
  thermal58('58mm'),
  custom('custom');

  const ReportPageSize(this.value);

  final String value;

  static ReportPageSize parseCanonical(String raw) => switch (raw.trim()) {
    'A4' => ReportPageSize.a4,
    'A5' => ReportPageSize.a5,
    'Letter' => ReportPageSize.letter,
    '80mm' => ReportPageSize.thermal80,
    '58mm' => ReportPageSize.thermal58,
    'custom' => ReportPageSize.custom,
    _ => throw ArgumentError.value(raw, 'size', 'Unsupported page size.'),
  };
}

enum ReportOrientation {
  portrait('portrait'),
  landscape('landscape');

  const ReportOrientation(this.value);

  final String value;

  static ReportOrientation parseCanonical(String raw) => switch (raw.trim()) {
    'portrait' => ReportOrientation.portrait,
    'landscape' => ReportOrientation.landscape,
    _ => throw ArgumentError.value(
      raw,
      'orientation',
      'Expected portrait or landscape.',
    ),
  };
}

enum ReportMeasurementUnit {
  mm('mm');

  const ReportMeasurementUnit(this.value);

  final String value;

  static ReportMeasurementUnit parseCanonical(String raw) =>
      switch (raw.trim()) {
        'mm' => ReportMeasurementUnit.mm,
        _ => throw ArgumentError.value(raw, 'unit', 'Expected mm.'),
      };
}
