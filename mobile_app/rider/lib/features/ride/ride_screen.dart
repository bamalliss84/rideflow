import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../shared/ride_map.dart';
import '../../shared/widgets.dart' show ActionRunner, AsyncBody;
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
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
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

enum _Sort { price, eta, rating }

class _OffersViewState extends ConsumerState<_OffersView> {
  _Sort _sort = _Sort.price;
  String? _selected;
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

  List<Offer> _ordered(List<Offer> offers) {
    final list = [...offers];
    switch (_sort) {
      case _Sort.price:
        list.sort((a, b) => a.amountMinor.compareTo(b.amountMinor));
      case _Sort.eta:
        list.sort((a, b) => a.etaSeconds.compareTo(b.etaSeconds));
      case _Sort.rating:
        list.sort((a, b) => (b.driver?.ratingAvg ?? 0).compareTo(a.driver?.ratingAvg ?? 0));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ride = widget.ride;
    final now = DateTime.now();
    final live = (ref.watch(offersProvider(ride.id)).valueOrNull ?? const <Offer>[]).where((o) => o.isLive(now)).toList();
    final selected = live.where((o) => o.id == _selected).firstOrNull;
    if (_selected != null && selected == null) {
      // The selected offer ran out or was withdrawn: say so, and never send a dead offer.
      _selected = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showToast(context, t.offerExpired, error: true);
      });
    }
    final price = RfCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Expanded(
          child: ride.riderPriceMinor == null
              ? Text('${t.estimate} ${widget.money(ride.estimateMin)}', style: RfType.caption)
              : Row(children: [Text('${t.yourPrice} ', style: RfType.caption), MoneyText(widget.money(ride.riderPriceMinor), style: RfType.bodyStrong.copyWith(color: RfColors.gold))]),
        ),
        TextButton(key: const Key('raisePrice'), onPressed: widget.busy ? null : widget.onRaise, child: Text(ride.riderPriceMinor == null ? t.addPrice : t.raisePrice)),
      ]),
    );
    final menu = ride.canCancel
        ? PopupMenuButton<String>(
            key: const Key('rideMenu'),
            tooltip: t.tripOptions,
            onSelected: (_) => widget.onCancel(),
            itemBuilder: (_) => [PopupMenuItem(key: const Key('cancelItem'), value: 'cancel', child: Text(t.cancelRequest))],
          )
        : const SizedBox(width: 48);
    if (live.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: Text('${t.to} ${ride.dropoffLandmark}', style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis)), menu]),
            const Spacer(),
            const Center(child: _Pulse()),
            const SizedBox(height: 28),
            Text(t.searching, key: const Key('searching'), textAlign: TextAlign.center, style: RfType.h1),
            const SizedBox(height: 8),
            Text(t.searchingNote, textAlign: TextAlign.center, style: RfType.body.copyWith(color: RfColors.textMuted, height: 1.6)),
            const Spacer(),
            price,
          ]),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text(t.offersTitle('${live.length}'), style: RfType.h2)), menu]),
          const SizedBox(height: 8),
          SegmentedPills(
            labels: [t.cheapest, t.nearest, t.topRated],
            selected: _sort.index,
            onSelected: (i) => setState(() => _sort = _Sort.values[i]),
          ),
          const SizedBox(height: 10),
          price,
          const SizedBox(height: 10),
          Expanded(
            child: ListView(children: [
              for (final o in _ordered(live))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OfferCard(key: Key('offer_${o.id}'), offer: o, money: widget.money, selected: o.id == _selected, onTap: () => setState(() => _selected = o.id)),
                ),
            ]),
          ),
          RfButton(
            key: const Key('selectOffer'),
            label: selected == null ? t.chooseOffer : t.selectOffer(selected.driver?.name ?? t.driver, widget.money(selected.amountMinor)),
            large: true,
            loading: widget.busy,
            onPressed: selected == null ? null : () => widget.onSelect(selected),
          ),
        ]),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({super.key, required this.offer, required this.money, required this.selected, required this.onTap});
  final Offer offer;
  final String Function(int?) money;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = offer.driver;
    final total = offer.expiresAt == null || offer.createdAt == null ? 0 : offer.expiresAt!.difference(offer.createdAt!).inSeconds;
    final left = offer.expiresAt == null ? 0 : offer.expiresAt!.difference(DateTime.now()).inSeconds;
    return RfCard(
      onTap: onTap,
      color: selected ? RfColors.tealSoft : null,
      border: selected ? RfColors.teal : null,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          DriverAvatar(name: d?.name ?? ''),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d?.name ?? t.driver, style: RfType.bodyStrong),
              const SizedBox(height: 2),
              DriverStats(driver: d),
              const SizedBox(height: 2),
              Text('${d?.vehicle?.name ?? ''} · ${t.minutes('${(offer.etaSeconds / 60).ceil()}')}', style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          MoneyText(money(offer.amountMinor), style: RfType.number.copyWith(color: RfColors.gold)),
        ]),
        if (total > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: (left / total).clamp(0.0, 1.0), minHeight: 3, backgroundColor: RfColors.surfaceSunken, color: RfColors.teal),
          ),
        ],
      ]),
    );
  }
}

class _Pulse extends StatelessWidget {
  const _Pulse();
  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(color: RfColors.teal.withOpacity(0.06), shape: BoxShape.circle, border: Border.all(color: RfColors.line, width: 2)),
        child: Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: RfColors.teal.withOpacity(0.1), shape: BoxShape.circle),
            child: Center(child: Container(width: 30, height: 30, decoration: BoxDecoration(color: RfColors.canvas, shape: BoxShape.circle, border: Border.all(color: RfColors.teal, width: 6)))),
          ),
        ),
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
    final deadline = widget.ride.matchDeadline;
    final left = deadline == null ? 0 : deadline.difference(DateTime.now()).inSeconds.clamp(0, 999);
    Widget step(String label, Widget mark, {bool done = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [Expanded(child: Text(label, style: RfType.bodyStrong.copyWith(color: done ? RfColors.text : RfColors.textMuted))), mark]),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.confirming, key: const Key('confirming'), style: RfType.h2),
          const SizedBox(height: 28),
          Center(
            child: Column(children: [
              Text('$left', style: RfType.display.copyWith(fontSize: 32)),
              Text(t.seconds, style: RfType.caption),
            ]),
          ),
          const SizedBox(height: 24),
          Text(t.waitingFor(widget.ride.driver?.name ?? t.driver), textAlign: TextAlign.center, style: RfType.h2),
          const SizedBox(height: 4),
          Text(t.notifyYou, textAlign: TextAlign.center, style: RfType.caption),
          const SizedBox(height: 24),
          RfCard(
            child: Column(children: [
              step(t.stepSent, Icon(Icons.check_rounded, color: RfColors.teal)),
              const Divider(),
              step(t.stepReview, const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              const Divider(),
              step(t.stepConfirm, Icon(Icons.radio_button_unchecked_rounded, color: RfColors.textMuted), done: false),
            ]),
          ),
          const Spacer(),
          if (widget.ride.canCancel) RfButton(key: const Key('cancelRequest'), label: t.cancelRequest, kind: RfButtonKind.secondary, onPressed: widget.onCancel),
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
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 30),
          Center(child: CircleAvatar(radius: 46, backgroundColor: RfColors.tealSoft, child: Icon(Icons.check_rounded, color: RfColors.teal, size: 54))),
          const SizedBox(height: 18),
          Text(t.tripConfirmed, key: const Key('tripConfirmed'), textAlign: TextAlign.center, style: RfType.h1),
          const SizedBox(height: 24),
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
      if (mounted && widget.ride.status == 'in_progress') setState(() {});
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
    final title = riding ? ride.dropoffLandmark : (arrived ? t.driverArrived : t.driverOnWay);
    final elapsed = ride.startedAt == null ? Duration.zero : DateTime.now().difference(ride.startedAt!);
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Column(children: [
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: RideMap(pickup: riding ? null : ride.pickup, dropoff: riding ? ride.dropoff : null, driver: position?.point, driverStale: position?.stale ?? false, center: position?.point ?? ride.pickup)),
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
        decoration: BoxDecoration(color: RfColors.ink2, border: Border(top: BorderSide(color: RfColors.line)), borderRadius: const BorderRadius.vertical(top: Radius.circular(RfRadius.xl))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (riding) Text(t.onWayTo, style: RfType.caption),
              Text(title, key: const Key('tripTitle'), style: RfType.h2.copyWith(color: arrived ? RfColors.teal : RfColors.text)),
              if (arrived) Text(ride.startCode != null ? t.goToCarCode : t.goToCar, style: RfType.caption),
              const SizedBox(height: 12),
              if (riding)
                RfCard(
                  child: Row(children: [
                    Expanded(child: StatColumn(label: t.tripTime, value: '$mm:$ss')),
                    Expanded(child: StatColumn(label: t.distance, value: formatDistance(ride.distanceM))),
                    Expanded(child: StatColumn(label: t.fare, value: widget.money(ride.fareMinor), color: RfColors.gold)),
                  ]),
                )
              else ...[
                _DriverCard(ride: ride, onCall: widget.onCall),
                if (ride.startCode != null) ...[
                  const SizedBox(height: 10),
                  RfCard(
                    key: const Key('startCode'),
                    border: RfColors.teal,
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t.startCodeTitle, style: RfType.bodyStrong), Text(t.giveCode, style: RfType.caption)])),
                      Ltr(ride.startCode!, style: RfType.number.copyWith(color: RfColors.teal, fontSize: 20, letterSpacing: 3)),
                    ]),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: RfButton(key: const Key('share'), label: t.share, kind: RfButtonKind.secondary, icon: Icons.ios_share_rounded, onPressed: widget.busy ? null : widget.onShare)),
                const SizedBox(width: 10),
                Expanded(child: RfButton(key: const Key('emergency'), label: t.emergency, kind: RfButtonKind.dangerSoft, icon: Icons.warning_amber_rounded, onPressed: widget.onEmergency)),
              ]),
            ]),
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
    return RfCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          DriverAvatar(name: d?.name ?? ''),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(d?.name ?? t.driver, style: RfType.bodyStrong), DriverStats(driver: d)])),
          if (d?.phone != null) IconButton.filled(key: const Key('callDriver'), tooltip: t.call, style: IconButton.styleFrom(backgroundColor: RfColors.tealSoft, minimumSize: const Size(48, 48)), onPressed: () => onCall(d!.phone!), icon: Icon(Icons.phone_rounded, color: RfColors.teal)),
        ]),
        if (v != null) ...[
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v.name, style: RfType.bodyStrong), Text(v.color, style: RfType.caption)])),
            if (v.plate != null)
              Container(
                key: const Key('plate'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(RfRadius.sm)),
                child: Ltr(v.plate!, style: RfType.bodyStrong),
              ),
          ]),
        ],
      ]),
    );
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 36),
          Center(child: CircleAvatar(radius: 46, backgroundColor: RfColors.tealSoft, child: Icon(Icons.flag_rounded, color: RfColors.teal, size: 48))),
          const SizedBox(height: 18),
          Text(t.reachedDestination, key: const Key('reached'), textAlign: TextAlign.center, style: RfType.h1),
          Text(ride.dropoffLandmark, textAlign: TextAlign.center, style: RfType.caption),
          const SizedBox(height: 28),
          RfCard(
            child: Column(children: [
              Text(t.fareCash, style: RfType.caption),
              MoneyText(money(ride.fareMinor), style: RfType.display.copyWith(color: RfColors.gold, fontSize: 26)),
            ]),
          ),
          const SizedBox(height: 14),
          RfButton(key: const Key('paid'), label: ride.cashConfirmedByMe ? t.paidDone : t.paid, kind: RfButtonKind.secondary, loading: busy, onPressed: ride.cashConfirmedByMe ? null : onPaid),
          const Spacer(),
          if (rated) RfButton(key: const Key('toReceipt'), label: t.receipt, large: true, onPressed: onReceipt) else RfButton(key: const Key('rateTrip'), label: t.rateTrip, large: true, onPressed: onRate),
        ]),
      ),
    );
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
          Center(child: CircleAvatar(radius: 42, backgroundColor: RfColors.surface, child: Icon(Icons.schedule_rounded, color: RfColors.gold, size: 38))),
          const SizedBox(height: 24),
          Text(t.noOffers, key: const Key('noOffers'), textAlign: TextAlign.center, style: RfType.h1),
          const SizedBox(height: 8),
          Text(t.noOffersNote, textAlign: TextAlign.center, style: RfType.body.copyWith(color: RfColors.textMuted, height: 1.6)),
          const SizedBox(height: 28),
          RfCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ride.dropoffLandmark, style: RfType.bodyStrong),
              if (was != null) Text(t.wasPrice(money(was)), style: RfType.caption),
            ]),
          ),
          const Spacer(),
          RfButton(key: const Key('requestAgain'), label: t.requestAgain, large: true, onPressed: () => context.go('/request', extra: _draft(price: was))),
          const SizedBox(height: 8),
          if (higher != null) ...[RfButton(key: const Key('requestHigher'), label: t.requestHigher, kind: RfButtonKind.secondary, onPressed: () => context.go('/request', extra: _draft(price: higher))), const SizedBox(height: 4)],
          RfButton(label: t.goHome, kind: RfButtonKind.ghost, onPressed: () => context.go('/')),
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
      Icon(Icons.star_rounded, color: RfColors.gold, size: 15),
      const SizedBox(width: 3),
      Text(d.ratingProvisional || d.ratingAvg == null ? t.newDriver : d.ratingAvg!.toStringAsFixed(1), style: RfType.caption.copyWith(color: RfColors.text, fontWeight: FontWeight.w700)),
      Flexible(child: Text(' · ${t.rideCount('${d.completedRides}')}', style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
  }
}
