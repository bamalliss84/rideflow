import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildRideFlowTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: RfColors.teal,
    primary: RfColors.ink,
    onPrimary: RfColors.onInk,
    secondary: RfColors.teal,
    onSecondary: Colors.white,
    error: RfColors.coral,
    surface: RfColors.surface,
    onSurface: RfColors.text,
  );
  final text = TextTheme(
    displaySmall: RfType.display,
    headlineMedium: RfType.h1,
    headlineSmall: RfType.h1,
    titleLarge: RfType.h2,
    titleMedium: RfType.h3,
    titleSmall: RfType.bodyStrong,
    bodyLarge: RfType.body.copyWith(fontSize: 16),
    bodyMedium: RfType.body,
    bodySmall: RfType.caption,
    labelLarge: RfType.cta.copyWith(fontSize: 16),
    labelMedium: RfType.label,
    labelSmall: RfType.caption,
  );
  final inputBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(RfRadius.md), borderSide: const BorderSide(color: RfColors.line));
  return ThemeData(
    useMaterial3: true,
    fontFamily: RfType.family,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: RfColors.canvas,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: RfColors.canvas,
      foregroundColor: RfColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: RfType.h2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RfColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: RfType.label,
      floatingLabelStyle: RfType.label.copyWith(color: RfColors.tealDeep, fontWeight: FontWeight.w700),
      hintStyle: RfType.body.copyWith(color: RfColors.textSubtle),
      helperStyle: RfType.caption,
      errorStyle: RfType.caption.copyWith(color: RfColors.coralDeep),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: RfColors.teal, width: 2)),
      errorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: RfColors.coral)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: RfColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(RfRadius.xl))),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: RfColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RfRadius.lg)),
      titleTextStyle: RfType.h2,
      contentTextStyle: RfType.body,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: RfColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: RfColors.tealSoft,
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => RfType.caption.copyWith(
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? RfColors.text : RfColors.textMuted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RfColors.ink,
      contentTextStyle: RfType.body.copyWith(color: RfColors.onInk),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RfRadius.md)),
    ),
    dividerTheme: const DividerThemeData(color: RfColors.line, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: RfColors.teal),
    switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.all(Colors.white)),
  );
}
