import 'package:flutter/material.dart';

/// RideFlow design tokens (driver app). One source for colour, type, spacing, radius and elevation.
///
/// Night is the approved "Souq" palette (D035) and stays the default; day is the driver's choice (D049). Token names
/// predate the palettes: `ink` is the ground colour. Colours are read while building, so a widget using them can't be const.
enum RfAppearance { day, night }

class RfPalette {
  const RfPalette({required this.ink, required this.ink2, required this.ink3, required this.text, required this.textMuted, required this.textSubtle, required this.onInk, required this.onInkMuted, required this.mapGround, required this.canvas, required this.surface, required this.surfaceSunken, required this.line, required this.lineStrong, required this.gold, required this.onGold, required this.teal, required this.tealDeep, required this.tealSoft, required this.amber, required this.amberDeep, required this.amberSoft, required this.coral, required this.coralDeep, required this.coralSoft, required this.blue, required this.blueSoft});
  final Color ink, ink2, ink3, text, textMuted, textSubtle, onInk, onInkMuted, mapGround, canvas, surface, surfaceSunken, line, lineStrong, gold, onGold, teal, tealDeep, tealSoft, amber, amberDeep, amberSoft, coral, coralDeep, coralSoft, blue, blueSoft;

  static const night = RfPalette(
    ink: Color(0xFF0F2419),
    ink2: Color(0xFF183426),
    ink3: Color(0xFF27493A),
    text: Color(0xFFF3F6F3),
    textMuted: Color(0xFFB8CABE),
    textSubtle: Color(0xFF94AC9E),
    onInk: Color(0xFFF3F6F3),
    onInkMuted: Color(0xFFB8CABE),
    mapGround: Color(0xFF16291F),
    canvas: Color(0xFF0F2419),
    surface: Color(0xFF183426),
    surfaceSunken: Color(0xFF27493A),
    line: Color(0xFF27493A),
    lineStrong: Color(0xFF4A7361),
    gold: Color(0xFFF5B83D),
    onGold: Color(0xFF18261E),
    teal: Color(0xFF5FD09A),
    tealDeep: Color(0xFF5FD09A),
    tealSoft: Color(0xFF1F4A38),
    amber: Color(0xFFF5B83D),
    amberDeep: Color(0xFFF5B83D),
    amberSoft: Color(0xFF3A3518),
    coral: Color(0xFFFFA99D),
    coralDeep: Color(0xFFFFA99D),
    coralSoft: Color(0xFF4A2B27),
    blue: Color(0xFF9DC2FF),
    blueSoft: Color(0xFF243B55),
  );
  static const day = RfPalette(
    ink: Color(0xFFF2F5F2),
    ink2: Color(0xFFFFFFFF),
    ink3: Color(0xFFE7EDE8),
    text: Color(0xFF12211A),
    textMuted: Color(0xFF4F6157),
    textSubtle: Color(0xFF5C6E63),
    onInk: Color(0xFF12211A),
    onInkMuted: Color(0xFF4F6157),
    mapGround: Color(0xFFE8ECE6),
    canvas: Color(0xFFF2F5F2),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFE3EAE5),
    line: Color(0xFFDDE3DD),
    lineStrong: Color(0xFFBFCAC2),
    gold: Color(0xFF9A6700),
    onGold: Color(0xFFFFFFFF),
    teal: Color(0xFF0A7D46),
    tealDeep: Color(0xFF0A7D46),
    tealSoft: Color(0xFFE4F3EA),
    amber: Color(0xFF9A6700),
    amberDeep: Color(0xFF9A6700),
    amberSoft: Color(0xFFFBF0D6),
    coral: Color(0xFFB3261E),
    coralDeep: Color(0xFFB3261E),
    coralSoft: Color(0xFFFBE9E7),
    blue: Color(0xFF1B5FAA),
    blueSoft: Color(0xFFE3EDF9),
  );
}

abstract final class RfColors {
  static RfAppearance _appearance = RfAppearance.night;
  static RfPalette _p = RfPalette.night;

  static RfAppearance get appearance => _appearance;
  static bool get isNight => _appearance == RfAppearance.night;
  static void use(RfAppearance appearance) {
    _appearance = appearance;
    _p = appearance == RfAppearance.night ? RfPalette.night : RfPalette.day;
  }

  static Color get ink => _p.ink;
  static Color get ink2 => _p.ink2;
  static Color get ink3 => _p.ink3;
  static Color get text => _p.text;
  static Color get textMuted => _p.textMuted;
  static Color get textSubtle => _p.textSubtle;
  static Color get onInk => _p.onInk;
  static Color get onInkMuted => _p.onInkMuted;
  static Color get mapGround => _p.mapGround;
  static Color get canvas => _p.canvas;
  static Color get surface => _p.surface;
  static Color get surfaceSunken => _p.surfaceSunken;
  static Color get line => _p.line;
  static Color get lineStrong => _p.lineStrong;
  static Color get gold => _p.gold;
  static Color get onGold => _p.onGold;
  static Color get teal => _p.teal;
  static Color get tealDeep => _p.tealDeep;
  static Color get tealSoft => _p.tealSoft;
  static Color get amber => _p.amber;
  static Color get amberDeep => _p.amberDeep;
  static Color get amberSoft => _p.amberSoft;
  static Color get coral => _p.coral;
  static Color get coralDeep => _p.coralDeep;
  static Color get coralSoft => _p.coralSoft;
  static Color get blue => _p.blue;
  static Color get blueSoft => _p.blueSoft;
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
  static TextStyle get _base => TextStyle(fontFamily: family, color: RfColors.text, height: 1.35, letterSpacing: 0);

  static TextStyle get display => _base.copyWith(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15);
  static TextStyle get h1 => _base.copyWith(fontSize: 17, fontWeight: FontWeight.w800, height: 1.2);
  static TextStyle get h2 => _base.copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25);
  static TextStyle get h3 => _base.copyWith(fontSize: 14, fontWeight: FontWeight.w700);
  static TextStyle get body => _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400);
  static TextStyle get bodyStrong => _base.copyWith(fontSize: 13, fontWeight: FontWeight.w700);
  static TextStyle get label => _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: RfColors.textMuted);
  static TextStyle get caption => _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: RfColors.textMuted);
  static TextStyle get cta => _base.copyWith(fontSize: 14, fontWeight: FontWeight.w700, height: 1.1);
  static TextStyle get number => _base.copyWith(fontSize: 16, fontWeight: FontWeight.w800, height: 1.1);
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
