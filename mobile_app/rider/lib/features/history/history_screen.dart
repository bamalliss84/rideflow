import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/widgets.dart' show ActionRunner, AsyncBody;

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final units = ref.watch(authProvider).valueOrNull?.minorUnits ?? 2;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.rides, style: RfType.h1),
          const SizedBox(height: 12),
          SegmentedPills(labels: [t.past, t.current], selected: _tab, onSelected: (i) => setState(() => _tab = i)),
          const SizedBox(height: 12),
          Expanded(
            child: AsyncBody<List<Ride>>(
              value: ref.watch(ridesProvider),
              onRetry: () => ref.invalidate(ridesProvider),
              data: (rides) {
                final list = rides.where((r) => r.isActive == (_tab == 1)).toList();
                if (list.isEmpty) return Center(child: Text(t.noRides, key: const Key('noRides'), style: RfType.caption));
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(ridesProvider),
                  child: ListView(children: [
                    for (final r in list)
                      Padding(
                        padding: EdgeInsets.only(bottom: RfLayout.listGap),
                        child: _RideRow(ride: r, units: units),
                      ),
                  ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _RideRow extends StatelessWidget {
  const _RideRow({required this.ride, required this.units});
  final Ride ride;
  final int units;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final unrated = ride.status == 'completed' && ride.myRatingStars == null;
    final (status, color) = ride.isActive
        ? (t.status_active, RfColors.teal)
        : unrated
            ? (t.rateYourTrip, RfColors.gold)
            : switch (ride.status) {
                'completed' => (t.status_completed, RfColors.teal),
                'no_show' => (t.status_no_show, RfColors.coral),
                'disputed' => (t.status_disputed, RfColors.gold),
                _ => (t.status_cancelled, RfColors.coral),
              };
    final fare = ride.fareMinor;
    return RfCard(
      key: Key('ride_${ride.id}'),
      inList: true,
      padding: EdgeInsets.zero,
      onTap: () => context.push(ride.isActive || unrated ? '/ride/${ride.id}' : '/receipt/${ride.id}'),
      child: RfRow(
        title: ride.dropoffLandmark,
        sub: formatDateTime(ride.createdAt),
        maxLines: 1,
        trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          fare == null ? Text(t.noFare, style: RfType.caption) : MoneyText(formatMoney(fare, ride.currency, units), style: RfType.bodyStrong.copyWith(color: RfColors.gold)),
          Text(status, style: RfType.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key, required this.rideId});
  final String rideId;
  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  final _runner = ActionRunner();

  Future<void> _report() async {
    final t = AppLocalizations.of(context);
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.reportProblem),
        content: TextField(key: const Key('problemText'), controller: c, maxLines: 4, maxLength: 2000, decoration: InputDecoration(hintText: t.problemHint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          TextButton(key: const Key('sendProblem'), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(t.send)),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    await _runner.run(context, () => ref.read(riderApiProvider).report(widget.rideId, text), onChanged: () => setState(() {}), success: t.reportSent);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final units = ref.watch(authProvider).valueOrNull?.minorUnits ?? 2;
    return Scaffold(
      appBar: AppBar(title: Text(t.receipt), leading: IconButton(icon: const BackButtonIcon(), onPressed: () => context.canPop() ? context.pop() : context.go('/'))),
      body: AsyncBody<Ride>(
        value: ref.watch(rideProvider(widget.rideId)),
        onRetry: () => ref.invalidate(rideProvider(widget.rideId)),
        data: (r) {
          final fare = formatMoney(r.fareMinor, r.currency, units);
          final rows = <(String, String)>[
            (t.rideNumber, r.reference),
            (t.dateTime, formatDateTime(r.completedAt ?? r.createdAt)),
            (t.from, r.pickupLandmark),
            (t.to, r.dropoffLandmark),
            if (r.driver != null) (t.driver, '${r.driver!.name} · ${r.driver!.vehicle?.name ?? ''}'),
            (t.distance, formatDistance(r.distanceM)),
          ];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
            RfGroup(children: [
              for (final (label, value) in rows) label == t.distance ? RfRow(over: label, titleChild: Ltr(value, style: RfType.bodyStrong)) : RfRow(over: label, title: value),
              RfRow(over: t.fareCash, titleChild: MoneyText(fare, style: RfLayout.priceSmall)),
            ]),
            const SizedBox(height: 8),

            RfButton(
              key: const Key('copyReceipt'),
              label: t.shareReceipt,
              kind: RfButtonKind.secondary,
              onPressed: () async {
                final text = [for (final (l, v) in rows) '$l: $v', '${t.fareCash}: $fare'].join('\n');
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) showToast(context, t.receiptCopied);
              },
            ),
            const SizedBox(height: 8),
            if (r.pickup != null && r.dropoff != null)
              RfButton(key: const Key('repeatRide'), label: t.repeatRide, kind: RfButtonKind.ghost, onPressed: () => context.go('/request', extra: RideDraft(pickup: Place(r.pickupLandmark, r.pickup!), dropoff: Place(r.dropoffLandmark, r.dropoff!)))),
            RfButton(key: const Key('reportProblem'), label: t.reportProblem, kind: RfButtonKind.ghost, loading: _runner.busy, onPressed: _report),
          ]);
        },
      ),
    );
  }
}
