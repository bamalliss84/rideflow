import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart' show ActionRunner, AsyncBody, LoadingView, errorMessage;

/// Forward transitions in state-machine order; the backend's `allowed_actions` decides which are shown.
const _primary = ['confirm', 'en_route', 'arrive', 'start', 'complete'];
const _secondary = ['decline', 'no_show', 'driver_cancel'];

int stageIndex(String status) => switch (status) {
      'match_pending' || 'assigned' => 0,
      'en_route' => 1,
      'arrived' => 2,
      'in_progress' => 3,
      'completed' => 4,
      _ => -1,
    };

class TripScreen extends ConsumerStatefulWidget {
  const TripScreen({super.key, required this.rideId});
  final String rideId;
  @override
  ConsumerState<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends ConsumerState<TripScreen> {
  final _runner = ActionRunner();

  /// One idempotency key per (action, ride version): retrying the same tap replays, a new state gets a new key.
  final _keys = <String, String>{};
  String _keyFor(String action, int version) => _keys.putIfAbsent('$action@$version', newActionKey);

  Future<void> _transition(Ride ride, String action) async {
    final t = AppLocalizations.of(context);
    final api = ref.read(driverApiProvider);
    Json extra = {};
    if (action == 'driver_cancel' || action == 'decline') {
      final reason = await _askReason(action == 'decline' ? t.declineReason : t.cancelReason, required: action == 'driver_cancel');
      if (reason == null) return;
      extra = {'reason': reason};
    }
    if (action == 'arrive') {
      // Arrival is evidence: the backend checks the geofence and GPS accuracy from these values.
      final p = await ref.read(locationServiceProvider).current();
      if (p == null) {
        if (mounted) showToast(context, t.noLocationFix, error: true);
        return;
      }
      extra = {'lat': p.lat, 'lng': p.lng, 'accuracy_m': p.accuracy, 'device_ts': p.deviceTs.toUtc().toIso8601String()};
    }
    if (!mounted) return;
    await _runner.run(context, () async {
      try {
        await api.transition(ride, action, actionKey: _keyFor(action, ride.version), extra: extra);
      } on ApiException catch (e) {
        if (e.status == 409) _refresh(); // state moved on (other party / timer): show the current one
        rethrow;
      }
    }, onChanged: () => setState(() {}));
    _refresh();
  }

  void _refresh() {
    ref.invalidate(rideProvider(widget.rideId));
    ref.invalidate(ridesProvider);
    ref.invalidate(offersProvider);
    ref.read(pendingMatchProvider.notifier).reconcile();
  }

  Future<String?> _askReason(String label, {required bool required}) {
    final c = TextEditingController();
    final t = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(controller: c, maxLength: 300, autofocus: true, decoration: const InputDecoration()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          TextButton(
            onPressed: () {
              if (required && c.text.trim().isEmpty) return;
              Navigator.pop(ctx, c.text.trim());
            },
            child: Text(t.confirm),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final units = me?.minorUnits ?? 2;
    final value = ref.watch(rideProvider(widget.rideId));
    final current = value.valueOrNull;
    final primary = current == null || current.status == 'match_pending' ? const <String>[] : _primary.where(current.allowedActions.contains).toList();
    return Scaffold(
      // Pinned in the bottom bar slot (not the body) so toasts float above the primary action instead of over it.
      bottomNavigationBar: primary.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(RfSpace.md, RfSpace.sm, RfSpace.md, RfSpace.md),
              decoration: const BoxDecoration(color: RfColors.surface, border: Border(top: BorderSide(color: RfColors.line))),
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final a in primary)
                    Padding(
                      padding: const EdgeInsets.only(bottom: RfSpace.xs),
                      child: RfButton(
                        key: Key('action_$a'),
                        label: actionLabel(t, a),
                        kind: a == 'complete' || a == 'confirm' ? RfButtonKind.go : RfButtonKind.primary,
                        large: true,
                        loading: _runner.busy,
                        onPressed: () => _transition(current!, a),
                      ),
                    ),
                ]),
              ),
            ),
      appBar: AppBar(
        title: Text(t.rideTitle),
        leading: IconButton(icon: const BackButtonIcon(), onPressed: () => context.canPop() ? context.pop() : context.go('/')),
      ),
      body: AsyncBody<Ride>(
        value: value,
        onRetry: _refresh,
        data: (ride) {
          if (ride.status == 'match_pending' && ride.viewerRole == 'driver') {
            // Right after a confirm this snapshot is the stale pre-confirm one while the re-read is in flight:
            // redirecting on it bounced the driver back to the confirmation page. Wait for the fresh read.
            if (value.isLoading) return const LoadingView();
            // The dedicated confirmation flow owns this state.
            WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? context.go('/confirm/${ride.id}') : null);
          }
          final stage = stageIndex(ride.status);
          final secondary = _secondary.where(ride.allowedActions.contains).toList();
          return Column(children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView(padding: const EdgeInsets.fromLTRB(RfSpace.md, 0, RfSpace.md, RfSpace.lg), children: [
                  Row(children: [
                    Expanded(child: Text(rideStatusLabel(t, ride.status), key: const Key('rideStatus'), style: RfType.h1)),
                    StatusPill(rideStatusLabel(t, ride.status), tone: toneFor(ride.status)),
                  ]),
                  if (stage >= 0) ...[
                    const SizedBox(height: RfSpace.md),
                    StageStepper(labels: [t.stageConfirmed, t.stageToPickup, t.stageArrived, t.stageInTrip, t.stageDone], current: stage),
                  ],
                  const SizedBox(height: RfSpace.md),
                  RfCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      RouteStops(pickupLabel: t.pickup, pickup: ride.pickupLandmark, dropoffLabel: t.dropoff, dropoff: ride.dropoffLandmark),
                      if (ride.riderNote.isNotEmpty) ...[const SizedBox(height: RfSpace.sm), Banner2(text: ride.riderNote, tone: Tone.info, icon: Icons.sticky_note_2_outlined)],
                      const SizedBox(height: RfSpace.md),
                      const Divider(),
                      const SizedBox(height: RfSpace.md),
                      Row(children: [
                        Expanded(child: MetricTile(label: t.agreedFare, value: formatMoney(ride.agreedFareMinor ?? ride.myBid?.amountMinor, ride.currency, units), icon: Icons.payments_outlined)),
                        Expanded(child: MetricTile(label: t.distanceLabel, value: formatDistance(ride.distanceM), icon: Icons.straighten_rounded)),
                      ]),
                    ]),
                  ),
                  if (ride.rider != null) ...[
                    const SizedBox(height: RfSpace.sm),
                    RfCard(
                      child: Row(children: [
                        const CircleAvatar(radius: 22, backgroundColor: RfColors.surfaceSunken, child: Icon(Icons.person_rounded, color: RfColors.textMuted)),
                        const SizedBox(width: RfSpace.sm),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(ride.rider!.displayName.isEmpty ? t.rider : ride.rider!.displayName, style: RfType.bodyStrong),
                            if (ride.rider!.phone != null) Ltr(ride.rider!.phone!, style: RfType.body.copyWith(color: RfColors.tealDeep, fontWeight: FontWeight.w700)),
                            if (ride.rider!.ratingAvg != null) Text(t.riderRating(ride.rider!.ratingAvg!.toStringAsFixed(1)), style: RfType.caption),
                          ]),
                        ),
                      ]),
                    ),
                  ],
                  if (ride.status == 'arrived') ...[
                    const SizedBox(height: RfSpace.sm),
                    RfButton(
                      label: t.logContact,
                      icon: Icons.phone_forwarded_rounded,
                      kind: RfButtonKind.secondary,
                      onPressed: _runner.busy
                          ? null
                          : () => _runner.run(context, () => ref.read(driverApiProvider).contactAttempt(ride.id, 'call'), onChanged: () => setState(() {}), success: t.contactLogged),
                    ),
                  ],
                  if (ride.status == 'completed') ...[const SizedBox(height: RfSpace.sm), _CashCard(ride: ride, minorUnits: units, onChanged: _refresh)],
                  if (ride.cancellation != null) ...[
                    const SizedBox(height: RfSpace.sm),
                    Banner2(tone: Tone.danger, icon: Icons.cancel_outlined, text: '${ride.cancellation!['reason'] ?? ''}'.isEmpty ? rideStatusLabel(t, ride.status) : '${ride.cancellation!['reason']}'),
                  ],
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: RfSpace.lg),
                    if (secondary.contains('no_show')) Padding(padding: const EdgeInsets.only(bottom: RfSpace.xs), child: Text(t.noShowNote, style: RfType.caption)),
                    for (final a in secondary)
                      Padding(
                        padding: const EdgeInsets.only(bottom: RfSpace.xs),
                        child: RfButton(key: Key('action_$a'), label: actionLabel(t, a), kind: RfButtonKind.ghost, onPressed: _runner.busy ? null : () => _transition(ride, a)),
                      ),
                  ],
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Cash is paid to the driver directly; the driver confirms receipt (no platform custody, D002/D026).
class _CashCard extends ConsumerStatefulWidget {
  const _CashCard({required this.ride, required this.minorUnits, required this.onChanged});
  final Ride ride;
  final int minorUnits;
  final VoidCallback onChanged;
  @override
  ConsumerState<_CashCard> createState() => _CashCardState();
}

class _CashCardState extends ConsumerState<_CashCard> {
  final _runner = ActionRunner();
  final _cashKey = newActionKey();
  final _rateKey = newActionKey();
  int _stars = 0;
  bool _rated = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = widget.ride;
    final amount = formatMoney(r.cashAmountMinor ?? r.agreedFareMinor, r.currency, widget.minorUnits);
    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.cashTitle, style: RfType.h3),
        const SizedBox(height: RfSpace.sm),
        if (r.driverCashConfirmed)
          Row(children: [const Icon(Icons.check_circle_rounded, color: RfColors.teal), const SizedBox(width: 8), Expanded(child: Text(t.cashConfirmed, style: RfType.bodyStrong))])
        else ...[
          MoneyText(amount, style: RfType.display),
          const SizedBox(height: 4),
          Text(t.cashInstruction(amount), style: RfType.body),
          const SizedBox(height: RfSpace.sm),
          RfButton(
            key: const Key('confirmCash'),
            label: t.confirmCash,
            kind: RfButtonKind.go,
            loading: _runner.busy,
            onPressed: () async {
              await _runner.run(context, () => ref.read(driverApiProvider).confirmCash(r.id, actionKey: _cashKey), onChanged: () => setState(() {}));
              widget.onChanged();
            },
          ),
        ],
        const SizedBox(height: RfSpace.md),
        const Divider(),
        const SizedBox(height: RfSpace.sm),
        Text(t.rateRider, style: RfType.bodyStrong),
        if (_rated)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(t.rated, style: RfType.body.copyWith(color: RfColors.tealDeep)))
        else
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i',
                iconSize: 38,
                onPressed: _runner.busy
                    ? null
                    : () async {
                        setState(() => _stars = i);
                        final ok = await _runner.run(context, () => ref.read(driverApiProvider).rate(r.id, i, actionKey: _rateKey), onChanged: () => setState(() {}));
                        if (ok) setState(() => _rated = true);
                      },
                icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: RfColors.amber),
              ),
          ]),
      ]),
    );
  }
}

// Keeps a stable reference for tests that pump the trip screen directly.
String tripErrorText(BuildContext context, Object e) => errorMessage(context, e);
