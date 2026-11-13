import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/app_settings.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/driver_photo.dart';
import '../../shared/ride_map.dart';
import '../../shared/widgets.dart' show ActionRunner, AsyncBody;
import '../home/home_screen.dart' show LiveDot, metersBetween;
import '../request/request_screen.dart';
import 'rating_panel.dart';

/// One screen per ride, showing whatever the ride's server state calls for. Hints and a slow poll keep it fresh.
class RideScreen extends ConsumerStatefulWidget {
  const RideScreen({super.key, required this.rideId});
  final String rideId;
  @override
  ConsumerState<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends ConsumerState<RideScreen> {
  final _runner = ActionRunner();
  Timer? _poll;
  bool _seenConfirmed = false;
  bool _rating = false;
  int _pollsSinceWave = 0;
  bool _wavesDone = false;

  @override
  void initState() {
    super.initState();
    _startPoll(ref.read(appSettingsProvider).riderRideRefresh);
    ref.listenManual<AppSettings>(appSettingsProvider, (a, b) {
      if (a?.riderRideRefresh != b.riderRideRefresh) _startPoll(b.riderRideRefresh);
    });
  }

  /// The gap is the operator's `app.rider_ride_refresh_seconds` (D051).
  void _startPoll(Duration every) {
    _poll?.cancel();
    _poll = Timer.periodic(every, (_) {
      final ride = ref.read(rideProvider(widget.rideId)).valueOrNull;
      if (ride == null || !ride.isActive) return;
      _refresh();
      if (ride.driver != null) ref.invalidate(driverPositionProvider(widget.rideId));
      _widenSearch(ride);
    });
  }

  /// The server only sends the first wave, so a request nobody received would otherwise wait until it expires.
  Future<void> _widenSearch(Ride ride) async {
    if (_wavesDone || (ride.status != 'requested' && ride.status != 'bidding')) return;
    final offers = ref.read(offersProvider(widget.rideId)).valueOrNull ?? const <Offer>[];
    if (offers.any((o) => o.isLive(DateTime.now())) || ++_pollsSinceWave < 3) return;
    _pollsSinceWave = 0;
    try {
      await ref.read(riderApiProvider).dispatchNextWave(ride.id);
      if (mounted) _refresh();
    } on ApiException catch (e) {
      if (e.code == 'max_waves_reached') _wavesDone = true;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(rideProvider(widget.rideId));
    ref.invalidate(offersProvider(widget.rideId));
  }

  Future<void> _act(Future<void> Function() action) async {
    await _runner.run(context, action, onChanged: () => setState(() {}));
    if (!mounted) return;
    _refresh();
    ref.invalidate(ridesProvider);
  }

  Future<void> _cancel(Ride ride) async {
    final picked = await showModalBottomSheet<({String code, String text})>(context: context, isScrollControlled: true, backgroundColor: RfColors.ink2, builder: (_) => _CancelSheet(ride: ride));
    if (picked != null) await _act(() => ref.read(riderApiProvider).cancel(ride, code: picked.code, reason: picked.text));
  }

  Future<void> _raise(Ride ride, int units) async {
    final step = ride.stepMinor ?? defaultStepMinor(units);
    final current = ride.riderPriceMinor;
    final minimum = current == null ? (ride.estimateMin ?? step) : current + step;
    final picked = await showPriceSheet(context, start: minimum, minimum: minimum, step: step, currency: ride.currency, minorUnits: units, estimate: '${formatMoney(ride.estimateMin, '', units)} – ${formatMoney(ride.estimateMax, ride.currency, units)}');
    if (picked != null && picked > 0) await _act(() => ref.read(riderApiProvider).raisePrice(ride, picked));
  }

  Future<void> _share(Ride ride) async {
    final t = AppLocalizations.of(context);
    await _act(() async {
      final url = await ref.read(riderApiProvider).share(ride.id);
      if (url == null) {
        if (mounted) showToast(context, t.shareNotReady, error: true);
        return;
      }
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) showToast(context, t.linkCopied);
    });
  }

  Future<void> _emergency(Ride ride) async {
    final t = AppLocalizations.of(context);
    final phone = ride.emergencyPhone;
    if (phone == null) {
      showToast(context, t.emergencyOff, error: true);
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.emergency),
        content: Text(t.emergencyConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(key: const Key('emergencyGo'), onPressed: () => Navigator.pop(ctx, true), child: Text(t.confirm)),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    // The call matters most, so it never waits on the server.
    final opened = await ref.read(externalAppsProvider).dial(phone);
    if (!opened && mounted) showToast(context, t.callFailed, error: true);
    unawaited(ref.read(riderApiProvider).emergency(ride.id, ref.read(myLocationProvider).valueOrNull).catchError((_) {}));
  }

  Future<void> _call(String phone) async {
    final t = AppLocalizations.of(context);
    final opened = await ref.read(externalAppsProvider).dial(phone);
    if (!opened && mounted) showToast(context, t.callFailed, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final units = ref.watch(authProvider).valueOrNull?.minorUnits ?? 2;
    final value = ref.watch(rideProvider(widget.rideId));
    return Scaffold(
      body: AsyncBody<Ride>(
        value: value,
        onRetry: _refresh,
        data: (ride) {
          String money(int? v) => formatMoney(v, ride.currency, units);
          switch (ride.status) {
            case 'requested' || 'bidding':
              return _OffersView(ride: ride, money: money, busy: _runner.busy, onSelect: (o) => _act(() => ref.read(riderApiProvider).select(ride, o.id, actionKey: newActionKey())), onRaise: () => _raise(ride, units), onCancel: () => _cancel(ride));
            case 'match_pending':
              return _ConfirmingView(ride: ride, money: money, onCancel: () => _cancel(ride));
            case 'assigned' || 'en_route' when !_seenConfirmed && ride.status == 'assigned':
              return _ConfirmedView(ride: ride, onCall: _call, onContinue: () => setState(() => _seenConfirmed = true));
            case 'assigned' || 'en_route' || 'arrived' || 'in_progress':
              return _TripView(ride: ride, money: money, busy: _runner.busy, onCall: _call, onShare: () => _share(ride), onEmergency: () => _emergency(ride), onCancel: () => _cancel(ride));
            case 'completed':
              if (_rating) return RatingPanel(ride: ride, onDone: () => context.go('/receipt/${ride.id}'));
              return _ArrivedView(ride: ride, money: money, busy: _runner.busy, onPaid: () => _act(() => ref.read(riderApiProvider).confirmCash(ride.id, actionKey: newActionKey())), onRate: () => setState(() => _rating = true), onReceipt: () => context.go('/receipt/${ride.id}'));
          }
          if (ride.expiredWithoutOffers) return _NoOffersView(ride: ride, money: money, units: units);
          return _EndedView(title: t.rideEnded, status: t.status_cancelled);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- offers

class _OffersView extends ConsumerStatefulWidget {
  const _OffersView({required this.ride, required this.money, required this.busy, required this.onSelect, required this.onRaise, required this.onCancel});
  final Ride ride;
  final String Function(int?) money;
  final bool busy;
  final void Function(Offer) onSelect;
  final VoidCallback onRaise, onCancel;
  @override
  ConsumerState<_OffersView> createState() => _OffersViewState();
}

class _OffersViewState extends ConsumerState<_OffersView> {
  final _hidden = <String>{}; // offers the rider ignored, on this phone only
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ride = widget.ride;
    final now = DateTime.now();
    final all = (ref.watch(offersProvider(ride.id)).valueOrNull ?? const <Offer>[]).where((o) => o.isLive(now)).toList()
      ..sort((a, b) => a.amountMinor.compareTo(b.amountMinor));
    final live = all.where((o) => !_hidden.contains(o.id)).toList();
    final price = Row(children: [
      Expanded(
        child: ride.riderPriceMinor == null
            ? Text('${t.estimate} ${widget.money(ride.estimateMin)}', style: RfType.caption)
            : Row(children: [Text('${t.yourPrice}  ', style: RfType.caption), MoneyText(widget.money(ride.riderPriceMinor), style: RfLayout.priceSmall)]),
      ),
      TextButton(
        key: const Key('raisePrice'),
        style: TextButton.styleFrom(backgroundColor: RfColors.pri, foregroundColor: RfColors.onPri, minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 16), shape: const StadiumBorder()),
        onPressed: widget.busy ? null : widget.onRaise,
        child: Text(ride.riderPriceMinor == null ? t.addPrice : t.raisePrice, style: RfType.bodyStrong.copyWith(color: RfColors.onPri)),
      ),
    ]);

    if (live.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            const Center(child: _Pulse()),
            const SizedBox(height: 24),
            Text(t.searching, key: const Key('searching'), textAlign: TextAlign.center, style: RfType.h1),
            const SizedBox(height: 6),
            Text(t.searchingNote, textAlign: TextAlign.center, style: RfType.body.copyWith(color: RfColors.textMuted, height: 1.6)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                RouteStops(pickupLabel: t.from, pickup: ride.pickupLandmark, dropoffLabel: t.to, dropoff: ride.dropoffLandmark, dense: true, showLabels: false),
                Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Container(height: 1, color: RfColors.line)),
                price,
              ]),
            ),
            if (ride.canCancel) ...[
              const SizedBox(height: 8),
              RfButton(key: const Key('cancelRequest'), label: t.cancelRequest, kind: RfButtonKind.ghost, onPressed: widget.onCancel),
            ],
          ]),
        ),
      );
    }
    final menu = ride.canCancel
        ? PopupMenuButton<String>(
            key: const Key('rideMenu'),
            tooltip: t.tripOptions,
            onSelected: (_) => widget.onCancel(),
            itemBuilder: (_) => [PopupMenuItem(key: const Key('cancelItem'), value: 'cancel', child: Text(t.cancelRequest))],
          )
        : const SizedBox(width: 48);
    final cheapest = live.length > 1 ? live.first.id : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.offersTitle('${live.length}'), style: RfType.h1),
                    Text(t.pickFromCard, style: RfType.caption),
                  ]),
                ),
                menu,
              ]),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(children: [
                  for (final o in live)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OfferCard(
                        key: Key('offer_${o.id}'),
                        offer: o,
                        money: widget.money,
                        cheapest: o.id == cheapest,
                        busy: widget.busy,
                        // A card that ran out between the last tick and the tap is never sent.
                        onAccept: () => o.isLive(DateTime.now()) ? widget.onSelect(o) : showToast(context, t.offerExpired, error: true),
                        onIgnore: () => setState(() => _hidden.add(o.id)),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
      RfFoot(child: price),
    ]);
  }
}

/// "4:10" for what is left of a countdown.
String countdown(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// One offer (direction A, board 5): who, the car, the price largest, and accept straight from the card with the time
/// left on it.
class _OfferCard extends StatelessWidget {
  const _OfferCard({super.key, required this.offer, required this.money, required this.cheapest, required this.busy, required this.onAccept, required this.onIgnore});
  final Offer offer;
  final String Function(int?) money;
  final bool cheapest, busy;
  final VoidCallback onAccept, onIgnore;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = offer.driver;
    final left = offer.expiresAt?.difference(DateTime.now()).inSeconds;
    final id = offer.id;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DriverPhoto(driver: d, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d?.name ?? t.driver, style: RfType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
              Row(children: [
                _Stars(driver: d),
                Flexible(child: Text(' · ${t.tripsCount('${d?.completedRides ?? 0}')}', style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              if (d?.vehicle?.name != null) Text(d!.vehicle!.name, style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (cheapest)
                Container(
                  key: const Key('cheapestTag'),
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: RfColors.tealSoft, borderRadius: BorderRadius.circular(RfRadius.pill)),
                  child: Text(t.cheapest, style: RfType.caption.copyWith(color: RfColors.tealDeep, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            MoneyText(money(offer.amountMinor), style: RfLayout.price),
            Text('${t.arrivesFact} ${t.minutes('${(offer.etaSeconds / 60).ceil()}')}', style: RfType.caption),
          ]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: RfButton(key: Key('ignore_$id'), label: t.ignore, kind: RfButtonKind.secondary, onPressed: busy ? null : onIgnore)),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: RfButton(key: Key('accept_$id'), label: left == null ? t.accept : t.acceptIn(countdown(left)), loading: busy, onPressed: onAccept),
          ),
        ]),
      ]),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.driver});
  final Driver? driver;
  @override
  Widget build(BuildContext context) {
    final d = driver;
    final isNew = d == null || d.ratingProvisional || d.ratingAvg == null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, color: RfColors.star, size: 14),
      const SizedBox(width: 2),
      Text(isNew ? AppLocalizations.of(context).newDriver : d.ratingAvg!.toStringAsFixed(1), style: RfType.bodyStrong),
    ]);
  }
}

/// Rings spreading from the middle while looking for drivers. Still when the phone asks for less motion.
class _Pulse extends StatefulWidget {
  const _Pulse();
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Widget _ring(double delay) => AnimatedBuilder(
        animation: _spin,
        builder: (_, __) {
          final v = (_spin.value + delay) % 1;
          return Transform.scale(
            scale: 0.35 + 0.65 * v,
            child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: RfColors.teal.withOpacity(0.55 * (1 - v)), width: 2))),
          );
        },
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const Key('searchPulse'),
        width: 150,
        height: 150,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: _ring(0)),
          Positioned.fill(child: _ring(1 / 3)),
          Positioned.fill(child: _ring(2 / 3)),
          const _PulseCore(),
        ]),
      );
}

class _PulseCore extends StatelessWidget {
  const _PulseCore();
  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(color: RfColors.teal.withOpacity(0.1), shape: BoxShape.circle),
        child: Center(child: Container(width: 30, height: 30, decoration: BoxDecoration(color: RfColors.canvas, shape: BoxShape.circle, border: Border.all(color: RfColors.teal, width: 6)))),
      );
}

// ---------------------------------------------------------------- confirmation

class _ConfirmingView extends StatefulWidget {
  const _ConfirmingView({required this.ride, required this.money, required this.onCancel});
  final Ride ride;
  final String Function(int?) money;
  final VoidCallback onCancel;
  @override
  State<_ConfirmingView> createState() => _ConfirmingViewState();
}

class _ConfirmingViewState extends State<_ConfirmingView> {
  Timer? _tick;
  int? _total; // the confirmation window as first seen, for the ring
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ride = widget.ride;
    final d = ride.driver;
    final v = d?.vehicle;
    final deadline = ride.matchDeadline;
    final left = deadline == null ? 0 : deadline.difference(DateTime.now()).inSeconds.clamp(0, 999);
    final total = _total ??= left > 0 ? left : 1;
    final fare = ride.agreedFareMinor;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Spacer(),
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: Stack(fit: StackFit.expand, children: [
                CircularProgressIndicator(value: (left / total).clamp(0.0, 1.0), strokeWidth: 7, color: RfColors.pri, backgroundColor: RfColors.surfaceSunken, strokeCap: StrokeCap.round),
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Ltr(countdown(left), key: const Key('confirmLeft'), style: RfType.display.copyWith(fontSize: 30)),
                    Text(t.toConfirm, style: RfType.caption),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          Text(t.confirmingTitle(d?.name ?? t.driver), key: const Key('confirming'), textAlign: TextAlign.center, style: RfType.h1),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (v != null) Flexible(child: Text('${v.color.isEmpty ? v.name : '${v.name} · ${v.color}'} · ', style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (d != null) Flexible(child: DriverStats(driver: d)),
          ]),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(16)),
            child: Text(fare == null ? t.confirmNote : t.confirmPriceNote(widget.money(fare)), style: RfType.body.copyWith(height: 1.6), textAlign: TextAlign.center),
          ),
          const Spacer(),
          if (ride.canCancel) RfButton(key: const Key('cancelRequest'), label: t.cancelRequest, kind: RfButtonKind.ghost, onPressed: widget.onCancel),
        ]),
      ),
    );
  }
}

class _ConfirmedView extends StatelessWidget {
  const _ConfirmedView({required this.ride, required this.onCall, required this.onContinue});
  final Ride ride;
  final void Function(String) onCall;
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 24),
          Center(child: CircleAvatar(radius: 34, backgroundColor: RfColors.tealSoft, child: Icon(Icons.check_rounded, color: RfColors.teal, size: 38))),
          const SizedBox(height: 12),
          Text(t.tripConfirmed, key: const Key('tripConfirmed'), textAlign: TextAlign.center, style: RfType.h1),
          const SizedBox(height: 12),
          _DriverCard(ride: ride, onCall: onCall),
          const Spacer(),
          RfButton(key: const Key('followDriver'), label: t.followDriver, large: true, onPressed: onContinue),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- the trip

class _TripView extends ConsumerStatefulWidget {
  const _TripView({required this.ride, required this.money, required this.busy, required this.onCall, required this.onShare, required this.onEmergency, required this.onCancel});
  final Ride ride;
  final String Function(int?) money;
  final bool busy;
  final void Function(String) onCall;
  final VoidCallback onShare, onEmergency, onCancel;
  @override
  ConsumerState<_TripView> createState() => _TripViewState();
}

class _TripViewState extends ConsumerState<_TripView> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (widget.ride.status == 'in_progress' || widget.ride.freeCancelUntil != null)) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ride = widget.ride;
    final position = ref.watch(driverPositionProvider(ride.id)).valueOrNull;
    final riding = ride.status == 'in_progress';
    final arrived = ride.status == 'arrived';
    final now = DateTime.now();
    final d = ride.driver;
    final safety = Row(children: [
      Expanded(child: RfButton(key: const Key('share'), label: t.share, kind: RfButtonKind.secondary, icon: Icons.ios_share_rounded, onPressed: widget.busy ? null : widget.onShare)),
      const SizedBox(width: 8),
      Expanded(child: RfButton(key: const Key('emergency'), label: t.emergency, kind: RfButtonKind.dangerSoft, icon: Icons.warning_amber_rounded, onPressed: widget.onEmergency)),
    ]);
    Widget heading(String text) => Row(children: [
          const LiveDot(),
          const SizedBox(width: 10),
          Expanded(child: Text(text, key: const Key('tripTitle'), style: RfType.h1.copyWith(color: arrived ? RfColors.tealDeep : RfColors.text))),
        ]);

    final List<Widget> body;
    if (riding) {
      // Board 9: where to, how long so far, how far is left (straight line from the driver), the fare.
      final elapsed = ride.startedAt == null ? Duration.zero : now.difference(ride.startedAt!);
      final total = ride.pickup != null && ride.dropoff != null ? metersBetween(ride.pickup!, ride.dropoff!) : null;
      final left = position != null && ride.dropoff != null ? metersBetween(position.point, ride.dropoff!) : null;
      final progress = total == null || left == null || total <= 0 ? null : (1 - left / total).clamp(0.0, 1.0);
      body = [
        Text(t.onWayTo, style: RfType.caption),
        Text(ride.dropoffLandmark, key: const Key('tripTitle'), style: RfType.h1, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.tripTime, style: RfType.caption),
              Ltr(countdown(elapsed.inSeconds), style: RfType.h2),
            ]),
          ),
          if (left != null)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.remaining, style: RfType.caption),
                Ltr(formatDistance(left.round()), key: const Key('remaining'), style: RfType.h2),
              ]),
            ),
          MoneyText(widget.money(ride.fareMinor), style: RfLayout.price),
        ]),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(key: const Key('tripProgress'), value: progress, minHeight: 5, color: RfColors.teal, backgroundColor: RfColors.surfaceSunken),
            ),
          ),
        const SizedBox(height: 10),
        Text([d?.name ?? t.driver, if (d?.vehicle?.plate != null) d!.vehicle!.plate!].join(' · '), style: RfType.caption),
        const SizedBox(height: 10),
        if (ride.pickup != null && ride.dropoff != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RfButton(
              key: const Key('openGoogleMaps'),
              label: t.openGoogleMaps,
              kind: RfButtonKind.secondary,
              icon: Icons.open_in_new_rounded,
              onPressed: () async {
                final ok = await ref.read(externalAppsProvider).directions(fromLat: ride.pickup!.lat, fromLng: ride.pickup!.lng, toLat: ride.dropoff!.lat, toLng: ride.dropoff!.lng);
                if (!ok && context.mounted) showToast(context, t.mapsFailed, error: true);
              },
            ),
          ),
        safety,
      ];
    } else if (arrived) {
      // Board 8: the driver is here, how long they have waited, and the code large enough to read out.
      final since = ride.arrivedAt;
      body = [
        heading(t.driverArrived),
        if (since != null) Text(t.waitingSince(countdown(now.difference(since).inSeconds)), key: const Key('waitingSince'), style: RfType.caption),
        const SizedBox(height: 12),
        _DriverCard(ride: ride, onCall: widget.onCall),
        if (ride.startCode != null) ...[
          const SizedBox(height: 14),
          Text(t.sayCode, key: const Key('startCode'), textAlign: TextAlign.center, style: RfType.bodyStrong),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final c in ride.startCode!.split(''))
                Container(
                  width: 54,
                  height: 62,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(14)),
                  child: Text(c, style: RfType.display.copyWith(fontSize: 28)),
                ),
            ]),
          ),
        ] else
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(t.goToCar, style: RfType.caption)),
        const SizedBox(height: 14),
        safety,
      ];
    } else {
      // Board 7: on the way.
      body = [
        heading(t.driverOnWay),
        if (position != null && ride.pickup != null) Text(t.driverAway(formatDistance(metersBetween(position.point, ride.pickup!).round())), key: const Key('driverAway'), style: RfType.caption),
        const SizedBox(height: 12),
        _DriverCard(ride: ride, onCall: widget.onCall),
        if (ride.startCode != null)
          Container(
            key: const Key('startCode'),
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.startCodeTitle, style: RfType.bodyStrong),
                  Text(t.codeOnBoard, style: RfType.caption),
                ]),
              ),
              const SizedBox(width: 8),
              Ltr(ride.startCode!, style: RfLayout.priceBig.copyWith(color: RfColors.text, letterSpacing: 4)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            if (ride.fareMinor != null) ...[MoneyText(widget.money(ride.fareMinor), style: RfType.bodyStrong), const SizedBox(width: 4)],
            Expanded(
              child: Text(
                [
                  t.cash,
                  if (ride.canCancel && ride.freeCancelUntil != null && ride.freeCancelUntil!.isAfter(now)) t.freeCancelLeft(countdown(ride.freeCancelUntil!.difference(now).inSeconds)),
                ].join(' · '),
                key: const Key('tripMoneyLine'),
                style: RfType.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        safety,
      ];
    }

    return Column(children: [
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: RideMap(pickup: ride.pickup, dropoff: riding ? ride.dropoff : null, driver: position?.point, driverStale: position?.stale ?? false, center: position?.point ?? ride.pickup)),
          if (ride.canCancel)
            SafeArea(
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: PopupMenuButton<String>(
                  key: const Key('rideMenu'),
                  tooltip: t.tripOptions,
                  onSelected: (_) => widget.onCancel(),
                  itemBuilder: (_) => [PopupMenuItem(key: const Key('cancelItem'), value: 'cancel', child: Text(t.cancelRide))],
                ),
              ),
            ),
        ]),
      ),
      Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
        decoration: BoxDecoration(
          color: RfColors.canvas,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 30, offset: Offset(0, -8))],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
          ),
        ),
      ),
    ]);
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.ride, required this.onCall});
  final Ride ride;
  final void Function(String) onCall;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = ride.driver;
    final v = d?.vehicle;
    return Row(children: [
      DriverPhoto(driver: d, radius: 24),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d?.name ?? t.driver, style: RfType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
          DriverStats(driver: d),
          if (v != null) Text(v.color.isEmpty ? v.name : '${v.name} · ${v.color}', style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
      if (v?.plate != null)
        Container(
          margin: const EdgeInsetsDirectional.only(end: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(8)),
          child: Ltr(v!.plate!, key: const Key('plate'), style: RfType.bodyStrong.copyWith(letterSpacing: 1)),
        ),
      if (d?.phone != null) RfCircleButton(key: const Key('callDriver'), icon: Icons.phone_rounded, tooltip: t.call, onPressed: () => onCall(d!.phone!)),
    ]);
  }
}

// ---------------------------------------------------------------- the end

class _ArrivedView extends StatelessWidget {
  const _ArrivedView({required this.ride, required this.money, required this.busy, required this.onPaid, required this.onRate, required this.onReceipt});
  final Ride ride;
  final String Function(int?) money;
  final bool busy;
  final VoidCallback onPaid, onRate, onReceipt;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rated = ride.myRatingStars != null;
    final map = ride.dropoff != null;
    final took = ride.startedAt != null && ride.completedAt != null ? ride.completedAt!.difference(ride.startedAt!) : null;
    final facts = [
      if (ride.distanceM != null) formatDistance(ride.distanceM),
      if (took != null) t.minutes('${took.inMinutes < 1 ? 1 : took.inMinutes}'),
    ].join(' · ');
    // Board 10: the cash to hand over is the largest thing, then the trip in one card, then the rating.
    return Column(children: [
      if (map) Expanded(child: RideMap(pickup: ride.pickup, dropoff: ride.dropoff, arrived: true)),
      Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (map ? 0.78 : 1)),
        decoration: BoxDecoration(
          color: RfColors.canvas,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 30, offset: Offset(0, -8))],
        ),
        child: SafeArea(
          top: !map,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_rounded, color: RfColors.teal, size: 22),
                const SizedBox(width: 8),
                Flexible(child: Text(t.safeArrival, key: const Key('reached'), style: RfType.h1)),
              ]),
              const SizedBox(height: 12),
              Text(t.payCash, textAlign: TextAlign.center, style: RfType.caption),
              Center(child: FittedBox(fit: BoxFit.scaleDown, child: MoneyText(money(ride.fareMinor), key: const Key('fareBig'), style: RfLayout.priceBig.copyWith(fontSize: 36)))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  RouteStops(pickupLabel: t.from, pickup: ride.pickupLandmark, dropoffLabel: t.to, dropoff: ride.dropoffLandmark, dense: true, showLabels: false),
                  if (facts.isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Container(height: 1, color: RfColors.line)),
                    Row(children: [Expanded(child: Text(t.distance, style: RfType.caption)), Ltr(facts, style: RfType.bodyStrong)]),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              RfButton(key: const Key('paid'), label: ride.cashConfirmedByMe ? t.paidDone : t.paid, kind: RfButtonKind.secondary, icon: ride.cashConfirmedByMe ? Icons.check_rounded : null, loading: busy, onPressed: ride.cashConfirmedByMe ? null : onPaid),
              const SizedBox(height: 14),
              if (rated)
                RfButton(key: const Key('toReceipt'), label: t.receipt, large: true, onPressed: onReceipt)
              else ...[
                Text(t.rateWith(ride.driver?.name ?? t.driver), textAlign: TextAlign.center, style: RfType.h2),
                const SizedBox(height: 8),
                RfButton(key: const Key('rateTrip'), label: t.rateTrip, large: true, icon: Icons.star_rounded, onPressed: onRate),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _NoOffersView extends ConsumerWidget {
  const _NoOffersView({required this.ride, required this.money, required this.units});
  final Ride ride;
  final String Function(int?) money;
  final int units;

  RideDraft? _draft({int? price}) {
    final p = ride.pickup, d = ride.dropoff;
    if (p == null || d == null) return null;
    return RideDraft(pickup: Place(ride.pickupLandmark, p), dropoff: Place(ride.dropoffLandmark, d), pickupNote: ride.pickupNote, dropoffNote: ride.dropoffNote, requireCode: ride.startCodeRequired, priceMinor: price);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final was = ride.riderPriceMinor;
    final higher = was == null ? null : was + (ride.stepMinor ?? defaultStepMinor(units));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Spacer(),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: RfColors.surfaceSunken, shape: BoxShape.circle),
              child: Icon(Icons.hourglass_empty_rounded, color: RfColors.text, size: 36),
            ),
          ),
          const SizedBox(height: 24),
          Text(t.noOffers, key: const Key('noOffers'), textAlign: TextAlign.center, style: RfType.h1),
          const SizedBox(height: 8),
          Text(t.noOffersNote, textAlign: TextAlign.center, style: RfType.body.copyWith(color: RfColors.textMuted, height: 1.6)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              RouteStops(pickupLabel: t.from, pickup: ride.pickupLandmark, dropoffLabel: t.to, dropoff: ride.dropoffLandmark, dense: true, showLabels: false),
              if (was != null) ...[const SizedBox(height: 8), Text(t.wasPrice(money(was)), style: RfType.caption)],
            ]),
          ),
          const Spacer(),
          if (higher != null) ...[
            RfButton(key: const Key('requestHigher'), label: t.raiseAndRequest(money(higher)), large: true, onPressed: () => context.go('/request', extra: _draft(price: higher))),
            const SizedBox(height: 8),
            RfButton(key: const Key('requestAgain'), label: t.requestAgain, kind: RfButtonKind.secondary, onPressed: () => context.go('/request', extra: _draft(price: was))),
          ] else
            RfButton(key: const Key('requestAgain'), label: t.requestAgain, large: true, onPressed: () => context.go('/request', extra: _draft(price: was))),
          const SizedBox(height: 4),
          RfButton(key: const Key('notNow'), label: t.notNow, kind: RfButtonKind.ghost, onPressed: () => context.go('/')),
        ]),
      ),
    );
  }
}

class _EndedView extends StatelessWidget {
  const _EndedView({required this.title, required this.status});
  final String title, status;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Spacer(),
          Text(title, key: const Key('rideEnded'), textAlign: TextAlign.center, style: RfType.h1),
          const SizedBox(height: 8),
          Text(status, textAlign: TextAlign.center, style: RfType.caption),
          const Spacer(),
          RfButton(label: t.goHome, large: true, onPressed: () => context.go('/')),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- cancelling

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.ride});
  final Ride ride;
  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _other = TextEditingController();
  String? _selected;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final until = widget.ride.freeCancelUntil;
    final reasons = {
      'changed_mind': t.reason_changed_mind,
      if (widget.ride.driver != null) ...{'driver_too_far': t.reason_driver_too_far, 'driver_asked': t.reason_driver_asked},
      'wait_too_long': t.reason_wait_too_long,
      'other': t.reason_other,
    };
    final isOther = _selected == 'other';
    final reason = isOther ? _other.text.trim() : reasons[_selected] ?? '';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(t.cancelTitle, style: RfType.h2),
            if (until != null) ...[
              const SizedBox(height: 4),
              Text(until.isAfter(DateTime.now()) ? t.cancelFreeUntil(formatTime(until)) : t.cancelLate, key: const Key('cancelNotice'), style: RfType.caption.copyWith(color: until.isAfter(DateTime.now()) ? RfColors.textMuted : RfColors.coral)),
            ],
            const SizedBox(height: 12),
            for (final e in reasons.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: _selected == e.key ? RfColors.text : RfColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(RfRadius.sm),
                  child: InkWell(
                    key: Key('reason_${e.key}'),
                    borderRadius: BorderRadius.circular(RfRadius.sm),
                    onTap: () => setState(() => _selected = e.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Text(e.value, style: RfType.bodyStrong.copyWith(color: _selected == e.key ? RfColors.canvas : RfColors.text)),
                    ),
                  ),
                ),
              ),
            if (isOther) TextField(key: const Key('reasonText'), controller: _other, maxLength: 300, autofocus: true, decoration: InputDecoration(hintText: t.reasonHint), onChanged: (_) => setState(() {})),
            const SizedBox(height: 4),
            RfButton(key: const Key('confirmCancel'), label: widget.ride.driver == null ? t.cancelRequest : t.cancelRide, kind: RfButtonKind.danger, onPressed: reason.isEmpty ? null : () => Navigator.pop(context, (code: _selected!, text: reason))),
            RfButton(label: t.back, kind: RfButtonKind.ghost, onPressed: () => Navigator.pop(context)),
          ]),
        ),
      ),
    );
  }
}

class DriverStats extends StatelessWidget {
  const DriverStats({super.key, required this.driver});
  final Driver? driver;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = driver;
    if (d == null) return const SizedBox.shrink();
    return Row(children: [
      Icon(Icons.star_rounded, color: RfColors.star, size: 15),
      const SizedBox(width: 3),
      Text(d.ratingProvisional || d.ratingAvg == null ? t.newDriver : d.ratingAvg!.toStringAsFixed(1), style: RfType.caption.copyWith(color: RfColors.text, fontWeight: FontWeight.w700)),
      Flexible(child: Text(' · ${t.rideCount('${d.completedRides}')}', style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
  }
}
