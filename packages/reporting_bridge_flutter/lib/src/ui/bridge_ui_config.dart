import 'package:flutter/material.dart';

import 'bridge_ui_features.dart';

enum BridgeUiThemeMode { inheritHost, brand, custom }

class BridgeUiConfig {
  const BridgeUiConfig._({
    required this.mode,
    required this.features,
    this.seedColor,
    this.colorScheme,
    this.textTheme,
  });

  const BridgeUiConfig.inheritHost({
    BridgeUiFeatures features = const BridgeUiFeatures(),
  }) : this._(mode: BridgeUiThemeMode.inheritHost, features: features);

  const BridgeUiConfig.brand({
    required Color seedColor,
    BridgeUiFeatures features = const BridgeUiFeatures(),
  }) : this._(
         mode: BridgeUiThemeMode.brand,
         features: features,
         seedColor: seedColor,
       );

  const BridgeUiConfig.custom({
    required ColorScheme colorScheme,
    TextTheme? textTheme,
    BridgeUiFeatures features = const BridgeUiFeatures(),
  }) : this._(
         mode: BridgeUiThemeMode.custom,
         features: features,
         colorScheme: colorScheme,
         textTheme: textTheme,
       );

  final BridgeUiThemeMode mode;
  final BridgeUiFeatures features;
  final Color? seedColor;
  final ColorScheme? colorScheme;
  final TextTheme? textTheme;

  ThemeData resolve(ThemeData host) => switch (mode) {
    BridgeUiThemeMode.inheritHost => _buildBridgeTheme(
      host: host,
      colorScheme: host.colorScheme,
      textTheme: host.textTheme,
    ),
    BridgeUiThemeMode.brand => _buildBridgeTheme(
      host: host,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor!,
        brightness: host.brightness,
      ),
      textTheme: host.textTheme,
    ),
    BridgeUiThemeMode.custom => _buildBridgeTheme(
      host: host,
      colorScheme: colorScheme!,
      textTheme: textTheme ?? host.textTheme,
    ),
  };

  /// Rebuilds a Bridge-scoped theme from Host color/typography tokens only.
  ///
  /// Does not carry Host FAB/button/card/input geometry wholesale.
  static ThemeData _buildBridgeTheme({
    required ThemeData host,
    required ColorScheme colorScheme,
    TextTheme? textTheme,
  }) {
    final resolvedTextTheme = textTheme ?? host.textTheme;
    final base = ThemeData.from(
      colorScheme: colorScheme,
      textTheme: resolvedTextTheme,
      useMaterial3: true,
    );

    return base.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      visualDensity: VisualDensity.standard,
      platform: host.platform,
      pageTransitionsTheme: host.pageTransitionsTheme,
      // Bridge-owned component geometry — Host FAB/button/card/input themes
      // must not deform Bridge widgets (including the Close FAB exception).
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 4,
        disabledElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
        extendedIconLabelSpacing: 8,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
    );
  }
}
