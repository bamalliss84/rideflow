import 'package:flutter/material.dart';

/// RideFlow design tokens (driver app). One source for colour, type, spacing, radius and elevation.
///
/// Identity: deep "night" ink for focus surfaces, a confident teal for go/online, warm amber for things
/// waiting on the driver, coral for danger. Light, airy surfaces for everything else.
abstract final class RfColors {
  // ink / surfaces
  static const ink = Color(0xFF0B1B2B); // primary text, night surfaces
  static const ink2 = Color(0xFF16293D);
  static const ink3 = Color(0xFF243B55);
  static const text = Color(0xFF0B1B2B);
  static const textMuted = Color(0xFF5B6B7F);
  static const textSubtle = Color(0xFF8A98AA);
  static const onInk = Color(0xFFFFFFFF);
  static const onInkMuted = Color(0xFFB4C2D3);
  static const canvas = Color(0xFFF3F5F8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSunken = Color(0xFFEDF1F5);
  static const line = Color(0xFFE2E7EE);
  static const lineStrong = Color(0xFFCBD3DE);

  // brand / states
  static const teal = Color(0xFF0FA394);
  static const tealDeep = Color(0xFF0B7C71);
  static const tealSoft = Color(0xFFE3F7F4);
  static const amber = Color(0xFFF2A93B);
  static const amberDeep = Color(0xFF9A5B0B);
  static const amberSoft = Color(0xFFFFF4E2);
  static const coral = Color(0xFFE5484D);
  static const coralDeep = Color(0xFFB4262B);
  static const coralSoft = Color(0xFFFDECEC);
  static const blue = Color(0xFF3B82F6);
  static const blueSoft = Color(0xFFE8F1FE);
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
