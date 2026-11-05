import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../core/realtime/events_socket.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart' show errorMessage, RefRetry, ErrorView;
import '../history/history_screens.dart' show summarize;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _poll;
  Timer? _clock;
  String _tab = 'all';
  String? _openId;

  @override
  void initState() {
    super.initState();
    // Offers also arrive as realtime hints; this slow poll is only a safety net while online.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (ref.read(onlineControllerProvider).online) ref.invalidate(offersProvider);
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null); // freshness and offer countdowns
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
    ref.invalidate(hiddenOffersProvider);
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

    final units = me?.minorUnits ?? 2;
    final offers = ref.watch(offersProvider);
    final all = offers.valueOrNull ?? const <Ride>[];
    final mine = all.where(_hasLiveBid).toList();
    final fresh = all.where((r) => !_hasLiveBid(r)).toList();
    final showBar = online.online && mine.isNotEmpty && _tab != 'mine';

    return Scaffold(
      // In the bottom bar slot, so toasts float above it instead of covering it.
      bottomNavigationBar: showBar ? _OffersBar(offers: mine, minorUnits: units, onTap: () => setState(() => _tab = 'mine')) : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(RfSpace.md, RfSpace.sm, RfSpace.md, RfSpace.xl), children: [
            const _ProfileCard(),
            const SizedBox(height: RfSpace.sm),
            if (online.online)
              _StatusCard(online: online, eligibility: eligibility.valueOrNull, onRefresh: _reconnect)
            else
              _AvailabilityHero(online: online, eligibility: eligibility.valueOrNull),
            ..._problems(context, online, eligibility),
            if (pending != null) ...[const SizedBox(height: RfSpace.md), _PendingCard(ride: pending, minorUnits: units)],
            if (active != null && active.status != 'match_pending') ...[const SizedBox(height: RfSpace.md), _ActiveRideCard(ride: active)],
            if (!online.online) ...[
              const _TodaySummary(),
              SectionHeader(t.offersTitle),
              EmptyState(icon: Icons.wifi_tethering_off_rounded, title: t.offersOfflineHint),
            ] else ...[
              const SizedBox(height: RfSpace.sm),
              _RequestsHead(
                count: fresh.length,
                child: _Tabs(
                  selected: _tab,
                  all: fresh.length,
                  priced: fresh.where((r) => r.riderPriceMinor != null).length,
                  mine: mine.length,
                  onSelect: (tab) => setState(() => _tab = tab),
                ),
              ),
              const SizedBox(height: RfSpace.sm),
              offers.when(
                skipLoadingOnRefresh: true,
                loading: () => const SkeletonList(count: 2, height: 150),
                error: (e, _) => ErrorView(error: e, onRetry: ref.retry(offersProvider)),
                data: (_) => _tab == 'mine'
                    ? _MyOffers(offers: mine, minorUnits: units, maxOpen: eligibility.valueOrNull?.maxOpenBids)
                    : _RequestsList(
                        rides: _filtered(fresh),
                        minorUnits: units,
                        openId: _openId,
                        onToggle: (id) => setState(() => _openId = _openId == id ? null : id),
                        onShowMine: () => setState(() => _tab = 'mine'),
                      ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  /// The chosen filter. "Nearest" measures from this phone's last location; with none, the order stays as it came.
  List<Ride> _filtered(List<Ride> rides) {
    switch (_tab) {
      case 'price':
        return rides.where((r) => r.riderPriceMinor != null).toList();
      case 'high':
        int top(Ride r) => r.riderPriceMinor ?? r.estimateMax ?? 0;
        return [...rides]..sort((a, b) => top(b).compareTo(top(a)));
      case 'near':
        final here = ref.read(locationServiceProvider).last;
        if (here == null) return rides;
        double away(Ride r) => r.pickup == null ? double.infinity : distanceMeters(here.lat, here.lng, r.pickup!.lat, r.pickup!.lng);
        return [...rides]..sort((a, b) => away(a).compareTo(away(b)));
    }
    return rides;
  }

  /// The connection dropped: reconnect the event stream, send the location and read everything again.
  Future<void> _reconnect() async {
    ref.read(eventsSocketProvider).reconnectNow();
    try {
      await ref.read(onlineControllerProvider.notifier).sendNow();
    } catch (_) {}
    await _refresh();
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
    } else if (online.online && eligibility.hasValue && (!eligibility.value!.locationFresh || locationStopped(online, eligibility.value, DateTime.now()))) {
      final detail = online.locationError != null && online.locationError is! StateError ? errorMessage(context, online.locationError!) : t.locationStoppedDriver;
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

/// Photo, name, rating and car, with day or night and the notifications (D049, model 1).
class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final profile = ref.watch(profileProvider).valueOrNull;
    final trust = ref.watch(trustProvider).valueOrNull;
    final unread = ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0;
    final night = ref.watch(appearanceProvider) == RfAppearance.night;
    final path = profile?.photoUrl;
    final image = path == null ? null : ref.watch(photoBytesProvider(path)).valueOrNull;
    final name = (profile?.fullName.isNotEmpty == true ? profile!.fullName : me?.fullName) ?? '';
    final car = profile?.vehicles.where((v) => v.make.isNotEmpty).map((v) => '${v.make} ${v.model}'.trim()).firstOrNull;
    final rating = trust?.ratingAvg;
    return RfCard(
      key: const Key('profileCard'),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: RfColors.surfaceSunken,
          backgroundImage: image == null ? null : MemoryImage(image),
          child: image != null ? null : Text(name.isEmpty ? '' : name.characters.first, style: RfType.h2.copyWith(color: RfColors.teal)),
        ),
        const SizedBox(width: RfSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? t.appTitle : name, style: RfType.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(children: [
              if (rating != null) ...[Icon(Icons.star_rounded, size: 14, color: RfColors.gold), const SizedBox(width: 2), Ltr(rating.toStringAsFixed(1), style: RfType.caption)],
              if (rating != null && car != null) Text(' · ', style: RfType.caption),
              if (car != null) Flexible(child: Text(car, style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ]),
        ),
        _RoundTool(
          key: const Key('appearanceToggle'),
          icon: night ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          label: night ? t.dayMode : t.nightMode,
          onTap: () => ref.read(appearanceProvider.notifier).set(night ? RfAppearance.day : RfAppearance.night),
        ),
        const SizedBox(width: RfSpace.xs),
        _BellButton(unread: unread),
      ]),
    );
  }
}

class _RoundTool extends StatelessWidget {
  const _RoundTool({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        tooltip: label,
        style: IconButton.styleFrom(backgroundColor: RfColors.surfaceSunken, minimumSize: const Size(44, 44)),
        icon: Icon(icon, color: RfColors.text, size: 20),
        onPressed: onTap,
      );
}

/// The title and filters above the requests.
class _RequestsHead extends StatelessWidget {
  const _RequestsHead({required this.count, required this.child});
  final int count;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t.availableRequests, style: RfType.h2)),
          if (count > 0)
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: RfColors.gold, borderRadius: BorderRadius.circular(11)),
              child: Ltr('$count', style: RfType.caption.copyWith(color: RfColors.onGold, fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: RfSpace.xs),
        child,
      ]),
    );
  }
}

bool _hasLiveBid(Ride r) {
  final bid = r.myBid;
  return bid != null && bid.status == 'open' && (bid.expiresAt == null || bid.expiresAt!.isAfter(DateTime.now()));
}

/// Online, or the connection dropped with a way to bring it back; stopping is always one tap away.
/// "Ready" still needs a server-confirmed fresh position.
class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.online, required this.eligibility, required this.onRefresh});
  final OnlineState online;
  final Eligibility? eligibility;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final ready = (eligibility?.locationFresh ?? false) && !locationStopped(online, eligibility, DateTime.now());
    final socket = ref.watch(socketStateProvider).valueOrNull;
    final cut = socket == SocketState.disconnected;
    final lastSent = online.lastSentAt ?? eligibility?.locationServerTs;
    final ago = lastSent == null ? null : DateTime.now().difference(lastSent).inSeconds.clamp(0, 99999);
    return RfCard(
      key: const Key('statusCard'),
      child: Row(children: [
        _Pulse(color: cut ? RfColors.coral : (ready ? RfColors.teal : RfColors.amber), active: ready && !cut),
        const SizedBox(width: RfSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cut ? t.connectionCut : t.onlineShort, style: RfType.bodyStrong),
            Text(
              cut ? t.connectionCutHint : (ready && ago != null ? t.statusOnlineLine('$ago') : t.degradedSubtitle),
              key: Key(ready ? 'statusReady' : 'statusDegraded'),
              style: RfType.caption,
            ),
          ]),
        ),
        if (cut || !ready) ...[
          RfButton(key: const Key('reconnect'), label: t.refreshShort, icon: Icons.refresh_rounded, kind: RfButtonKind.primary, expand: false, onPressed: onRefresh),
          const SizedBox(width: RfSpace.xs),
        ],
        RfButton(
          key: const Key('toggleOnline'),
          label: t.stopShort,
          kind: RfButtonKind.secondary,
          expand: false,
          loading: online.busy,
          onPressed: () async {
            try {
              await ref.read(onlineControllerProvider.notifier).goOffline();
            } catch (e) {
              if (context.mounted) showToast(context, errorMessage(context, e), error: true);
            }
          },
        ),
      ]),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.unread});
  final int unread;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Stack(clipBehavior: Clip.none, children: [
      IconButton.filledTonal(
        tooltip: t.notificationsTitle,
        style: IconButton.styleFrom(backgroundColor: RfColors.surface, minimumSize: const Size(48, 48)),
        icon: Icon(Icons.notifications_none_rounded, color: RfColors.text),
        onPressed: () => context.push('/notifications'),
      ),
      if (unread > 0)
        PositionedDirectional(
          top: 4,
          end: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: RfColors.coral, borderRadius: BorderRadius.circular(RfRadius.pill)),
            child: Ltr(unread > 9 ? '9+' : '$unread', style: RfType.caption.copyWith(color: RfColors.onGold, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ),
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
            Center(child: Icon(Icons.my_location_rounded, size: 56, color: RfColors.teal)),
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
    final ready = online.online && (eligibility?.locationFresh ?? false) && !locationStopped(online, eligibility, DateTime.now());
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
      decoration: BoxDecoration(color: RfColors.surface, borderRadius: BorderRadius.circular(RfRadius.xl), boxShadow: RfShadow.raised),
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
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.error_outline_rounded, size: 18, color: RfColors.amberDeep)),
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
          Icon(Icons.notifications_active_rounded, color: RfColors.amberDeep),
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
      onTap: () => context.push('/ride/${ride.id}'),
      child: Row(children: [
        Icon(Icons.directions_car_filled_rounded, color: RfColors.teal),
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
      padding: const EdgeInsets.only(top: RfSpace.xs),
      child: RfGroup(onTap: () => context.go('/earnings'), children: [
        RfFacts([
          RfFact(t.todayRides, '${s.count}', ltr: true),
          RfFact(t.todayFares, formatMoney(s.total, me?.currency ?? '', me?.minorUnits ?? 2), ltr: true, color: RfColors.gold),
        ]),
      ]),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.all, required this.priced, required this.mine, required this.onSelect});
  final String selected;
  final int all, priced, mine;
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget chip(String id, String label) {
      final on = selected == id;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: Material(
          color: on ? RfColors.text : Colors.transparent,
          shape: StadiumBorder(side: BorderSide(color: on ? RfColors.text : RfColors.lineStrong)),
          child: InkWell(
            key: Key('tab_$id'),
            customBorder: const StadiumBorder(),
            onTap: () => onSelect(id),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(label, style: RfType.bodyStrong.copyWith(fontSize: 12, color: on ? RfColors.canvas : RfColors.text)),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('all', t.tabAll('$all')),
        chip('near', t.filterNearest),
        chip('high', t.filterHighest),
        chip('price', t.tabRiderPrice('$priced')),
        chip('mine', t.tabMyOffers('$mine')),
      ]),
    );
  }
}

class _RequestsList extends ConsumerWidget {
  const _RequestsList({required this.rides, required this.minorUnits, required this.openId, required this.onToggle, required this.onShowMine});
  final List<Ride> rides;
  final int minorUnits;
  final String? openId;
  final ValueChanged<String> onToggle;
  final VoidCallback onShowMine;

  Future<void> _hide(BuildContext context, WidgetRef ref, Ride ride) async {
    final t = AppLocalizations.of(context);
    final api = ref.read(driverApiProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.hideOffer(ride.id);
    } catch (e) {
      if (context.mounted) showToast(context, errorMessage(context, e), error: true);
      return;
    }
    ref.invalidate(offersProvider);
    ref.invalidate(hiddenOffersProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(t.requestHidden),
        action: SnackBarAction(
          key: const Key('undoHide'),
          label: t.undo,
          textColor: RfColors.gold,
          onPressed: () async {
            await api.unhideOffer(ride.id);
            ref.invalidate(offersProvider);
            ref.invalidate(hiddenOffersProvider);
          },
        ),
      ));
  }

  Future<void> _offer(BuildContext context, Ride ride) async {
    final result = await RfSheet.show<String>(context, BidSheet(ride: ride, minorUnits: minorUnits));
    if (result == 'mine') onShowMine();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    if (rides.isEmpty) {
      final hidden = ref.watch(hiddenOffersProvider).valueOrNull ?? 0;
      return EmptyState(
        icon: Icons.radar_rounded,
        title: t.noRequests,
        message: t.noRequestsHint,
        action: hidden == 0
            ? null
            : RfButton(
                key: const Key('showHidden'),
                label: t.showHidden('$hidden'),
                kind: RfButtonKind.secondary,
                expand: false,
                onPressed: () async {
                  await ref.read(driverApiProvider).unhideAllOffers();
                  ref.invalidate(offersProvider);
                  ref.invalidate(hiddenOffersProvider);
                },
              ),
      );
    }
    return Column(children: [
      for (final r in rides)
        _RequestCard(
          key: Key('offerCard_${r.id}'),
          ride: r,
          minorUnits: minorUnits,
          open: openId == r.id,
          onToggle: () => onToggle(r.id),
          onOffer: () => _offer(context, r),
          onHide: () => _hide(context, ref, r),
        ),
    ]);
  }
}

String _rangeText(Ride r, int units) => r.estimateMin == null
    ? '—'
    : (r.estimateMin == r.estimateMax
        ? formatMoney(r.estimateMin, '', units)
        : '${formatMoney(r.estimateMin, '', units)}–${formatMoney(r.estimateMax, '', units)}');

class _RequestCard extends StatelessWidget {
  const _RequestCard({super.key, required this.ride, required this.minorUnits, required this.open, required this.onToggle, required this.onOffer, required this.onHide});
  final Ride ride;
  final int minorUnits;
  final bool open;
  final VoidCallback onToggle, onOffer, onHide;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rider = ride.rider;
    final price = ride.riderPriceMinor;
    final range = _rangeText(ride, minorUnits);
    final name = rider == null || rider.displayName.isEmpty ? t.rider : rider.displayName;
    return Padding(
      padding: EdgeInsets.only(bottom: RfLayout.listGap),
      child: RfCard(
        padding: EdgeInsets.zero,
        inList: true,
        border: open ? RfColors.gold : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            key: Key('toggleCard_${ride.id}'),
            onTap: onToggle,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              RfRow(
                leading: CircleAvatar(radius: RfLayout.avatar, backgroundColor: RfColors.surfaceSunken, child: Text(name.characters.first, style: RfType.caption.copyWith(color: RfColors.text, fontWeight: FontWeight.w800))),
                title: name,
                maxLines: 1,
                trailing: RatingBadge(score: rider?.ratingAvg, count: rider?.ratingCount ?? 0, provisional: rider?.ratingProvisional ?? true, newLabel: t.newUser),
              ),
              Container(height: 1, color: RfLayout.softLine),
              RfStops(fromLabel: t.pickup, from: ride.pickupLandmark, toLabel: t.dropoff, to: ride.dropoffLandmark),
              Container(height: 1, color: RfLayout.softLine),
              Row(children: [
                Expanded(
                  child: RfFacts([
                    RfFact(t.distanceLabel, formatDistance(ride.distanceM), ltr: true),
                    RfFact(t.estimateShort(ride.currency), range, ltr: true),
                  ]),
                ),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.expand_more_rounded, color: RfColors.text),
                ),
                SizedBox(width: RfLayout.inset),
              ]),
              if (price != null) ...[
                Container(height: 1, color: RfLayout.softLine),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: RfLayout.inset, vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text(t.riderPriceLabel, style: RfType.caption)),
                    MoneyText(formatMoney(price, ride.currency, minorUnits), style: RfLayout.priceSmall),
                  ]),
                ),
              ],
            ]),
          ),
          if (open)
            Padding(
              padding: EdgeInsets.fromLTRB(RfLayout.inset, RfSpace.xs, RfLayout.inset, RfSpace.xxs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                RfButton(
                  key: Key('makeOffer_${ride.id}'),
                  label: price != null ? t.acceptPrice(formatMoney(price, ride.currency, minorUnits)) : t.makeOffer,
                  onPressed: onOffer,
                ),
                if (price != null) ...[
                  const SizedBox(height: RfSpace.xs),
                  RfButton(key: Key('otherPrice_${ride.id}'), label: t.offerOtherPrice, kind: RfButtonKind.secondary, onPressed: onOffer),
                ],
                TextButton(
                  key: Key('hide_${ride.id}'),
                  onPressed: onHide,
                  child: Text(t.hideRequest, style: RfType.body.copyWith(color: RfColors.textMuted, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

String _clock(Duration left) {
  final s = left.inSeconds.clamp(0, 99999);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _MyOffers extends ConsumerStatefulWidget {
  const _MyOffers({required this.offers, required this.minorUnits, required this.maxOpen});
  final List<Ride> offers;
  final int minorUnits;
  final int? maxOpen;
  @override
  ConsumerState<_MyOffers> createState() => _MyOffersState();
}

class _MyOffersState extends ConsumerState<_MyOffers> {
  String? _withdrawing;

  Future<void> _withdraw(Ride r) async {
    setState(() => _withdrawing = r.id);
    try {
      await ref.read(driverApiProvider).withdrawBid(r.id, r.myBid!.id);
      ref.invalidate(offersProvider);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(context, e), error: true);
    } finally {
      if (mounted) setState(() => _withdrawing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final max = widget.maxOpen;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RfGroup(children: [
        Padding(
          padding: RfLayout.box,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(t.openOffersTitle, style: RfType.bodyStrong)),
              Ltr(max == null ? '${widget.offers.length}' : t.offersOfMax('${widget.offers.length}', '$max'), style: RfType.bodyStrong),
            ]),
            if (max != null && max > 0) ...[
              const SizedBox(height: RfSpace.xs),
              LinearProgressIndicator(
                value: (widget.offers.length / max).clamp(0.0, 1.0),
                minHeight: 6,
                borderRadius: BorderRadius.circular(RfRadius.pill),
                backgroundColor: RfColors.surfaceSunken,
                color: RfColors.gold,
              ),
            ],
          ]),
        ),
      ]),

      if (widget.offers.isEmpty) EmptyState(icon: Icons.local_offer_outlined, title: t.noOpenOffers),
      for (final r in widget.offers) _myOffer(context, r),
    ]);
  }

  Widget _myOffer(BuildContext context, Ride r) {
    final t = AppLocalizations.of(context);
    final bid = r.myBid!;
    final left = bid.expiresAt?.difference(DateTime.now()) ?? Duration.zero;
    final total = bid.expiresAt != null && bid.createdAt != null ? bid.expiresAt!.difference(bid.createdAt!) : const Duration(seconds: 120);
    final urgent = left.inSeconds <= 30;
    return Padding(
      padding: EdgeInsets.only(bottom: RfLayout.listGap),
      child: RfCard(
        key: Key('myOffer_${r.id}'),
        inList: true,
        border: urgent ? RfColors.gold : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: _CountdownRing(
              key: Key('offerClock_${r.id}'),
              text: _clock(left),
              part: total.inSeconds <= 0 ? 0 : (left.inSeconds / total.inSeconds).clamp(0.0, 1.0),
              urgent: urgent,
            ),
          ),
          const SizedBox(height: RfSpace.xs),
          Center(child: MoneyText(formatMoney(bid.amountMinor, r.currency, widget.minorUnits), style: RfLayout.price)),
          const SizedBox(height: 2),
          Text('${r.pickupLandmark} ← ${r.dropoffLandmark}', style: RfType.bodyStrong, textAlign: TextAlign.center),
          Text(urgent ? t.endingSoon : t.waitingRider, style: RfType.caption, textAlign: TextAlign.center),
          const SizedBox(height: RfSpace.xs),
          Row(children: [
            Expanded(
              child: RfButton(
                key: Key('editOffer_${r.id}'),
                label: t.editOffer,
                kind: RfButtonKind.secondary,
                onPressed: () => RfSheet.show<String>(context, BidSheet(ride: r, minorUnits: widget.minorUnits)),
              ),
            ),
            const SizedBox(width: RfSpace.xs),
            Expanded(
              child: TextButton(
                key: Key('withdraw_${r.id}'),
                onPressed: _withdrawing == r.id ? null : () => _withdraw(r),
                child: Text(t.withdrawOffer, style: RfType.bodyStrong.copyWith(color: RfColors.coral)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// The time an open offer has left, inside a ring that empties with it.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({super.key, required this.text, required this.part, required this.urgent});
  final String text;
  final double part;
  final bool urgent;
  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 96,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(
            child: CircularProgressIndicator(value: part, strokeWidth: 6, strokeCap: StrokeCap.round, backgroundColor: RfColors.surfaceSunken, color: urgent ? RfColors.gold : RfColors.teal),
          ),
          Ltr(text, style: RfLayout.price.copyWith(color: urgent ? RfColors.gold : RfColors.text)),
        ]),
      );
}

/// Always-visible follow-up of open offers while the driver browses other requests.
class _OffersBar extends StatelessWidget {
  const _OffersBar({required this.offers, required this.minorUnits, required this.onTap});
  final List<Ride> offers;
  final int minorUnits;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final soonest = offers.reduce((a, b) => a.myBid!.expiresAt!.isBefore(b.myBid!.expiresAt!) ? a : b);
    final left = soonest.myBid!.expiresAt!.difference(DateTime.now());
    final urgent = left.inSeconds <= 30;
    final single = offers.length == 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(RfSpace.sm, 0, RfSpace.sm, RfSpace.xs),
        child: Material(
          color: RfColors.surfaceSunken,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RfRadius.md),
            side: urgent ? BorderSide(color: RfColors.gold, width: 2) : BorderSide.none,
          ),
          child: InkWell(
            key: const Key('offersBar'),
            borderRadius: BorderRadius.circular(RfRadius.md),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(RfSpace.sm),
              child: Row(children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: urgent ? RfColors.gold : RfColors.teal,
                  child: Ltr(_clock(left), style: RfType.caption.copyWith(color: RfColors.onGold, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: RfSpace.sm),
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      single ? t.yourOfferAmount(formatMoney(soonest.myBid!.amountMinor, soonest.currency, minorUnits)) : t.openOffersCount('${offers.length}'),
                      style: RfType.bodyStrong,
                    ),
                    Text(single ? t.waitingRider : t.soonestEnds('${left.inSeconds.clamp(0, 99999)}'), style: RfType.caption),
                  ]),
                ),
                Text(t.follow, style: RfType.bodyStrong.copyWith(color: RfColors.gold)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SendProblem { none, network, limit, rideLimit, gone, cantSend }

/// One sheet for accepting the rider's price or sending the driver's own (D035). Every amount and arrival time
/// has its own idempotency key: a resend after a lost response replays instead of creating a second offer.
class BidSheet extends ConsumerStatefulWidget {
  const BidSheet({super.key, required this.ride, required this.minorUnits});
  final Ride ride;
  final int minorUnits;
  @override
  ConsumerState<BidSheet> createState() => _BidSheetState();
}

class _BidSheetState extends ConsumerState<BidSheet> {
  late final TextEditingController _amount;
  final _keys = <String, String>{};
  bool _busy = false;
  int _eta = 5;
  String? _error;
  _SendProblem _problem = _SendProblem.none;
  static const _etaChoices = [3, 5, 8, 10, 15];

  @override
  void initState() {
    super.initState();
    final r = widget.ride;
    final bid = r.myBid;
    final start = bid != null && bid.status == 'open' ? bid.amountMinor : (r.riderPriceMinor ?? r.estimateMin);
    if (bid != null && bid.status == 'open' && bid.etaSeconds > 0) {
      final minutes = (bid.etaSeconds / 60).round();
      if (_etaChoices.contains(minutes)) _eta = minutes;
    }
    _amount = TextEditingController(text: start == null ? '' : minorToInput(start, widget.minorUnits));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _minor => inputToMinor(_amount.text, widget.minorUnits);

  void _step(int direction) {
    final step = widget.ride.bidStepMinor ?? 1;
    final next = (_minor ?? 0) + direction * step;
    if (next <= 0) return;
    setState(() => _amount.text = minorToInput(next, widget.minorUnits));
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    final minor = _minor;
    if (minor == null || minor <= 0) {
      setState(() => _error = t.errorValidation);
      return;
    }
    setState(() {
      _error = null;
      _problem = _SendProblem.none;
      _busy = true;
    });
    try {
      await ref.read(driverApiProvider).placeBid(
            widget.ride.id,
            amountMinor: minor,
            etaSeconds: _eta * 60,
            actionKey: _keys.putIfAbsent('$minor@$_eta', newActionKey),
          );
      ref.invalidate(offersProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      final problem = switch (e.code) {
        _ when e.isNetwork => _SendProblem.network,
        'open_bid_limit' => _SendProblem.limit,
        'bid_limit' => _SendProblem.rideLimit,
        'bidding_closed' || 'driver_busy' => _SendProblem.gone,
        _ when e.status == 404 => _SendProblem.gone,
        _ when e.status == 403 => _SendProblem.cantSend,
        _ => _SendProblem.none,
      };
      if (problem == _SendProblem.gone) ref.invalidate(offersProvider);
      setState(() => _problem = problem);
      if (problem == _SendProblem.none) setState(() => _error = errorMessage(context, e));
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshPresence() async {
    final controller = ref.read(onlineControllerProvider.notifier);
    setState(() => _busy = true);
    try {
      if (ref.read(onlineControllerProvider).online) {
        await controller.sendNow();
      } else {
        await controller.goOnline();
      }
      ref.invalidate(eligibilityProvider);
      if (mounted) await _send();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _hint(AppLocalizations t) {
    final r = widget.ride;
    final minor = _minor;
    if (minor == null) return '';
    final rider = r.riderPriceMinor;
    if (rider != null) {
      if (minor == rider) return t.matchesRider;
      final gap = formatMoney((minor - rider).abs(), r.currency, widget.minorUnits);
      return minor > rider ? t.aboveRider(gap) : t.belowRider(gap);
    }
    if (r.estimateMin == null) return '';
    if (minor < r.estimateMin!) return t.belowEstimate;
    return minor > r.estimateMax! ? t.aboveEstimate : t.withinEstimate;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = widget.ride;
    final rider = r.rider;
    final name = rider == null || rider.displayName.isEmpty ? t.rider : rider.displayName;
    final minor = _minor;
    final amount = minor == null ? '' : formatMoney(minor, r.currency, widget.minorUnits);
    final accepting = r.riderPriceMinor != null && minor == r.riderPriceMinor;

    if (_problem == _SendProblem.gone) {
      return RfSheet(
        title: t.requestGoneTitle,
        body: [Text(t.requestGoneBody, key: const Key('requestGone'), style: RfType.body)],
        action: RfButton(label: t.backToRequests, onPressed: () => Navigator.pop(context)),
      );
    }

    final (Widget? banner, Widget action) = switch (_problem) {
      _SendProblem.network => (
          Banner2(title: t.sendFailedTitle, text: t.sendFailedBody, tone: Tone.neutral, icon: Icons.wifi_off_rounded),
          RfButton(key: const Key('sendBid'), label: t.resend, large: true, loading: _busy, onPressed: _send),
        ),
      _SendProblem.limit => (
          Banner2(title: t.limitTitle, text: t.limitBody, icon: Icons.layers_rounded),
          RfButton(key: const Key('openMine'), label: t.openMyOffers, large: true, onPressed: () => Navigator.pop(context, 'mine')),
        ),
      _SendProblem.rideLimit => (
          Banner2(title: t.limitTitle, text: t.bidLimitBody, icon: Icons.layers_rounded),
          RfButton(label: t.backToRequests, large: true, onPressed: () => Navigator.pop(context)),
        ),
      _SendProblem.cantSend => (
          Banner2(title: t.cantSendTitle, text: t.cantSendBody, icon: Icons.gps_not_fixed_rounded),
          RfButton(key: const Key('refreshPresence'), label: t.refreshLocation, large: true, loading: _busy, onPressed: _refreshPresence),
        ),
      _ => (
          null,
          RfButton(
            key: const Key('sendBid'),
            label: accepting ? t.acceptPrice(amount) : t.sendOfferAmount(amount),
            large: true,
            loading: _busy,
            onPressed: _send,
          ),
        ),
    };

    return RfSheet(
      title: r.myBid?.status == 'open' ? t.editOffer : t.bidTitle,
      body: [
        RfGroup(key: const Key('offerRider'), title: t.sectionRider, children: [
          RfRow(
            leading: CircleAvatar(radius: RfLayout.avatar, backgroundColor: RfColors.surfaceSunken, child: Text(name.characters.first, style: RfType.bodyStrong)),
            title: name,
            trailing: rider == null || rider.ratingProvisional ? RatingBadge(score: rider?.ratingAvg, count: rider?.ratingCount ?? 0, provisional: true, newLabel: t.newUser, large: true) : null,
          ),
          if (rider != null && !rider.ratingProvisional)
            RfFacts([
              RfFact(t.ratingFact, null, child: RatingBadge(score: rider.ratingAvg, count: rider.ratingCount, provisional: false, newLabel: t.newUser)),
              RfFact(t.tripsFact, '${rider.completedRides}', ltr: true),
              RfFact(t.commitmentFact, rider.completionRate == null ? '—' : '${(rider.completionRate! * 100).round()}%', ltr: true),
            ]),
        ]),
        RfGroup(key: const Key('offerTrip'), title: t.sectionTrip, children: [
          RfStops(fromLabel: t.pickup, from: r.pickupLandmark, toLabel: t.dropoff, to: r.dropoffLandmark, showLabels: false),
          if (r.riderNote.isNotEmpty) RfRow(title: r.riderNote, titleStyle: RfType.caption),
          if (r.pickupNote.isNotEmpty) RfRow(title: t.pickupNoteLabel(r.pickupNote), titleStyle: RfType.caption),
          if (r.dropoffNote.isNotEmpty) RfRow(title: t.dropoffNoteLabel(r.dropoffNote), titleStyle: RfType.caption),
        ]),
        RfGroup(title: t.sectionPrices, children: [
          RfFacts([
            if (r.riderPriceMinor != null) RfFact(t.riderPriceLabel, formatMoney(r.riderPriceMinor, r.currency, widget.minorUnits), ltr: true, color: RfColors.gold),
            RfFact('${t.estimateLabel} · ${formatDistance(r.distanceM)}', '${_rangeText(r, widget.minorUnits)} ${r.currency}', ltr: true),
          ]),
        ]),
        if (banner != null) ...[const SizedBox(height: RfSpace.xs), banner, const SizedBox(height: RfSpace.xs)],
        RfGroup(title: t.sectionOffer, children: [
          Padding(
            padding: RfLayout.box,
            child: Row(children: [
              _StepButton(key: const Key('pricePlus'), icon: Icons.add_rounded, primary: true, onTap: () => _step(1)),
              Expanded(
                child: Column(children: [
                  TextField(
                    key: const Key('bidAmount'),
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: RfLayout.price,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                    decoration: const InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  Text(_hint(t), key: const Key('priceHint'), style: RfType.caption.copyWith(color: RfColors.text), textAlign: TextAlign.center),
                ]),
              ),
              _StepButton(key: const Key('priceMinus'), icon: Icons.remove_rounded, onTap: () => _step(-1)),
            ]),
          ),
        ]),
        if (_error != null) ...[Text(_error!, style: RfType.caption.copyWith(color: RfColors.coral)), const SizedBox(height: RfSpace.xs)],
        RfGroup(title: t.etaLabel, plain: true, children: [
          Row(children: [
            for (final m in _etaChoices)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Material(
                    color: _eta == m ? RfColors.text : RfColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(RfRadius.sm),
                    child: InkWell(
                      key: Key('eta_$m'),
                      borderRadius: BorderRadius.circular(RfRadius.sm),
                      onTap: () => setState(() => _eta = m),
                      child: SizedBox(
                        height: 44,
                        child: Center(child: Text(t.minutesShort('$m'), style: RfType.bodyStrong.copyWith(color: _eta == m ? RfColors.canvas : RfColors.text))),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
        Text(t.bindingNote, style: RfType.caption),
      ],
      action: action,
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({super.key, required this.icon, required this.onTap, this.primary = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) => Material(
        color: primary ? RfColors.gold : RfColors.surfaceSunken,
        borderRadius: BorderRadius.circular(RfRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(RfRadius.md),
          onTap: onTap,
          child: SizedBox(width: 50, height: 50, child: Icon(icon, size: 26, color: primary ? RfColors.onGold : RfColors.text)),
        ),
      );
}

/// Straight-line distance on the earth, in meters.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final a = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lng2 - lng1) / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
