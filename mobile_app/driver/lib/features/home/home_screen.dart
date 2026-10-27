import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../data/models.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Offers also arrive as realtime hints; this slow poll is only a safety net while online.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (ref.read(onlineControllerProvider).online) ref.invalidate(offersProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(eligibilityProvider);
    ref.invalidate(offersProvider);
    ref.invalidate(ridesProvider);
    await ref.read(eligibilityProvider.future).catchError((_) => Eligibility({}));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final eligibility = ref.watch(eligibilityProvider);
    final online = ref.watch(onlineControllerProvider);
    final active = ref.watch(activeRideProvider).valueOrNull;
    ref.listen(eligibilityProvider, (_, next) {
      final e = next.valueOrNull;
      if (e != null) unawaited(ref.read(onlineControllerProvider.notifier).adopt(e.isOnline));
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(me?.tenantName ?? t.appTitle),
        actions: [
          IconButton(icon: const Icon(Icons.notifications_none_rounded), tooltip: t.notificationsTitle, onPressed: () => context.push('/notifications')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _AvailabilityCard(online: online, eligibility: eligibility.valueOrNull),
          if (online.online && eligibility.hasValue && !eligibility.value!.locationFresh) ...[
            const SizedBox(height: 12),
            _LocationNotUpdating(online: online),
          ],
          if (online.noFix && !online.online) ...[
            const SizedBox(height: 12),
            Card(color: Brand.amberSoft, child: Padding(padding: const EdgeInsets.all(14), child: Text(t.noLocationFix))),
          ],
          if (online.locationAccess != null && online.locationAccess != LocationAccess.granted) ...[
            const SizedBox(height: 12),
            _LocationProblem(access: online.locationAccess!),
          ],
          if (!online.online && eligibility.hasValue && !eligibility.value!.eligible) ...[
            const SizedBox(height: 12),
            _NotEligible(reasons: online.reasons.isNotEmpty ? online.reasons : eligibility.value!.reasons),
          ],
          if (eligibility.hasError) ...[const SizedBox(height: 12), ErrorView(error: eligibility.error!, onRetry: ref.retry(eligibilityProvider))],
          if (active != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Brand.navy,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: const Icon(Icons.directions_car_filled_rounded, color: Colors.white),
                title: Text(t.activeRide, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: Text(rideStatusLabel(t, active.status), style: const TextStyle(color: Colors.white70)),
                trailing: FilledButton.tonal(onPressed: () => context.push('/ride/${active.id}'), child: Text(t.openRide)),
                onTap: () => context.push('/ride/${active.id}'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(t.offersTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 8),
          if (!online.online)
            EmptyView(text: t.offersOfflineHint, icon: Icons.wifi_tethering_off_rounded)
          else
            AsyncBody<List<Ride>>(
              value: ref.watch(offersProvider),
              onRetry: ref.retry(offersProvider),
              data: (offers) => offers.isEmpty
                  ? EmptyView(text: t.offersEmpty, icon: Icons.radar_rounded)
                  : Column(children: [for (final r in offers) _OfferCard(ride: r, me: me)]),
            ),
        ]),
      ),
    );
  }
}

class _AvailabilityCard extends ConsumerWidget {
  const _AvailabilityCard({required this.online, required this.eligibility});
  final OnlineState online;
  final Eligibility? eligibility;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final controller = ref.read(onlineControllerProvider.notifier);
    // "Receiving requests" only when the server agrees: online AND a fresh position (eligibility.presence).
    final ready = online.online && (eligibility?.locationFresh ?? false);
    final degraded = online.online && !ready;
    return Card(
      color: ready ? Brand.teal700 : (degraded ? Brand.amberSoft : Colors.white),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(ready ? Icons.podcasts_rounded : (degraded ? Icons.location_disabled_rounded : Icons.power_settings_new_rounded),
                color: ready ? Colors.white : (degraded ? Brand.amber : Brand.muted)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(ready ? t.statusOnline : (degraded ? t.statusOnlineNoLocation : t.statusOffline),
                  key: const Key('availabilityStatus'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: ready ? Colors.white : Brand.navy)),
            ),
          ]),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('toggleOnline'),
            style: ready ? FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.teal700) : null,
            onPressed: online.busy
                ? null
                : () async {
                    if (online.online) {
                      try {
                        await controller.goOffline();
                      } catch (e) {
                        if (context.mounted) showMessage(context, errorMessage(context, e), error: true);
                      }
                    } else {
                      await controller.goOnline();
                      final after = ref.read(onlineControllerProvider);
                      final err = after.error;
                      if (after.noFix && context.mounted) showMessage(context, t.noLocationFix, error: true);
                      if (err != null && err.reasons.isEmpty && context.mounted) showMessage(context, errorMessage(context, err), error: true);
                    }
                  },
            child: online.busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(online.online ? t.goOffline : t.goOnline),
          ),
        ]),
      ),
    );
  }
}

class _NotEligible extends StatelessWidget {
  const _NotEligible({required this.reasons});
  final List<String> reasons;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final needsOnboarding = reasons.any((r) => r.startsWith('driver_') || r.startsWith('documents') || r == 'no_approved_vehicle');
    final needsSubscription = reasons.contains('subscription_inactive');
    return SectionCard(
      title: t.notEligibleTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 18, color: Brand.amber),
              const SizedBox(width: 8),
              Expanded(child: Text(eligibilityReason(t, r))),
            ]),
          ),
        const SizedBox(height: 8),
        if (needsOnboarding) OutlinedButton(onPressed: () => context.push('/onboarding'), child: Text(t.completeOnboarding)),
        if (needsSubscription) ...[
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => context.push('/subscription'), child: Text(t.manageSubscription)),
        ],
      ]),
    );
  }
}

class _LocationNotUpdating extends ConsumerWidget {
  const _LocationNotUpdating({required this.online});
  final OnlineState online;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final detail = online.locationError != null && online.locationError is! StateError ? errorMessage(context, online.locationError!) : t.noLocationFix;
    return Card(
      color: Brand.amberSoft,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.gps_off_rounded, color: Brand.amber),
            const SizedBox(width: 10),
            Expanded(child: Text(detail)),
          ]),
          if (online.lastSentAt != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(t.locationLastSent(formatDateTime(online.lastSentAt)), style: const TextStyle(color: Brand.muted, fontSize: 12))),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('sendLocationNow'),
            icon: const Icon(Icons.my_location_rounded),
            label: Text(t.sendLocationNow),
            onPressed: () async {
              try {
                await ref.read(onlineControllerProvider.notifier).sendNow();
              } catch (e) {
                if (context.mounted) showMessage(context, errorMessage(context, e), error: true);
              }
            },
          ),
        ]),
      ),
    );
  }
}

class _LocationProblem extends ConsumerWidget {
  const _LocationProblem({required this.access});
  final LocationAccess access;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = switch (access) {
      LocationAccess.deniedForever => t.locationDeniedForever,
      LocationAccess.serviceDisabled => t.locationServiceOff,
      _ => t.locationNeeded,
    };
    return Card(
      color: Brand.amberSoft,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.location_off_rounded, color: Brand.amber),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          if (access == LocationAccess.deniedForever)
            TextButton(onPressed: () => ref.read(locationServiceProvider).openSettings(), child: Text(t.openSettings)),
        ]),
      ),
    );
  }
}

class _OfferCard extends ConsumerWidget {
  const _OfferCard({required this.ride, required this.me});
  final Ride ride;
  final Me? me;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final units = me?.minorUnits ?? 2;
    final range = '${formatMoney(ride.estimateMin, ride.currency, units)} – ${formatMoney(ride.estimateMax, ride.currency, units)}';
    final bid = ride.myBid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => BidSheet(ride: ride, minorUnits: units)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Stop(icon: Icons.trip_origin, color: Brand.teal, label: t.pickup, text: ride.pickupLandmark),
              const SizedBox(height: 6),
              _Stop(icon: Icons.place_rounded, color: Brand.coral, label: t.dropoff, text: ride.dropoffLandmark),
              const Divider(height: 20),
              Row(children: [
                Expanded(child: Text(t.estimate(range), style: const TextStyle(fontWeight: FontWeight.w600))),
                Ltr(formatDistance(ride.distanceM), style: const TextStyle(color: Brand.muted)),
              ]),
              if (bid != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text(t.myOffer(formatMoney(bid.amountMinor, ride.currency, units)))),
                  StatusChip(bidStatusLabel(t, bid.status), tone: toneFor(bid.status)),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.icon, required this.color, required this.label, required this.text});
  final IconData icon;
  final Color color;
  final String label, text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(color: Brand.muted)),
        Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]);
}

/// Fare proposal for one ride. One idempotency key per sheet: a retried "send" can never create two bids.
class BidSheet extends ConsumerStatefulWidget {
  const BidSheet({super.key, required this.ride, required this.minorUnits});
  final Ride ride;
  final int minorUnits;
  @override
  ConsumerState<BidSheet> createState() => _BidSheetState();
}

class _BidSheetState extends ConsumerState<BidSheet> {
  late final TextEditingController _amount;
  final _eta = TextEditingController(text: '5');
  final _runner = ActionRunner();
  final _key = newActionKey();
  String? _error;

  @override
  void initState() {
    super.initState();
    final suggestion = widget.ride.estimateMin;
    _amount = TextEditingController(text: suggestion == null ? '' : minorToInput(suggestion, widget.minorUnits));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = widget.ride;
    final bid = r.myBid;
    final canBid = r.allowedActions.contains('bid');
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.bidTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(t.estimateNote, style: const TextStyle(color: Brand.muted, fontSize: 12)),
        if (r.riderNote.isNotEmpty) ...[const SizedBox(height: 8), Text(r.riderNote)],
        const SizedBox(height: 16),
        if (bid != null && bid.status == 'open') ...[
          Text(t.myOffer(formatMoney(bid.amountMinor, r.currency, widget.minorUnits))),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _runner.busy
                ? null
                : () async {
                    final ok = await _runner.run(context, () => ref.read(driverApiProvider).withdrawBid(r.id, bid.id), onChanged: () => setState(() {}));
                    if (ok && context.mounted) {
                      ref.invalidate(offersProvider);
                      Navigator.pop(context);
                    }
                  },
            child: Text(t.withdrawOffer),
          ),
        ] else if (canBid) ...[
          TextField(
            key: const Key('bidAmount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            decoration: InputDecoration(labelText: t.yourFare(r.currency), errorText: _error),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _eta,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: t.etaMinutes),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('sendBid'),
            onPressed: _runner.busy
                ? null
                : () async {
                    final minor = inputToMinor(_amount.text, widget.minorUnits);
                    final eta = int.tryParse(_eta.text) ?? 0;
                    if (minor == null || eta <= 0 || eta > 120) {
                      setState(() => _error = t.errorValidation);
                      return;
                    }
                    setState(() => _error = null);
                    final ok = await _runner.run(
                      context,
                      () => ref.read(driverApiProvider).placeBid(r.id, amountMinor: minor, etaSeconds: eta * 60, actionKey: _key),
                      onChanged: () => setState(() {}),
                      success: t.offerSent,
                    );
                    if (ok && context.mounted) {
                      ref.invalidate(offersProvider);
                      Navigator.pop(context);
                    }
                  },
            child: _runner.busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(t.sendOffer),
          ),
        ] else
          StatusChip(rideStatusLabel(t, r.status), tone: toneFor(r.status)),
      ]),
    );
  }
}
