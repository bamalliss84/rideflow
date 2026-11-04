import 'package:flutter/material.dart';

/// RideFlow design tokens (driver app). One source for colour, type, spacing, radius and elevation.
///
/// Identity (D035, "Souq" dark): deep green surfaces, gold for prices and the main action, a live green for
/// online and progress, a soft coral for danger. Token names predate the palette: `ink` is the ground colour.
abstract final class RfColors {
  // ink / surfaces
  static const ink = Color(0xFF0F2419);
  static const ink2 = Color(0xFF183426);
  static const ink3 = Color(0xFF27493A);
  static const text = Color(0xFFF3F6F3);
  static const textMuted = Color(0xFFB8CABE);
  static const textSubtle = Color(0xFF94AC9E);
  static const onInk = Color(0xFFF3F6F3);
  static const onInkMuted = Color(0xFFB8CABE);
  static const canvas = Color(0xFF0F2419);
  static const surface = Color(0xFF183426);
  static const surfaceSunken = Color(0xFF27493A);
  static const line = Color(0xFF27493A);
  static const lineStrong = Color(0xFF4A7361);
  static const gold = Color(0xFFF5B83D);
  static const onGold = Color(0xFF18261E);

  // brand / states
  static const teal = Color(0xFF5FD09A);
  static const tealDeep = Color(0xFF5FD09A);
  static const tealSoft = Color(0xFF1F4A38);
  static const amber = Color(0xFFF5B83D);
  static const amberDeep = Color(0xFFF5B83D);
  static const amberSoft = Color(0xFF3A3518);
  static const coral = Color(0xFFFFA99D);
  static const coralDeep = Color(0xFFFFA99D);
  static const coralSoft = Color(0xFF4A2B27);
  static const blue = Color(0xFF9DC2FF);
  static const blueSoft = Color(0xFF243B55);
}

abstract final class RfSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const page = EdgeInsets.symmetric(horizontal: 16);
}

abstract final class RfRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const pill = 999.0;
}

abstract final class RfShadow {
  static const card = [BoxShadow(color: Color(0x140B1B2B), blurRadius: 18, offset: Offset(0, 6))];
  static const raised = [BoxShadow(color: Color(0x260B1B2B), blurRadius: 28, offset: Offset(0, 12))];
  static const soft = [BoxShadow(color: Color(0x0D0B1B2B), blurRadius: 8, offset: Offset(0, 2))];
}

/// Tajawal type scale: readable at arm's length without crowding a phone screen.
abstract final class RfType {
  static const family = 'Tajawal';
  static const _base = TextStyle(fontFamily: family, color: RfColors.text, height: 1.35, letterSpacing: 0);

  static final display = _base.copyWith(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15);
  static final h1 = _base.copyWith(fontSize: 17, fontWeight: FontWeight.w800, height: 1.2);
  static final h2 = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25);
  static final h3 = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w700);
  static final body = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400);
  static final bodyStrong = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w700);
  static final label = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: RfColors.textMuted);
  static final caption = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: RfColors.textMuted);
  static final cta = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w700, height: 1.1);
  static final number = _base.copyWith(fontSize: 16, fontWeight: FontWeight.w800, height: 1.1);
}

// ---------------------------------------------------------------- layout models

/// How data is arranged on every screen while the owner compares the three models (D044).
/// a: separate cards. b: one page, sections and thin lines. c: borderless cards, shorter rows.
enum RfLayoutModel { a, b, c }

abstract final class RfLayout {
  static RfLayoutModel _model = RfLayoutModel.a;
  static RfLayoutModel get model => _model;
  static void use(RfLayoutModel model) => _model = model;
  static RfLayoutModel? decode(String? s) => switch (s) { 'a' => RfLayoutModel.a, 'b' => RfLayoutModel.b, 'c' => RfLayoutModel.c, _ => null };

  static bool get ruled => _model == RfLayoutModel.b;
  static bool get compact => _model == RfLayoutModel.c;

  static Color get page => ruled ? RfColors.surface : RfColors.canvas;
  static Color get softLine => RfColors.line.withOpacity(0.6);
  static double get radius => switch (_model) { RfLayoutModel.a => 14, RfLayoutModel.b => 0, RfLayoutModel.c => 10 };
  static double get groupGap => switch (_model) { RfLayoutModel.a => 8, RfLayoutModel.b => 2, RfLayoutModel.c => 6 };
  static double get listGap => switch (_model) { RfLayoutModel.a => 8, RfLayoutModel.b => 0, RfLayoutModel.c => 6 };
  static double get inset => switch (_model) { RfLayoutModel.a => 12, RfLayoutModel.b => 2, RfLayoutModel.c => 10 };
  static double get rowHeight => compact ? 42 : 50;
  static double get rowPad => compact ? 4 : 6;
  static double get iconBox => compact ? 28 : 32;
  static double get avatar => compact ? 16 : 19;
  static EdgeInsets get titlePad => compact ? const EdgeInsets.fromLTRB(2, 8, 2, 4) : const EdgeInsets.fromLTRB(2, 12, 2, 6);
  static EdgeInsets get box => EdgeInsets.symmetric(horizontal: inset, vertical: compact ? 8 : 10);

  static TextStyle get price => RfType.display.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: RfColors.gold);
  static TextStyle get priceSmall => price.copyWith(fontSize: 15);
  static TextStyle get priceBig => price.copyWith(fontSize: 26);
}
