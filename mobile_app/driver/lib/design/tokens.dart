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

/// Tajawal type scale. Sizes are deliberately not tiny: drivers read at arm's length, often in sunlight.
abstract final class RfType {
  static const family = 'Tajawal';
  static const _base = TextStyle(fontFamily: family, color: RfColors.text, height: 1.35, letterSpacing: 0);

  static final display = _base.copyWith(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15);
  static final h1 = _base.copyWith(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2);
  static final h2 = _base.copyWith(fontSize: 19, fontWeight: FontWeight.w700, height: 1.25);
  static final h3 = _base.copyWith(fontSize: 17, fontWeight: FontWeight.w700);
  static final body = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w400);
  static final bodyStrong = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w700);
  static final label = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: RfColors.textMuted);
  static final caption = _base.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: RfColors.textMuted);
  static final cta = _base.copyWith(fontSize: 17, fontWeight: FontWeight.w700, height: 1.1);
  static final number = _base.copyWith(fontSize: 22, fontWeight: FontWeight.w800, height: 1.1);
}
