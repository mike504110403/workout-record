import 'package:flutter/material.dart';

/// Central Material 3 theme definition for Work It Out.
///
/// Seed color is a deep blue, in line with common fitness-app palettes.
/// Both light and dark variants are generated from the same seed so the
/// app stays visually consistent regardless of the platform brightness.
class AppTheme {
  const AppTheme._();

  static const Color _seedColor = Color(0xFF1B3A6B);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      );
}
