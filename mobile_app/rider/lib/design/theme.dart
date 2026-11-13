import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildRideFlowTheme({String family = RfFonts.preferred}) {
  final scheme = ColorScheme.fromSeed(
    brightness: RfColors.isNight ? Brightness.dark : Brightness.light,
    seedColor: RfColors.teal,
    primary: RfColors.teal,
    onPrimary: RfColors.canvas,
    secondary: RfColors.teal,
    onSecondary: RfColors.onGold,
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
    bodyLarge: RfType.body.copyWith(fontSize: 14),
    bodyMedium: RfType.body,
    bodySmall: RfType.caption,
    labelLarge: RfType.cta.copyWith(fontSize: 14),
    labelMedium: RfType.label,
    labelSmall: RfType.caption,
  );
  final inputBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: RfColors.line));
  TextStyle f(TextStyle style) => style.copyWith(fontFamily: family);
  return ThemeData(
    useMaterial3: true,
    fontFamily: family,
    colorScheme: scheme,
    textTheme: text.apply(fontFamily: family),
    scaffoldBackgroundColor: RfLayout.page,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: RfLayout.page,
      foregroundColor: RfColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: f(RfType.h2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RfColors.surfaceSunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: f(RfType.label),
      floatingLabelStyle: f(RfType.label).copyWith(color: RfColors.tealDeep, fontWeight: FontWeight.w700),
      hintStyle: f(RfType.body).copyWith(color: RfColors.textSubtle),
      helperStyle: f(RfType.caption),
      errorStyle: f(RfType.caption).copyWith(color: RfColors.coralDeep),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: RfColors.pri, width: 1.5)),
      errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: RfColors.coral)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: RfLayout.page,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(RfRadius.xl))),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: RfColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RfRadius.lg)),
      titleTextStyle: f(RfType.h2),
      contentTextStyle: f(RfType.body),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      margin: EdgeInsets.only(bottom: RfLayout.listGap),
      color: RfLayout.ruled ? Colors.transparent : RfColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RfLayout.ruled ? Border(bottom: BorderSide(color: RfColors.line)) : RoundedRectangleBorder(borderRadius: BorderRadius.circular(RfLayout.radius), side: RfLayout.compact ? BorderSide.none : BorderSide(color: RfColors.line)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: RfColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: RfColors.tealSoft,
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => f(RfType.caption).copyWith(
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? RfColors.text : RfColors.textMuted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RfColors.ink3,
      contentTextStyle: f(RfType.body).copyWith(color: RfColors.onInk),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RfRadius.md)),
    ),
    dividerTheme: DividerThemeData(color: RfColors.line, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: RfColors.teal),
    switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.all(RfColors.isNight ? RfColors.text : Colors.white)),
  );
}
