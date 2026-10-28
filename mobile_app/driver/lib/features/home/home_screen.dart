import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../core/realtime/events_socket.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart' show ActionRunner, errorMessage, RefRetry, ErrorView;
import '../history/history_screens.dart' show summarize;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _poll;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Offers also arrive as realtime hints; this slow poll is only a safety net while online.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (ref.read(onlineControllerProvider).online) ref.invalidate(offersProvider);
    });
    _clock = Timer.periodic(const Duration(seconds: 5), (_) => mounted ? setState(() {}) : null); // freshness label
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(eligibilityProvider);
    ref.invalidate(offersProvider);
    ref.invalidate(ridesProvider);
    await ref.read(pendingMatchProvider.notifier).reconcile();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final eligibility = ref.watch(eligibilityProvider);
    final online = ref.watch(onlineControllerProvider);
    final active = ref.watch(activeRideProvider).valueOrNull;
    final pending = ref.watch(pendingMatchProvider).valueOrNull;
    ref.listen(eligibilityProvider, (_, next) {
      final e = next.valueOrNull;
      if (e != null) unawaited(ref.read(onlineControllerProvider.notifier).adopt(e.isOnline));
    });
    final firstName = (me?.fullName.trim().split(RegExp(r'\s+')).first ?? '');

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(RfSpace.md, RfSpace.sm, RfSpace.md, RfSpace.xl), children: [
            _Header(name: firstName),
            const SizedBox(height: RfSpace.md),
            _AvailabilityHero(online: online, eligibility: eligibility.valueOrNull),
            ..._problems(context, online, eligibility),
            if (pending != null) ...[const SizedBox(height: RfSpace.md), _PendingCard(ride: pending, minorUnits: me?.minorUnits ?? 2)],
            if (active != null && active.status != 'match_pending') ...[const SizedBox(height: RfSpace.md), _ActiveRideCard(ride: active)],
            const _TodaySummary(),
            SectionHeader(t.offersTitle, trailing: online.online ? const _LiveDot() : null),
            if (!online.online)
              EmptyState(icon: Icons.wifi_tethering_off_rounded, title: t.offersOfflineHint)
            else
              ref.watch(offersProvider).when(
                    skipLoadingOnRefresh: true,
                    loading: () => const SkeletonList(count: 2, height: 150),
                    error: (e, _) => ErrorView(error: e, onRetry: ref.retry(offersProvider)),
                    data: (offers) => offers.isEmpty
                        ? EmptyState(icon: Icons.radar_rounded, title: t.offersEmpty)
                        : Column(children: [for (final r in offers) OfferCard(ride: r, minorUnits: me?.minorUnits ?? 2)]),
                  ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _problems(BuildContext context, OnlineState online, AsyncValue<Eligibility> eligibility) {
    final t = AppLocalizations.of(context);
    final out = <Widget>[];
    void add(Widget w) => out
      ..add(const SizedBox(height: RfSpace.sm))
      ..add(w);
    final access = online.locationAccess;
    if (access == LocationAccess.deniedForever || access == LocationAccess.denied) {
      add(Banner2(
        tone: Tone.danger,
        icon: Icons.location_disabled_rounded,
        title: t.locationDeniedTitle,
        text: access == LocationAccess.deniedForever ? t.locationDeniedForever : t.locationNeeded,
        actionLabel: t.openSettings,
        onAction: () => ref.read(locationServiceProvider).openSettings(),
      ));
    } else if (access == LocationAccess.serviceDisabled) {
      add(Banner2(
        tone: Tone.warning,
        icon: Icons.gps_off_rounded,
        text: t.locationServiceOff,
        actionLabel: t.turnOnLocation,
        onAction: () => ref.read(locationServiceProvider).openLocationSettings(),
      ));
    } else if (online.online && eligibility.hasValue && !eligibility.value!.locationFresh) {
      final detail = online.locationError != null && online.locationError is! StateError ? errorMessage(context, online.locationError!) : t.noLocationFix;
      add(Banner2(
        key: const Key('locationNotUpdating'),
        tone: Tone.warning,
        icon: Icons.gps_not_fixed_rounded,
        text: detail,
        actionLabel: t.sendLocationNow,
        onAction: () async {
          try {
            await ref.read(onlineControllerProvider.notifier).sendNow();
          } catch (e) {
            if (context.mounted) showToast(context, errorMessage(context, e), error: true);
          }
        },
      ));
    } else if (online.noFix && !online.online) {
      add(Banner2(tone: Tone.warning, icon: Icons.gps_not_fixed_rounded, text: t.noLocationFix));
    }
    if (!online.online && eligibility.hasValue && !eligibility.value!.eligible) {
      final reasons = online.reasons.isNotEmpty ? online.reasons : eligibility.value!.reasons;
      add(_NotEligible(reasons: reasons));
    }
    if (eligibility.hasError) add(ErrorView(error: eligibility.error!, onRetry: ref.retry(eligibilityProvider)));
    return out;
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.name});
  final String name;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final unread = ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0;
    return Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: RfColors.ink, borderRadius: BorderRadius.circular(RfRadius.md)),
        child: const Icon(Icons.local_taxi_rounded, color: RfColors.teal),
      ),
      const SizedBox(width: RfSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isEmpty ? t.appTitle : t.greeting(name), style: RfType.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('RideFlow', style: RfType.caption),
        ]),
      ),
      Stack(clipBehavior: Clip.none, children: [
        IconButton.filledTonal(
          tooltip: t.notificationsTitle,
          style: IconButton.styleFrom(backgroundColor: RfColors.surface, minimumSize: const Size(48, 48)),
          icon: const Icon(Icons.notifications_none_rounded, color: RfColors.text),
          onPressed: () => context.push('/notifications'),
        ),
        if (unread > 0)
          PositionedDirectional(
            top: 4,
            end: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: RfColors.coral, borderRadius: BorderRadius.circular(RfRadius.pill)),
              child: Ltr(unread > 9 ? '9+' : '$unread', style: RfType.caption.copyWith(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    ]);
  }
}

/// One obvious action. "Online & receiving" only when the server confirms a fresh position.
class _AvailabilityHero extends ConsumerWidget {
  const _AvailabilityHero({required this.online, required this.eligibility});
  final OnlineState online;
  final Eligibility? eligibility;

  Future<void> _goOnline(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final location = ref.read(locationServiceProvider);
    // Explain before the system prompt (better grant rate, honest about what we do with location).
    if (await location.access(request: false) == LocationAccess.denied && context.mounted) {
      final allow = await RfSheet.show<bool>(
        context,
        RfSheet(
          title: t.locationWhyTitle,
          body: [
            const Center(child: Icon(Icons.my_location_rounded, size: 56, color: RfColors.teal)),
            const SizedBox(height: RfSpace.md),
            Text(t.locationWhyBody, style: RfType.body),
          ],
          action: Column(mainAxisSize: MainAxisSize.min, children: [
            RfButton(key: const Key('allowLocation'), label: t.allowLocation, kind: RfButtonKind.go, onPressed: () => Navigator.pop(context, true)),
            const SizedBox(height: RfSpace.xs),
            RfButton(label: t.notNow, kind: RfButtonKind.ghost, onPressed: () => Navigator.pop(context, false)),
          ]),
        ),
      );
      if (allow != true) return;
    }
    await ref.read(onlineControllerProvider.notifier).goOnline();
    if (!context.mounted) return;
    final after = ref.read(onlineControllerProvider);
    if (after.noFix) showToast(context, t.noLocationFix, error: true);
    if (after.error != null && after.error!.reasons.isEmpty) showToast(context, errorMessage(context, after.error!), error: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final ready = online.online && (eligibility?.locationFresh ?? false);
    final degraded = online.online && !ready;
    final socket = ref.watch(socketStateProvider).valueOrNull;
    final lastSent = online.lastSentAt ?? eligibility?.locationServerTs;
    final ago = lastSent == null ? null : DateTime.now().difference(lastSent).inSeconds.clamp(0, 99999);
    final (title, subtitle, accent) = ready
        ? (t.youAreOnline, t.onlineSubtitle, RfColors.teal)
        : degraded
            ? (t.youAreOnline, t.degradedSubtitle, RfColors.amber)
            : (t.youAreOffline, t.offlineSubtitle, RfColors.textSubtle);
    return Container(
      padding: const EdgeInsets.all(RfSpace.lg),
      decoration: BoxDecoration(color: RfColors.ink, borderRadius: BorderRadius.circular(RfRadius.xl), boxShadow: RfShadow.raised),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _Pulse(color: accent, active: ready),
          const SizedBox(width: RfSpace.sm),
          Expanded(child: Text(title, key: const Key('availabilityStatus'), style: RfType.h1.copyWith(color: RfColors.onInk))),
          if (online.online)
            StatusPill(
              socket == SocketState.connected ? t.realtimeLive : t.realtimeReconnecting,
              tone: socket == SocketState.connected ? Tone.success : Tone.warning,
              dot: true,
            ),
        ]),
        const SizedBox(height: 6),
        Text(subtitle, key: const Key('availabilitySubtitle'), style: RfType.body.copyWith(color: RfColors.onInkMuted)),
        if (online.online) ...[
          const SizedBox(height: RfSpace.xs),
          Row(children: [
            Icon(Icons.my_location_rounded, size: 16, color: ready ? RfColors.teal : RfColors.amber),
            const SizedBox(width: 6),
            Text(ago == null ? t.locationUnknown : t.locationFreshAgo('$ago'), style: RfType.caption.copyWith(color: RfColors.onInkMuted)),
          ]),
        ],
        const SizedBox(height: RfSpace.lg),
        RfButton(
          key: const Key('toggleOnline'),
          large: true,
          kind: online.online ? RfButtonKind.onInk : RfButtonKind.go,
          icon: online.online ? Icons.pause_circle_rounded : Icons.play_circle_fill_rounded,
          label: online.online ? t.goOffline : t.goOnline,
          loading: online.busy,
          onPressed: () async {
            if (online.online) {
              try {
                await ref.read(onlineControllerProvider.notifier).goOffline();
              } catch (e) {
                if (context.mounted) showToast(context, errorMessage(context, e), error: true);
              }
            } else {
              await _goOnline(context, ref);
            }
          },
        ),
      ]),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.active});
  final Color color;
  final bool active;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    widget.active ? _c.repeat() : _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 22,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Stack(alignment: Alignment.center, children: [
            if (widget.active)
              Container(
                width: 10 + 12 * _c.value,
                height: 10 + 12 * _c.value,
                decoration: BoxDecoration(color: widget.color.withOpacity(0.35 * (1 - _c.value)), shape: BoxShape.circle),
              ),
            Container(width: 12, height: 12, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
          ]),
        ),
      );
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();
  @override
  Widget build(BuildContext context) => const _Pulse(color: RfColors.teal, active: true);
}

class _NotEligible extends StatelessWidget {
  const _NotEligible({required this.reasons});
  final List<String> reasons;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final needsOnboarding = reasons.any((r) => r.startsWith('driver_') || r.startsWith('documents') || r == 'no_approved_vehicle');
    final needsSubscription = reasons.contains('subscription_inactive');
    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.notEligibleTitle, style: RfType.h3),
        const SizedBox(height: RfSpace.sm),
        for (final r in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: RfSpace.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.error_outline_rounded, size: 18, color: RfColors.amberDeep)),
              const SizedBox(width: RfSpace.xs),
              Expanded(child: Text(eligibilityReason(t, r), style: RfType.body)),
            ]),
          ),
        const SizedBox(height: RfSpace.xs),
        if (needsOnboarding) RfButton(label: t.completeOnboarding, kind: RfButtonKind.primary, icon: Icons.badge_rounded, onPressed: () => context.push('/onboarding')),
        if (needsSubscription) ...[
          const SizedBox(height: RfSpace.xs),
          RfButton(label: t.manageSubscription, kind: RfButtonKind.secondary, icon: Icons.workspace_premium_rounded, onPressed: () => context.push('/subscription')),
        ],
      ]),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.ride, required this.minorUnits});
  final Ride ride;
  final int minorUnits;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return RfCard(
      key: const Key('pendingConfirmationCard'),
      color: RfColors.amberSoft,
      border: RfColors.amber,
      onTap: () => context.push('/confirm/${ride.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.notifications_active_rounded, color: RfColors.amberDeep),
          const SizedBox(width: RfSpace.xs),
          Expanded(child: Text(t.pendingBannerTitle, style: RfType.h3)),
          MoneyText(formatMoney(ride.agreedFareMinor ?? ride.myBid?.amountMinor, ride.currency, minorUnits), style: RfType.bodyStrong),
        ]),
        const SizedBox(height: RfSpace.sm),
        RouteStops(pickupLabel: t.pickup, pickup: ride.pickupLandmark, dropoffLabel: t.dropoff, dropoff: ride.dropoffLandmark, dense: true),
        const SizedBox(height: RfSpace.sm),
        RfButton(label: t.pendingBannerAction, kind: RfButtonKind.primary, onPressed: () => context.push('/confirm/${ride.id}')),
      ]),
    );
  }
}

class _ActiveRideCard extends StatelessWidget {
  const _ActiveRideCard({required this.ride});
  final Ride ride;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return RfCard(
      color: RfColors.ink2,
      border: RfColors.ink2,
      onTap: () => context.push('/ride/${ride.id}'),
      child: Row(children: [
        const Icon(Icons.directions_car_filled_rounded, color: RfColors.teal),
        const SizedBox(width: RfSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.activeRide, style: RfType.bodyStrong.copyWith(color: RfColors.onInk)),
            Text(rideStatusLabel(t, ride.status), style: RfType.caption.copyWith(color: RfColors.onInkMuted)),
          ]),
        ),
        RfButton(label: t.openRide, kind: RfButtonKind.go, expand: false, onPressed: () => context.push('/ride/${ride.id}')),
      ]),
    );
  }
}

/// Real numbers only: today's completed rides and their agreed cash fares from the driver's own records.
class _TodaySummary extends ConsumerWidget {
  const _TodaySummary();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final rides = ref.watch(ridesProvider).valueOrNull;
    if (rides == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final s = summarize(rides, DateTime(now.year, now.month, now.day));
    return Padding(
      padding: const EdgeInsets.only(top: RfSpace.md),
      child: RfCard(
        onTap: () => context.go('/earnings'),
        child: Row(children: [
          Expanded(child: MetricTile(label: t.todayRides, value: '${s.count}', icon: Icons.route_rounded)),
          Container(width: 1, height: 40, color: RfColors.line),
          const SizedBox(width: RfSpace.md),
          Expanded(child: MetricTile(label: t.todayFares, value: formatMoney(s.total, me?.currency ?? '', me?.minorUnits ?? 2), icon: Icons.payments_rounded)),
        ]),
      ),
    );
  }
}

class OfferCard extends ConsumerWidget {
  const OfferCard({super.key, required this.ride, required this.minorUnits});
  final Ride ride;
  final int minorUnits;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final bid = ride.myBid;
    final hasOpenBid = bid != null && bid.status == 'open';
    final estimate = ride.estimateMin == null
        ? '—'
        : (ride.estimateMin == ride.estimateMax
            ? formatMoney(ride.estimateMin, ride.currency, minorUnits)
            : '${formatMoney(ride.estimateMin, '', minorUnits)}–${formatMoney(ride.estimateMax, ride.currency, minorUnits)}');
    return Padding(
      padding: const EdgeInsets.only(bottom: RfSpace.sm),
      child: RfCard(
        onTap: () => RfSheet.show<void>(context, BidSheet(ride: ride, minorUnits: minorUnits)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RouteStops(pickupLabel: t.pickup, pickup: ride.pickupLandmark, dropoffLabel: t.dropoff, dropoff: ride.dropoffLandmark, dense: true),
          const SizedBox(height: RfSpace.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: RfSpace.sm, vertical: RfSpace.sm),
            decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(RfRadius.md)),
            child: Row(children: [
              Expanded(child: _Fact(label: t.estimateLabel, value: estimate)),
              Expanded(child: _Fact(label: t.distanceLabel, value: formatDistance(ride.distanceM))),
            ]),
          ),
          const SizedBox(height: RfSpace.sm),
          if (hasOpenBid)
            Row(children: [
              Expanded(child: StatusPill(t.bid_active, tone: Tone.warning, icon: Icons.hourglass_top_rounded)),
              const SizedBox(width: RfSpace.xs),
              MoneyText(formatMoney(bid.amountMinor, ride.currency, minorUnits), style: RfType.h3),
            ])
          else if (bid != null)
            Align(alignment: AlignmentDirectional.centerStart, child: StatusPill(bidStatusLabel(t, bid.status), tone: toneFor(bid.status)))
          else if (ride.allowedActions.contains('bid'))
            RfButton(
              key: Key('makeOffer_${ride.id}'),
              label: t.makeOffer,
              icon: Icons.local_offer_rounded,
              kind: RfButtonKind.primary,
              onPressed: () => RfSheet.show<void>(context, BidSheet(ride: ride, minorUnits: minorUnits)),
            ),
        ]),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: RfType.caption),
        const SizedBox(height: 2),
        MoneyText(value, style: RfType.bodyStrong),
      ]);
}

/// Fare proposal. One idempotency key per sheet: a retried "send" can never create two bids.
class BidSheet extends ConsumerStatefulWidget {
  const BidSheet({super.key, required this.ride, required this.minorUnits});
  final Ride ride;
  final int minorUnits;
  @override
  ConsumerState<BidSheet> createState() => _BidSheetState();
}

class _BidSheetState extends ConsumerState<BidSheet> {
  late final TextEditingController _amount;
  final _runner = ActionRunner();
  final _key = newActionKey();
  int _eta = 5;
  String? _error;
  static const _etaChoices = [3, 5, 8, 10, 15];

  @override
  void initState() {
    super.initState();
    final suggestion = widget.ride.estimateMin;
    _amount = TextEditingController(text: suggestion == null ? '' : minorToInput(suggestion, widget.minorUnits));
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    final minor = inputToMinor(_amount.text, widget.minorUnits);
    if (minor == null) {
      setState(() => _error = t.errorValidation);
      return;
    }
    setState(() => _error = null);
    final ok = await _runner.run(
      context,
      () => ref.read(driverApiProvider).placeBid(widget.ride.id, amountMinor: minor, etaSeconds: _eta * 60, actionKey: _key),
      onChanged: () => setState(() {}),
      success: t.offerSent,
    );
    if (ok && mounted) {
      ref.invalidate(offersProvider);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = widget.ride;
    final bid = r.myBid;
    if (bid != null && bid.status == 'open') {
      return RfSheet(
        title: t.viewOffer,
        body: [
          MoneyText(formatMoney(bid.amountMinor, r.currency, widget.minorUnits), style: RfType.display),
          const SizedBox(height: RfSpace.xs),
          StatusPill(t.bid_active, tone: Tone.warning),
          const SizedBox(height: RfSpace.md),
          RouteStops(pickupLabel: t.pickup, pickup: r.pickupLandmark, dropoffLabel: t.dropoff, dropoff: r.dropoffLandmark, dense: true),
        ],
        action: RfButton(
          label: t.withdrawOffer,
          kind: RfButtonKind.secondary,
          loading: _runner.busy,
          onPressed: () async {
            final ok = await _runner.run(context, () => ref.read(driverApiProvider).withdrawBid(r.id, bid.id), onChanged: () => setState(() {}));
            if (ok && context.mounted) {
              ref.invalidate(offersProvider);
              Navigator.pop(context);
            }
          },
        ),
      );
    }
    return RfSheet(
      title: t.bidTitle,
      subtitle: t.bidSheetSubtitle,
      body: [
        RouteStops(pickupLabel: t.pickup, pickup: r.pickupLandmark, dropoffLabel: t.dropoff, dropoff: r.dropoffLandmark, dense: true),
        if (r.riderNote.isNotEmpty) ...[const SizedBox(height: RfSpace.sm), Text(r.riderNote, style: RfType.caption)],
        const SizedBox(height: RfSpace.lg),
        Text(t.fareLabel, style: RfType.label),
        const SizedBox(height: RfSpace.xs),
        TextField(
          key: const Key('bidAmount'),
          controller: _amount,
          autofocus: false,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: RfType.display.copyWith(fontSize: 32),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          decoration: InputDecoration(
            errorText: _error,
            suffixText: r.currency,
            suffixStyle: RfType.bodyStrong.copyWith(color: RfColors.textMuted),
            helperText: r.estimateMin == null
                ? null
                : '${t.estimateLabel}: ${formatMoney(r.estimateMin, '', widget.minorUnits)}–${formatMoney(r.estimateMax, r.currency, widget.minorUnits)}',
          ),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: RfSpace.lg),
        Text(t.etaLabel, style: RfType.label),
        const SizedBox(height: RfSpace.xs),
        Wrap(spacing: RfSpace.xs, runSpacing: RfSpace.xs, children: [
          for (final m in _etaChoices)
            ChoiceChip(
              key: Key('eta_$m'),
              label: Text(t.minutesShort('$m'), style: RfType.bodyStrong.copyWith(color: _eta == m ? Colors.white : RfColors.text)),
              selected: _eta == m,
              showCheckmark: false,
              selectedColor: RfColors.ink,
              backgroundColor: RfColors.surface,
              side: BorderSide(color: _eta == m ? RfColors.ink : RfColors.lineStrong),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              onSelected: (_) => setState(() => _eta = m),
            ),
        ]),
      ],
      action: RfButton(key: const Key('sendBid'), label: t.sendOffer, icon: Icons.send_rounded, kind: RfButtonKind.go, large: true, loading: _runner.busy, onPressed: _send),
    );
  }
}
