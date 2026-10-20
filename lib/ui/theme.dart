import 'package:flutter/material.dart';

/// App-wide dark sporty theme (green pitch accent).
class AppTheme {
  AppTheme._();

  static const Color surface = Color(0xFF10151B);
  static const Color surfaceCard = Color(0xFF171E27);
  static const Color accent = Color(0xFF22C55E);
  static const Color accentDim = Color(0xFF166534);
  static const Color danger = Color(0xFFEF4444);
  static const Color warn = Color(0xFFF59E0B);
  static const Color textDim = Color(0xFF94A3B8);

  static ThemeData build() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accentDim,
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 11, color: Colors.grey.shade300),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceCard,
        labelStyle: const TextStyle(fontSize: 11),
        padding: EdgeInsets.zero,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.grey.shade700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade800),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade800),
        ),
        prefixIconColor: textDim,
      ),
      listTileTheme: const ListTileThemeData(dense: true),
      dividerTheme: DividerThemeData(color: Colors.grey.shade900, thickness: 1),
    );
  }
}
