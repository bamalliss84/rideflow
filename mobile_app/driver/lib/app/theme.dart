import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// Compatibility aliases onto the RideFlow design tokens (lib/design). New code uses RfColors directly.
abstract final class Brand {
  static Color get navy => RfColors.ink;
  static Color get navy700 => RfColors.ink3;
  static Color get teal => RfColors.teal;
  static Color get teal700 => RfColors.tealDeep;
  static Color get tealSoft => RfColors.tealSoft;
  static Color get amber => RfColors.amber;
  static Color get amberSoft => RfColors.amberSoft;
  static Color get coral => RfColors.coral;
  static Color get coralSoft => RfColors.coralSoft;
  static Color get surface => RfColors.canvas;
  static Color get line => RfColors.line;
  static Color get muted => RfColors.textMuted;
}

ThemeData buildTheme() => buildRideFlowTheme();
