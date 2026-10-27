import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart';

/// Primary forward transitions, in state-machine order; the backend's `allowed_actions` decides which show.
const _primary = ['confirm', 'en_route', 'arrive', 'start', 'complete'];
const _secondary = ['decline', 'no_show', 'driver_cancel'];

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
        if (mounted) showMessage(context, t.locationNeeded, error: true);
        return;
      }
      extra = {'lat': p.lat, 'lng': p.lng, 'accuracy_m': p.accuracy, 'device_ts': p.deviceTs.toUtc().toIso8601String()};
    }
    if (!mounted) return;
    await _runner.run(context, () async {
      await api.transition(ride, action, actionKey: _keyFor(action, ride.version), extra: extra);
    }, onChanged: () => setState(() {}));
    _refresh();
  }

  void _refresh() {
    ref.invalidate(rideProvider(widget.rideId));
    ref.invalidate(ridesProvider);
    ref.invalidate(offersProvider);
  }

  Future<String?> _askReason(String label, {required bool required}) {
    final c = TextEditingController();
    final t = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: TextField(controller: c, maxLength: 300, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          FilledButton(
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
    return Scaffold(
      appBar: AppBar(title: Text(t.rideTitle)),
      body: AsyncBody<Ride>(
        value: value,
        onRetry: _refresh,
        data: (ride) => RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text(rideStatusLabel(t, ride.status), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
              StatusChip(rideStatusLabel(t, ride.status), tone: toneFor(ride.status)),
            ]),
            if (ride.status == 'match_pending' && ride.matchDeadline != null) ...[
              const SizedBox(height: 6),
              Text(t.confirmDeadline(formatDateTime(ride.matchDeadline)), style: const TextStyle(color: Brand.coral, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _row(Icons.trip_origin, Brand.teal, t.pickup, ride.pickupLandmark),
                const SizedBox(height: 8),
                _row(Icons.place_rounded, Brand.coral, t.dropoff, ride.dropoffLandmark),
                if (ride.riderNote.isNotEmpty) ...[const Divider(height: 20), Text(ride.riderNote)],
                const Divider(height: 20),
                Row(children: [
                  Expanded(child: Text(t.agreedFare, style: const TextStyle(color: Brand.muted))),
                  Ltr(formatMoney(ride.agreedFareMinor ?? ride.myBid?.amountMinor, ride.currency, units), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: Text(t.distance, style: const TextStyle(color: Brand.muted))),
                  Ltr(formatDistance(ride.distanceM)),
                ]),
              ]),
            ),
            if (ride.rider != null) ...[
              const SizedBox(height: 12),
              SectionCard(
                title: t.rider,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(ride.rider!.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (ride.rider!.phone != null) ...[const SizedBox(height: 4), Ltr(ride.rider!.phone!, style: const TextStyle(color: Brand.navy))],
                  if (ride.status == 'arrived') ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.phone_forwarded_rounded),
                      label: Text(t.logContact),
                      onPressed: _runner.busy
                          ? null
                          : () => _runner.run(context, () => ref.read(driverApiProvider).contactAttempt(ride.id, 'call'),
                              onChanged: () => setState(() {}), success: t.contactLogged),
                    ),
                  ],
                ]),
              ),
            ],
            if (ride.status == 'completed') ...[const SizedBox(height: 12), _CashCard(ride: ride, minorUnits: units, onChanged: _refresh)],
            const SizedBox(height: 16),
            for (final a in _primary.where(ride.allowedActions.contains))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton(
                  key: Key('action_$a'),
                  onPressed: _runner.busy ? null : () => _transition(ride, a),
                  child: _runner.busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(actionLabel(t, a)),
                ),
              ),
            for (final a in _secondary.where(ride.allowedActions.contains)) ...[
              if (a == 'no_show') Text(t.noShowNote, style: const TextStyle(color: Brand.muted, fontSize: 12)),
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 4),
                child: OutlinedButton(
                  key: Key('action_$a'),
                  style: OutlinedButton.styleFrom(foregroundColor: Brand.coral),
                  onPressed: _runner.busy ? null : () => _transition(ride, a),
                  child: Text(actionLabel(t, a)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _row(IconData icon, Color color, String label, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Brand.muted, fontSize: 12)),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ]);
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
    return SectionCard(
      title: t.cashTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (r.driverCashConfirmed)
          Row(children: [const Icon(Icons.check_circle, color: Brand.teal), const SizedBox(width: 8), Text(t.cashConfirmed)])
        else ...[
          Text(t.cashInstruction(amount)),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('confirmCash'),
            onPressed: _runner.busy
                ? null
                : () async {
                    await _runner.run(context, () => ref.read(driverApiProvider).confirmCash(r.id, actionKey: _cashKey), onChanged: () => setState(() {}));
                    widget.onChanged();
                  },
            child: Text(t.confirmCash),
          ),
        ],
        const Divider(height: 24),
        Text(t.rateRider, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (_rated)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(t.rated, style: const TextStyle(color: Brand.teal700)))
        else
          Row(children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i',
                onPressed: _runner.busy
                    ? null
                    : () async {
                        setState(() => _stars = i);
                        final ok = await _runner.run(context, () => ref.read(driverApiProvider).rate(r.id, i, actionKey: _rateKey),
                            onChanged: () => setState(() {}));
                        if (ok) setState(() => _rated = true);
                      },
                icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: Brand.amber, size: 32),
              ),
          ]),
      ]),
    );
  }
}
