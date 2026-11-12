import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/battery.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';

/// Read once by [maybeShowBatteryGuide], so the guide opens by itself only the first time the driver goes online.
const batteryGuideSeenKey = 'battery_guide_seen';

/// After going online: opens the guide once, on phones that need it. Later it is in the account tab and the home banner.
Future<void> maybeShowBatteryGuide(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(prefsProvider);
  try {
    if (await prefs.read(batteryGuideSeenKey) == '1') return;
    final state = await ref.read(batteryGuardProvider).state();
    if (!state.needsGuide) return;
    await prefs.write(batteryGuideSeenKey, '1');
  } catch (_) {
    return;
  }
  if (context.mounted) await context.push('/battery');
}

/// Steps that keep requests and location coming with the screen locked: the Android exemption, the maker's own
/// saver, and locking the app in recent apps.
class BatteryGuideScreen extends ConsumerStatefulWidget {
  const BatteryGuideScreen({super.key});
  @override
  ConsumerState<BatteryGuideScreen> createState() => _BatteryGuideScreenState();
}

class _BatteryGuideScreenState extends ConsumerState<BatteryGuideScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the system dialog or the maker's settings: read the exemption again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(batteryStateProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final state = ref.watch(batteryStateProvider).valueOrNull ?? const BatteryState();
    final guard = ref.read(batteryGuardProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.batteryGuide), leading: const BackButton()),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Padding(padding: const EdgeInsets.fromLTRB(2, 0, 2, 12), child: Text(t.batteryIntro, style: RfType.body)),
        RfGroup(children: [
          RfRow(
            key: const Key('batteryExemption'),
            leading: _Number(1, done: state.exempt),
            title: t.batteryStep1,
            sub: state.exempt ? t.batteryStep1Done : t.batteryStep1Text,
            trailing: state.exempt
                ? Icon(Icons.check_circle_rounded, color: RfColors.teal)
                : RfButton(key: const Key('batteryAllow'), label: t.batteryAllow, expand: false, onPressed: () => guard.requestExemption()),
          ),
        ]),
        RfGroup(children: [
          RfRow(leading: const _Number(2), title: t.batteryStep2, sub: makerSteps(t, state.maker)),
          Padding(
            padding: EdgeInsets.fromLTRB(RfLayout.inset, 0, RfLayout.inset, RfLayout.inset),
            child: RfButton(
              key: const Key('batteryOpenSettings'),
              label: t.batteryOpenSettings,
              kind: RfButtonKind.secondary,
              icon: Icons.settings_rounded,
              onPressed: () async {
                final opened = await guard.openMakerSettings();
                if (!opened && context.mounted) showToast(context, t.batterySettingsFailed, error: true);
              },
            ),
          ),
        ]),
        RfGroup(children: [
          RfRow(leading: const _Number(3), title: t.batteryStep3, sub: t.batteryStep3Text),
        ]),
      ]),
    );
  }
}

String makerSteps(AppLocalizations t, PhoneMaker maker) => switch (maker) {
      PhoneMaker.transsion => t.batteryMakerTranssion,
      PhoneMaker.xiaomi => t.batteryMakerXiaomi,
      PhoneMaker.samsung => t.batteryMakerSamsung,
      PhoneMaker.huawei => t.batteryMakerHuawei,
      PhoneMaker.oppo => t.batteryMakerOppo,
      PhoneMaker.vivo => t.batteryMakerVivo,
      PhoneMaker.other => t.batteryMakerOther,
    };

class _Number extends StatelessWidget {
  const _Number(this.n, {this.done = false});
  final int n;
  final bool done;
  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: done ? RfColors.teal : RfColors.surfaceSunken, shape: BoxShape.circle),
        child: Text('$n', style: RfType.bodyStrong.copyWith(color: done ? RfColors.canvas : RfColors.text)),
      );
}
