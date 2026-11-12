import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Phone makers whose battery savers stop apps with the screen locked, grouped by whose settings look alike.
enum PhoneMaker { transsion, xiaomi, samsung, huawei, oppo, vivo, other }

PhoneMaker makerOf(String manufacturer) => switch (manufacturer.toLowerCase().trim()) {
      'infinix' || 'tecno' || 'itel' => PhoneMaker.transsion,
      'xiaomi' || 'redmi' || 'poco' => PhoneMaker.xiaomi,
      'samsung' => PhoneMaker.samsung,
      'huawei' || 'honor' => PhoneMaker.huawei,
      'oppo' || 'realme' || 'oneplus' => PhoneMaker.oppo,
      'vivo' || 'iqoo' => PhoneMaker.vivo,
      _ => PhoneMaker.other,
    };

class BatteryState {
  const BatteryState({this.supported = false, this.exempt = true, this.maker = PhoneMaker.other});

  /// False off Android, where there is nothing to set.
  final bool supported;

  /// The Android battery exemption. Some makers (Infinix, Tecno) still freeze the app without their own setting too.
  final bool exempt;
  final PhoneMaker maker;

  /// Worth showing the guide: the exemption is missing, or the maker has its own saver on top of it.
  bool get needsGuide => supported && (!exempt || maker != PhoneMaker.other);
}

/// The Android side lives in MainActivity ("rideflow/battery").
class BatteryGuard {
  const BatteryGuard();
  static const _channel = MethodChannel('rideflow/battery');

  Future<BatteryState> state() async {
    if (kIsWeb || !Platform.isAndroid) return const BatteryState();
    try {
      final m = (await _channel.invokeMapMethod<String, dynamic>('state')) ?? const {};
      return BatteryState(supported: true, exempt: m['exempt'] == true, maker: makerOf('${m['maker'] ?? ''}'));
    } catch (_) {
      return const BatteryState();
    }
  }

  /// Shows the system's "allow" dialog. The answer is read with [state] when the app comes back.
  Future<bool> requestExemption() async {
    try {
      return await _channel.invokeMethod<bool>('requestExemption') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The maker's auto-start screen, or the app's settings page. False when neither opened.
  Future<bool> openMakerSettings() async {
    try {
      return (await _channel.invokeMethod<String>('openMakerSettings')) != 'none';
    } catch (_) {
      return false;
    }
  }
}
