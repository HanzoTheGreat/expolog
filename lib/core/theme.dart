import 'package:flutter/material.dart';

class AppTheme {
  static const Color _bg = Color(0xFF111418);
  static const Color _surface = Color(0xFF1A1F26);
  static const Color _surfaceHigh = Color(0xFF232A33);
  static const Color _accent = Color(0xFF5B9BD5);
  static const Color _muted = Color(0xFF94A3B8);

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: _accent,
      onPrimary: const Color(0xFF0A1929),
      secondary: const Color(0xFF64B5A6),
      onSecondary: const Color(0xFF08201B),
      surface: _surface,
      onSurface: const Color(0xFFE8EDF2),
      surfaceContainerHighest: _surfaceHigh,
      outline: const Color(0xFF334155),
      error: const Color(0xFFE07A7A),
      onError: const Color(0xFF2B0B0B),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        foregroundColor: Color(0xFFE8EDF2),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF27303C)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surface,
        indicatorColor: _accent.withValues(alpha: 0.20),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? const Color(0xFFE8EDF2) : _muted,
          );
        }),
      ),
    );
  }
}
