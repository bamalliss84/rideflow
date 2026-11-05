import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/widgets.dart' show AsyncBody;

/// How long each wait lasts, in the order a ride goes (D049, model 1). The numbers are the operator's, read from the server.
class WaitTimesScreen extends ConsumerWidget {
  const WaitTimesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final value = ref.watch(waitTimesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.howItWorks), leading: const BackButton()),
      body: AsyncBody<Map<String, int>>(
        value: value,
        onRetry: () => ref.invalidate(waitTimesProvider),
        data: (w) {
          final steps = waitSteps(t, w);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Padding(padding: const EdgeInsets.fromLTRB(2, 4, 2, 10), child: Text(t.waitsNote, style: RfType.caption)),
            RfCard(
              child: Column(children: [
                for (var i = 0; i < steps.length; i++) _Step(key: Key('wait_$i'), title: steps[i].$1, value: steps[i].$2, text: steps[i].$3, last: i == steps.length - 1),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({super.key, required this.title, required this.value, required this.text, required this.last});
  final String title, value, text;
  final bool last;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 12,
            child: Column(children: [
              const SizedBox(height: 14),
              Container(width: 10, height: 10, decoration: BoxDecoration(color: RfColors.teal, shape: BoxShape.circle)),
              if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.only(top: 3), color: RfColors.line)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(title, style: RfType.bodyStrong)),
                  const SizedBox(width: 8),
                  Text(value, style: RfType.bodyStrong.copyWith(color: RfColors.gold)),
                ]),
                const SizedBox(height: 2),
                Text(text, style: RfType.caption),
              ]),
            ),
          ),
        ]),
      );
}

/// Seconds as people say them: "60 ثانية", "دقيقتان", "15 دقيقة".
String formatWait(AppLocalizations t, int seconds) {
  if (seconds < 120 && seconds % 60 != 0 || seconds <= 90) return t.waitSeconds('$seconds');
  final m = (seconds / 60).round();
  if (m == 1) return t.waitMinute1;
  if (m == 2) return t.waitMinute2;
  return m <= 10 ? t.waitMinutesFew('$m') : t.waitMinutesMany('$m');
}

String formatDays(AppLocalizations t, int days) => days == 1 ? t.waitDay1 : days == 2 ? t.waitDay2 : days <= 10 ? t.waitDaysFew('$days') : t.waitDaysMany('$days');

List<(String, String, String)> waitSteps(AppLocalizations t, Map<String, int> w) => [
      (t.waitSearch, formatWait(t, w['bidding_timeout_seconds']!), t.waitSearchText),
      (t.waitOffer, formatWait(t, w['bid_expiry_seconds']!), t.waitOfferText),
      (t.waitConfirm, formatWait(t, w['driver_confirm_timeout_seconds']!), t.waitConfirmText),
      (t.waitFreeCancel, formatWait(t, w['free_cancel_after_match_seconds']!), t.waitFreeCancelText),
      (t.waitDriverWaits, formatWait(t, w['noshow_wait_seconds']!), t.waitDriverWaitsText),
      (t.waitRating, formatDays(t, w['rating_window_days']!), t.waitRatingText),
    ];
