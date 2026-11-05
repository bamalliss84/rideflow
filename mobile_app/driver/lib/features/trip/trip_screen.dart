import 'dart:async';

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
import '../../shared/trip_map.dart';
import '../../shared/widgets.dart' show ActionRunner, AsyncBody, LoadingView, errorMessage;

/// Forward transitions in state-machine order; the backend's `allowed_actions` decides what's possible, and the
/// screen offers the first of them: one next step at a time.
const _primary = ['en_route', 'arrive', 'start', 'complete'];
const _menu = ['decline', 'driver_cancel'];

/// The driver's step in the trip (model 1, D039); null once there's nothing left to do on it.
int? tripStep(Ride ride) => switch (ride.status) {
      'assigned' || 'en_route' => 1,
      'arrived' => 2,
      'in_progress' => 3,
      'completed' when !ride.driverCashConfirmed => 4,
      _ => null,
    };

class TripScreen extends ConsumerStatefulWidget {
  const TripScreen({super.key, required this.rideId});
  final String rideId;
  @override
  ConsumerState<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends ConsumerState<TripScreen> {
  final _runner = ActionRunner();
  final _cashKey = newActionKey();

  /// One idempotency key per (action, ride version): retrying the same tap replays, a new state gets a new key.
  final _keys = <String, String>{};
  String _keyFor(String action, int version) => _keys.putIfAbsent('$action@$version', newActionKey);

  /// What the last "arrived" tap sent, by ride version. Its key must carry the same body when the tap is retried.
  final _arrivals = <int, Json>{};

  Future<void> _transition(Ride ride, String action) async {
    final t = AppLocalizations.of(context);
    final api = ref.read(driverApiProvider);
    Json extra = {};
    if (action == 'decline') {
      final reason = await _askReason(t.declineReason);
      if (reason == null) return;
      extra = {'reason': reason};
    }
    if (action == 'driver_cancel') {
      final reason = await _askCancelReason();
      if (reason == null) return;
      extra = {'reason': reason.text, 'reason_code': reason.code};
    }
    var attempt = action;
    if (action == 'start' && ride.startCodeRequired) {
      final code = await _askStartCode();
      if (code == null) return;
      extra = {'start_code': code};
      attempt = 'start:$code'; // a refused code is remembered under its key, so a different code needs a new one
    }
    if (!mounted) return;
    await _runner.run(context, () async {
      if (action == 'arrive') {
        // Arrival is evidence: the backend checks the geofence and GPS accuracy from these values. Reading them is part
        // of the action, so the button shows it's working from the first tap. No location in time: the tap still counts,
        // and the location follows when there is one (D045).
        final p = _arrivals.containsKey(ride.version) ? null : await ref.read(locationServiceProvider).now();
        extra = _arrivals[ride.version] ??= p == null ? const {} : {'lat': p.lat, 'lng': p.lng, 'accuracy_m': p.accuracy, 'device_ts': p.deviceTs.toUtc().toIso8601String()};
      }
      try {
        await api.transition(ride, action, actionKey: _keyFor(attempt, ride.version), extra: extra);
      } on ApiException catch (e) {
        if (e.status == 409) _refresh(); // state moved on (other party / timer): show the current one
        rethrow;
      }
      if (action == 'arrive' && extra.isEmpty) {
        unawaited(ref.read(arrivalFixQueueProvider).add(ride.id));
        if (mounted) showToast(context, t.arrivedNoLocation);
      }
    }, onChanged: () => setState(() {}));
    _refresh();
  }

  Future<void> _confirmCash(Ride ride) async {
    await _runner.run(context, () => ref.read(driverApiProvider).confirmCash(ride.id, actionKey: _cashKey), onChanged: () => setState(() {}));
    _refresh();
  }

  void _refresh() {
    ref.invalidate(rideProvider(widget.rideId));
    ref.invalidate(ridesProvider);
    ref.invalidate(offersProvider);
    ref.read(pendingMatchProvider.notifier).reconcile();
  }

  Future<void> _callRider(Ride ride) async {
    final t = AppLocalizations.of(context);
    final opened = await ref.read(externalAppsProvider).dial(ride.rider!.phone!);
    if (!mounted) return;
    if (!opened) {
      showToast(context, t.callFailed, error: true);
      return;
    }
    // Evidence for a no-show report, and it tells the rider the driver is waiting: only true after arrival.
    if (ride.status != 'arrived') return;
    await _runner.run(context, () => ref.read(driverApiProvider).contactAttempt(ride.id, 'call'), onChanged: () => setState(() {}), success: t.contactLogged);
    _refresh();
  }

  Future<void> _openMap(LatLng target) async {
    final t = AppLocalizations.of(context);
    final opened = await ref.read(externalAppsProvider).showOnMap(target.lat, target.lng);
    if (!opened && mounted) showToast(context, t.mapsFailed, error: true);
  }

  Future<String?> _askStartCode() {
    final c = TextEditingController();
    final t = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.startCodeTitle),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.startCodeHint, style: RfType.caption),
          TextField(key: const Key('startCodeInput'), controller: c, maxLength: 4, autofocus: true, keyboardType: TextInputType.number, textDirection: TextDirection.ltr, textAlign: TextAlign.center),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          TextButton(
            key: const Key('confirmStartCode'),
            onPressed: () {
              if (c.text.trim().length == 4) Navigator.pop(ctx, c.text.trim());
            },
            child: Text(t.confirm),
          ),
        ],
      ),
    );
  }

  Future<({String code, String text})?> _askCancelReason() => showModalBottomSheet<({String code, String text})>(
        context: context,
        isScrollControlled: true,
        backgroundColor: RfColors.surface,
        builder: (_) => const _CancelSheet(),
      );

  Future<String?> _askReason(String label) {
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
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
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
    final step = current == null ? null : tripStep(current);
    final menu = current == null || current.status == 'match_pending' ? const <String>[] : _menu.where(current.allowedActions.contains).toList();
    return Scaffold(
      // Pinned in the bottom bar slot (not the body) so toasts float above the primary action instead of over it.
      bottomNavigationBar: current == null ? null : _bottomBar(current),
      appBar: AppBar(
        title: Text(step == null ? t.rideTitle : t.tripStep('$step')),
        leading: IconButton(icon: const BackButtonIcon(), onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        actions: [
          if (menu.isNotEmpty)
            PopupMenuButton<String>(
              key: const Key('tripMenu'),
              tooltip: t.tripOptions,
              enabled: !_runner.busy,
              onSelected: (a) => _transition(current!, a),
              itemBuilder: (_) => [for (final a in menu) PopupMenuItem(key: Key('action_$a'), value: a, child: Text(actionLabel(t, a)))],
            ),
        ],
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
          final s = tripStep(ride);
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(padding: const EdgeInsets.fromLTRB(RfSpace.md, 0, RfSpace.md, RfSpace.lg), children: [
              if (s != null) ...[_StepBar(step: s), const SizedBox(height: RfSpace.sm)],
              ..._map(ride, s),
              ..._stage(ride, s, units, t),
            ]),
          );
        },
      ),
    );
  }

  List<Widget> _stage(Ride ride, int? step, int units, AppLocalizations t) {
    final fare = formatMoney(ride.cashAmountMinor ?? ride.agreedFareMinor ?? ride.myBid?.amountMinor, ride.currency, units);
    final name = _riderName(ride, t);
    switch (step) {
      case 1:
        final eta = (ride.myBid?.etaSeconds ?? 0) ~/ 60;
        return [
          _Ticker(builder: (now) {
            if (!locationStopped(ref.watch(onlineControllerProvider), null, now)) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: RfSpace.sm),
              child: Banner2(key: const Key('tripLocationStopped'), icon: Icons.gps_not_fixed_rounded, text: t.locationStoppedTrip),
            );
          }),
          _StageTitle(title: t.goToRider, note: eta > 0 ? t.etaPromise(t.minutesShort('$eta')) : null),
          RfGroup(title: t.pickup, children: [
            RfRow(
              leading: RfRowIcon(Icons.radio_button_checked_rounded, color: RfColors.teal),
              title: ride.pickupLandmark,
              trailing: _mapButton(ride.pickup, t),
            ),
            ..._note(ride),
          ]),
          ..._riderCard(ride, t),
          _fareGroup(t, fare, ride),
        ];
      case 2:
        return [
          _StageTitle(title: t.waitingFor(name), note: t.atPickup, titleKey: false),
          RfGroup(title: t.waitTime, children: [
            Padding(
              padding: RfLayout.box,
              child: Center(child: _Ticker(builder: (now) => Ltr(_clock(now.difference(ride.arrivedAt ?? now)), style: RfLayout.priceBig))),
            ),
            ..._note(ride),
          ]),
          ..._riderCard(ride, t),
        ];
      case 3:
        return [
          _StageTitle(title: t.goToDestination),
          RfGroup(title: t.dropoff, children: [
            RfRow(
              leading: RfRowIcon(Icons.place_rounded, color: RfColors.gold),
              title: ride.dropoffLandmark,
              trailing: _mapButton(ride.dropoff, t),
            ),
            if (ride.dropoffNote.isNotEmpty) RfRow(titleChild: Text(t.dropoffNoteLabel(ride.dropoffNote), key: const Key('dropoffNote'), style: RfType.caption)),
          ]),
          ..._riderCard(ride, t),
          _fareGroup(t, fare, ride),
        ];
      case 4:
        return [
          const SizedBox(height: RfSpace.lg),
          Text(t.collectFrom(name), key: const Key('rideStatus'), textAlign: TextAlign.center, style: RfType.h2),
          const SizedBox(height: RfSpace.xs),
          Center(child: MoneyText(fare, style: RfLayout.priceBig)),
          const SizedBox(height: RfSpace.lg),
          _route(ride, t),
        ];
    }
    if (ride.status == 'completed') {
      return [
        Banner2(tone: Tone.success, icon: Icons.check_circle_rounded, text: t.tripFinished(fare)),
        const SizedBox(height: RfSpace.md),
        _RatingPanel(ride: ride, riderName: name, onRated: _refresh),
        const SizedBox(height: RfSpace.md),
        _route(ride, t),
      ];
    }
    return [
      Row(children: [
        Expanded(child: Text(rideStatusLabel(t, ride.status), key: const Key('rideStatus'), style: RfType.h2)),
        StatusPill(rideStatusLabel(t, ride.status), tone: toneFor(ride.status)),
      ]),
      const SizedBox(height: RfSpace.xs),
      _route(ride, t),
      if (ride.cancellation != null) ...[
        Banner2(tone: Tone.danger, icon: Icons.cancel_outlined, text: '${ride.cancellation!['reason'] ?? ''}'.isEmpty ? rideStatusLabel(t, ride.status) : '${ride.cancellation!['reason']}'),
        const SizedBox(height: RfSpace.xs),
      ],
      if (ride.agreedFareMinor != null) _fareGroup(t, fare, ride),
    ];
  }

  /// The way to the rider, then the trip with the car on it, then the arrival mark (D049). The car follows this phone's location.
  List<Widget> _map(Ride ride, int? step) {
    final map = switch (step) {
      1 => _Ticker(builder: (_) => TripMap(pickup: ride.pickup, me: _here())),
      3 => _Ticker(builder: (_) => TripMap(pickup: ride.pickup, dropoff: ride.dropoff, me: _here())),
      _ when ride.status == 'completed' => TripMap(pickup: ride.pickup, dropoff: ride.dropoff, arrived: true, height: 180),
      _ => null,
    };
    return map == null ? const [] : [map, const SizedBox(height: RfSpace.sm)];
  }

  LatLng? _here() {
    final fix = ref.read(locationServiceProvider).last;
    return fix == null ? null : LatLng(fix.lat, fix.lng);
  }

  Widget _fareGroup(AppLocalizations t, String fare, Ride ride) => RfGroup(children: [
        RfFacts([
          RfFact(t.fareCash, fare, ltr: true, color: RfColors.gold),
          RfFact(t.distanceLabel, formatDistance(ride.distanceM), ltr: true),
        ]),
      ]);

  Widget? _bottomBar(Ride ride) {
    final t = AppLocalizations.of(context);
    final action = ride.status == 'match_pending' ? null : _primary.where(ride.allowedActions.contains).firstOrNull;
    final noShow = ride.allowedActions.contains('no_show');
    final cash = tripStep(ride) == 4;
    if (action == null && !noShow && !cash) return null;
    return Container(
      padding: const EdgeInsets.fromLTRB(RfSpace.md, RfSpace.sm, RfSpace.md, RfSpace.md),
      decoration: BoxDecoration(color: RfColors.surface, border: Border(top: BorderSide(color: RfColors.line))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (noShow) _NoShowControl(ride: ride, busy: _runner.busy, onPressed: () => _transition(ride, 'no_show')),
          if (cash) RfButton(key: const Key('confirmCash'), label: t.confirmCash, kind: RfButtonKind.live, large: true, loading: _runner.busy, onPressed: () => _confirmCash(ride)),
          if (action != null)
            RfButton(
              key: Key('action_$action'),
              label: actionLabel(t, action),
              kind: action == 'complete' ? RfButtonKind.live : RfButtonKind.primary,
              large: true,
              loading: _runner.busy,
              onPressed: () => _transition(ride, action),
            ),
        ]),
      ),
    );
  }

  String _riderName(Ride ride, AppLocalizations t) {
    final name = ride.rider?.displayName ?? '';
    return name.isEmpty ? t.rider : name;
  }

  List<Widget> _note(Ride ride) => [
        if (ride.riderNote.isNotEmpty) RfRow(title: ride.riderNote, titleStyle: RfType.caption),
        if (ride.pickupNote.isNotEmpty) RfRow(titleChild: Text(AppLocalizations.of(context).pickupNoteLabel(ride.pickupNote), key: const Key('pickupNote'), style: RfType.caption)),
      ];

  Widget? _mapButton(LatLng? target, AppLocalizations t) => target == null ? null : RfCircleButton(key: const Key('openMap'), icon: Icons.near_me_rounded, tooltip: t.openInMaps, onPressed: () => _openMap(target));

  Widget _route(Ride ride, AppLocalizations t) => RfGroup(children: [
        RfStops(fromLabel: t.pickup, from: ride.pickupLandmark, toLabel: t.dropoff, to: ride.dropoffLandmark, showLabels: false),
      ]);

  List<Widget> _riderCard(Ride ride, AppLocalizations t) {
    final rider = ride.rider;
    if (rider == null) return const [];
    final name = _riderName(ride, t);
    return [
      RfGroup(title: t.rider, children: [
        RfRow(
          leading: CircleAvatar(radius: RfLayout.avatar, backgroundColor: RfColors.surfaceSunken, child: Text(name.characters.first, style: RfType.bodyStrong)),
          title: name,
          maxLines: 1,
          subChild: ride.status == 'arrived' && ride.contactAttempts > 0
              ? Text(t.contactCount('${ride.contactAttempts}'), style: RfType.caption.copyWith(color: RfColors.teal, fontWeight: FontWeight.w700))
              : Align(alignment: AlignmentDirectional.centerStart, child: RatingBadge(score: rider.ratingAvg, count: rider.ratingCount, provisional: rider.ratingProvisional, newLabel: t.newUser)),
          trailing: rider.phone == null ? null : RfCircleButton(key: const Key('callRider'), icon: Icons.phone_rounded, tooltip: t.callRider, onPressed: _runner.busy ? null : () => _callRider(ride)),
        ),
      ]),
    ];
  }
}

String _clock(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Rebuilds its child every second, for what counts up or down while the screen is open.
class _Ticker extends StatefulWidget {
  const _Ticker({required this.builder});
  final Widget Function(DateTime now) builder;
  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(DateTime.now());
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step});
  final int step;
  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 1; i <= 4; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(color: i < step ? RfColors.teal : (i == step ? RfColors.gold : RfColors.surfaceSunken), borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ],
      ]);
}

/// What to do now, in one line, with one detail under it.
class _StageTitle extends StatelessWidget {
  const _StageTitle({required this.title, this.note, this.titleKey = true});
  final String title;
  final String? note;

  /// The status key marks the instruction: the title itself, or the note when the title names the rider.
  final bool titleKey;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: RfSpace.xxs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!titleKey && note != null) Text(note!, key: const Key('rideStatus'), style: RfType.caption),
          Text(title, key: titleKey ? const Key('rideStatus') : null, style: RfType.h2),
          if (titleKey && note != null) Text(note!, style: RfType.caption),
        ]),
      );
}

/// Says what a no-show report still needs. The backend decides (`mark_no_show`); this only explains ahead of the tap.
class _NoShowControl extends StatelessWidget {
  const _NoShowControl({required this.ride, required this.busy, required this.onPressed});
  final Ride ride;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _Ticker(builder: (now) {
      final unlockAt = ride.arrivedAt?.add(Duration(seconds: ride.noShowWaitSeconds));
      final left = unlockAt?.difference(now) ?? Duration.zero;
      final blocked = ride.arrivedOutsidePickup
          ? t.noShowOutside
          : ride.arrivedWithoutLocation
              ? t.noShowNoLocation
              : left > Duration.zero
              ? t.noShowAfter(_clock(left))
              : ride.contactRequired && ride.contactAttempts < 1
                  ? t.noShowCallFirst
                  : null;
      return Padding(
        padding: const EdgeInsets.only(bottom: RfSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (blocked != null) ...[Text(blocked, textAlign: TextAlign.center, style: RfType.caption), const SizedBox(height: RfSpace.xs)],
          RfButton(key: const Key('action_no_show'), label: t.action_no_show, kind: RfButtonKind.secondary, onPressed: blocked == null && !busy ? onPressed : null),
        ]),
      );
    });
  }
}

/// Ready-made reasons so cancelling takes two taps; the chosen text is what the ride's record keeps.
class _CancelSheet extends StatefulWidget {
  const _CancelSheet();
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
    final reasons = {'rider_asked': t.cancelRiderAsked, 'car_problem': t.cancelCarProblem, 'wrong_pickup': t.cancelWrongPickup, 'other': t.cancelOther};
    final isOther = _selected == 'other';
    final reason = isOther ? _other.text.trim() : reasons[_selected] ?? '';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RfSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(t.cancelSheetTitle, style: RfType.h2),
            const SizedBox(height: 4),
            Text(t.cancelSheetNote, style: RfType.caption),
            const SizedBox(height: RfSpace.sm),
            for (final e in reasons.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: RfSpace.xs),
                child: Material(
                  color: _selected == e.key ? RfColors.text : RfColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(RfRadius.sm),
                  child: InkWell(
                    key: Key('cancelReason_${e.key}'),
                    borderRadius: BorderRadius.circular(RfRadius.sm),
                    onTap: () => setState(() => _selected = e.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: RfSpace.sm, vertical: 14),
                      child: Text(e.value, style: RfType.bodyStrong.copyWith(color: _selected == e.key ? RfColors.canvas : RfColors.text)),
                    ),
                  ),
                ),
              ),
            if (isOther)
              TextField(
                key: const Key('cancelReasonText'),
                controller: _other,
                maxLength: 300,
                autofocus: true,
                decoration: InputDecoration(hintText: t.cancelReason),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: RfSpace.xs),
            RfButton(key: const Key('confirmCancel'), label: t.action_driver_cancel, kind: RfButtonKind.danger, onPressed: reason.isEmpty ? null : () => Navigator.pop(context, (code: _selected!, text: reason))),
            const SizedBox(height: RfSpace.xs),
            RfButton(label: t.keepRide, kind: RfButtonKind.ghost, onPressed: () => Navigator.pop(context)),
          ]),
        ),
      ),
    );
  }
}

/// Rating comes after the cash (no platform custody: the driver confirms receipt directly, D002/D026).
class _RatingPanel extends ConsumerStatefulWidget {
  const _RatingPanel({required this.ride, required this.riderName, required this.onRated});
  final Ride ride;
  final String riderName;
  final VoidCallback onRated;
  @override
  ConsumerState<_RatingPanel> createState() => _RatingPanelState();
}

class _RatingPanelState extends ConsumerState<_RatingPanel> {
  final _rateKey = newActionKey();
  int _stars = 0;
  final _tags = <String>{};
  bool _sendingRating = false;
  bool _rated = false;

  static const _goodTags = ['punctual', 'polite', 'paid_smoothly', 'great_service'];
  static const _badTags = ['late', 'rude', 'wrong_location', 'price_dispute'];

  String _tagLabel(AppLocalizations t, String tag) => switch (tag) {
        'punctual' => t.tag_punctual,
        'polite' => t.tag_polite,
        'paid_smoothly' => t.tag_paid_smoothly,
        'great_service' => t.tag_great_service,
        'late' => t.tag_late,
        'rude' => t.tag_rude,
        'wrong_location' => t.tag_wrong_location,
        _ => t.tag_price_dispute,
      };

  Future<void> _sendRating(Ride r) async {
    setState(() => _sendingRating = true);
    try {
      await ref.read(driverApiProvider).rate(r.id, _stars, tags: _tags.toList(), actionKey: _rateKey);
      if (mounted) setState(() => _rated = true);
      widget.onRated();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'already_rated') {
        setState(() => _rated = true);
      } else {
        showToast(context, errorMessage(context, e), error: true);
      }
    } catch (e) {
      if (mounted) showToast(context, errorMessage(context, e), error: true);
    } finally {
      if (mounted) setState(() => _sendingRating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = widget.ride;
    if (_rated || r.myRatingStars != null) {
      return Text(t.rated, key: const Key('rated'), textAlign: TextAlign.center, style: RfType.bodyStrong.copyWith(color: RfColors.tealDeep));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t.rateQuestion(widget.riderName), textAlign: TextAlign.center, style: RfType.h2),
      const SizedBox(height: RfSpace.xs),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            key: Key('rate_$i'),
            tooltip: '$i',
            iconSize: 38,
            onPressed: () => setState(() {
              _stars = i;
              _tags.clear();
            }),
            icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: RfColors.gold),
          ),
      ]),
      if (_stars > 0) ...[
        const SizedBox(height: RfSpace.xs),
        Text(t.rateWhat, style: RfType.caption),
        const SizedBox(height: RfSpace.xs),
        Wrap(spacing: RfSpace.xs, runSpacing: RfSpace.xs, children: [
          for (final tag in _stars >= 4 ? _goodTags : _badTags)
            FilterChip(
              key: Key('tag_$tag'),
              label: Text(_tagLabel(t, tag), style: RfType.caption.copyWith(color: _tags.contains(tag) ? RfColors.canvas : RfColors.text, fontWeight: FontWeight.w700)),
              selected: _tags.contains(tag),
              showCheckmark: false,
              selectedColor: RfColors.text,
              backgroundColor: RfColors.surfaceSunken,
              side: BorderSide.none,
              onSelected: (on) => setState(() => on ? _tags.add(tag) : _tags.remove(tag)),
            ),
        ]),
        const SizedBox(height: RfSpace.sm),
        RfButton(key: const Key('sendRating'), label: t.sendRating, large: true, loading: _sendingRating, onPressed: () => _sendRating(r)),
        const SizedBox(height: RfSpace.xs),
        Text(t.ratePrivacy, style: RfType.caption),
      ],
      const SizedBox(height: RfSpace.xs),
      Text(t.rateLaterNote, textAlign: TextAlign.center, style: RfType.caption),
      RfButton(key: const Key('rateLater'), label: t.rateLater, kind: RfButtonKind.ghost, onPressed: () => context.go('/')),
    ]);
  }
}

// Keeps a stable reference for tests that pump the trip screen directly.
String tripErrorText(BuildContext context, Object e) => errorMessage(context, e);
