import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/widgets.dart' show AsyncBody, RefRetry;
import 'subscription_screen.dart' show daysPhrase;

/// Invite a driver (D052, screen 8): the driver's code, sharing on WhatsApp, what it has earned so far, and how it works.
class InviteScreen extends ConsumerWidget {
  const InviteScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.inviteTitle), leading: const BackButton()),
      body: AsyncBody<SubscriptionOverview>(
        value: ref.watch(subscriptionProvider),
        onRetry: ref.retry(subscriptionProvider),
        data: (s) {
          final r = s.referral;
          Widget stat(String value, String label, {Color? color}) => Expanded(
                child: RfCard(
                  padding: const EdgeInsets.symmetric(vertical: RfSpace.sm),
                  child: Column(children: [
                    Text(value, style: RfType.h1.copyWith(color: color)),
                    Text(label, style: RfType.caption, textAlign: TextAlign.center),
                  ]),
                ),
              );
          return ListView(padding: const EdgeInsets.fromLTRB(RfSpace.md, RfSpace.xs, RfSpace.md, RfSpace.lg), children: [
            Text(t.inviteIntro(daysPhrase(t, r.rewardDays)), style: RfType.body),
            const SizedBox(height: RfSpace.md),
            RfCard(
              key: const Key('inviteCode'),
              child: Row(children: [
                Expanded(child: Center(child: Ltr(r.code, style: RfType.display.copyWith(letterSpacing: 4)))),
                TextButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(t.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: r.code));
                    if (context.mounted) showToast(context, t.copied);
                  },
                ),
              ]),
            ),
            const SizedBox(height: RfSpace.sm),
            RfButton(
              key: const Key('shareWhatsApp'),
              label: t.shareWhatsApp,
              icon: Icons.share_rounded,
              kind: RfButtonKind.go,
              onPressed: r.code.isEmpty
                  ? null
                  : () async {
                      final ok = await ref.read(externalAppsProvider).shareWhatsApp(t.shareText(r.code));
                      if (!ok && context.mounted) showToast(context, t.shareFailed, error: true);
                    },
            ),
            const SizedBox(height: RfSpace.md),
            Row(children: [
              stat('${r.invited}', t.inviteInvited),
              const SizedBox(width: RfSpace.xs),
              stat('${r.rewarded}', t.inviteJoined),
              const SizedBox(width: RfSpace.xs),
              stat('${r.daysEarned}', t.inviteDaysEarned, color: RfColors.teal),
            ]),
            const SizedBox(height: RfSpace.md),
            RfGroup(children: [
              for (final (i, step) in [t.inviteStep1, t.inviteStep2, t.inviteStep3].indexed)
                RfRow(
                  leading: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: RfColors.surfaceSunken, shape: BoxShape.circle),
                    child: Text('${i + 1}', style: RfType.bodyStrong),
                  ),
                  title: step,
                  titleStyle: RfType.body,
                ),
            ]),
          ]);
        },
      ),
    );
  }
}
