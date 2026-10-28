import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// Compatibility aliases onto the RideFlow design tokens (lib/design). New code uses RfColors directly.
abstract final class Brand {
  static const navy = RfColors.ink;
  static const navy700 = RfColors.ink3;
  static const teal = RfColors.teal;
  static const teal700 = RfColors.tealDeep;
  static const tealSoft = RfColors.tealSoft;
  static const amber = RfColors.amber;
  static const amberSoft = RfColors.amberSoft;
  static const coral = RfColors.coral;
  static const coralSoft = RfColors.coralSoft;
  static const surface = RfColors.canvas;
  static const line = RfColors.line;
  static const muted = RfColors.textMuted;
}

ThemeData buildTheme() => buildRideFlowTheme();
