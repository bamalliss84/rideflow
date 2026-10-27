import 'package:flutter/material.dart';

/// RideFlow brand (same tokens as the admin portal): navy primary, teal accent, coral danger, amber pending.
class Brand {
  static const navy = Color(0xFF10243A);
  static const navy700 = Color(0xFF26405E);
  static const teal = Color(0xFF0D9488);
  static const teal700 = Color(0xFF0F766E);
  static const tealSoft = Color(0xFFECFBF8);
  static const amber = Color(0xFFE9A23B);
  static const amberSoft = Color(0xFFFEF8EE);
  static const coral = Color(0xFFC94343);
  static const coralSoft = Color(0xFFFDF3F3);
  static const surface = Color(0xFFF5F7FA);
  static const line = Color(0xFFE3E8EF);
  static const muted = Color(0xFF586A80);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.navy,
    primary: Brand.navy,
    secondary: Brand.teal,
    error: Brand.coral,
    surface: Colors.white,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.surface,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Brand.navy, elevation: 0, scrolledUnderElevation: 1, centerTitle: false),
    cardTheme: CardTheme(color: Colors.white, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Brand.line))),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: shape, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: shape, side: const BorderSide(color: Brand.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.teal, width: 2)),
    ),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: Brand.tealSoft, height: 68),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
