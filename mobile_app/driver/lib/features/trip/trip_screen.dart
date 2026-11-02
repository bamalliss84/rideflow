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

  Future<void> _transition(Ride ride, String action) async {
    final t = AppLocalizations.of(context);
    final api = ref.read(driverApiProvider);
    Json extra = {};
    if (action == 'driver_cancel' || action == 'decline') {
      final reason = action == 'decline' ? await _askReason(t.declineReason) : await _askCancelReason();
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

  Future<String?> _askCancelReason() => showModalBottomSheet<String>(
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
              if (s != null) ...[_StepBar(step: s), const SizedBox(height: RfSpace.lg)],
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
          _Destination(caption: t.goToRider, place: ride.pickupLandmark, pickup: true),
          if (eta > 0) ...[const SizedBox(height: RfSpace.xs), Text(t.etaPromise(t.minutesShort('$eta')), style: RfType.body.copyWith(color: RfColors.textMuted))],
          ..._note(ride),
          ..._mapButton(ride.pickup, t),
          ..._riderCard(ride, t),
          _FareLine(label: '${t.fareCash} · ${formatDistance(ride.distanceM)}', fare: fare),
        ];
      case 2:
        return [
          Text(t.atPickup, key: const Key('rideStatus'), style: RfType.body.copyWith(color: RfColors.textMuted)),
          const SizedBox(height: RfSpace.xs),
          Text(t.waitingFor(name), style: RfType.h1),
          const SizedBox(height: RfSpace.md),
          RfCard(
            child: Column(children: [
              Text(t.waitTime, style: RfType.body.copyWith(color: RfColors.textMuted)),
              _Ticker(builder: (now) => Ltr(_clock(now.difference(ride.arrivedAt ?? now)), style: RfType.display.copyWith(fontSize: 34, color: RfColors.gold))),
            ]),
          ),
          ..._note(ride),
          ..._riderCard(ride, t),
        ];
      case 3:
        return [
          _Destination(caption: t.goToDestination, place: ride.dropoffLandmark, pickup: false),
          const SizedBox(height: RfSpace.xs),
          Text(t.tripDistance(formatDistance(ride.distanceM)), style: RfType.body.copyWith(color: RfColors.textMuted)),
          ..._mapButton(ride.dropoff, t),
          ..._riderCard(ride, t),
          _FareLine(label: t.fareCash, fare: fare),
        ];
      case 4:
        return [
          const SizedBox(height: RfSpace.xxl),
          Text(t.collectFrom(name), key: const Key('rideStatus'), textAlign: TextAlign.center, style: RfType.h2),
          const SizedBox(height: RfSpace.sm),
          Center(child: MoneyText(fare, style: RfType.display.copyWith(fontSize: 42, color: RfColors.gold))),
          const SizedBox(height: RfSpace.xl),
          _route(ride, t),
        ];
    }
    if (ride.status == 'completed') {
      return [
        Banner2(tone: Tone.success, icon: Icons.check_circle_rounded, text: t.tripFinished(fare)),
        const SizedBox(height: RfSpace.lg),
        _RatingPanel(ride: ride, riderName: name, onRated: _refresh),
        const SizedBox(height: RfSpace.lg),
        _route(ride, t),
      ];
    }
    return [
      Row(children: [
        Expanded(child: Text(rideStatusLabel(t, ride.status), key: const Key('rideStatus'), style: RfType.h1)),
        StatusPill(rideStatusLabel(t, ride.status), tone: toneFor(ride.status)),
      ]),
      const SizedBox(height: RfSpace.md),
      _route(ride, t),
      if (ride.cancellation != null) ...[
        const SizedBox(height: RfSpace.sm),
        Banner2(tone: Tone.danger, icon: Icons.cancel_outlined, text: '${ride.cancellation!['reason'] ?? ''}'.isEmpty ? rideStatusLabel(t, ride.status) : '${ride.cancellation!['reason']}'),
      ],
      if (ride.agreedFareMinor != null) _FareLine(label: t.fareCash, fare: fare),
    ];
  }

  Widget? _bottomBar(Ride ride) {
    final t = AppLocalizations.of(context);
    final action = ride.status == 'match_pending' ? null : _primary.where(ride.allowedActions.contains).firstOrNull;
    final noShow = ride.allowedActions.contains('no_show');
    final cash = tripStep(ride) == 4;
    if (action == null && !noShow && !cash) return null;
    return Container(
      padding: const EdgeInsets.fromLTRB(RfSpace.md, RfSpace.sm, RfSpace.md, RfSpace.md),
      decoration: const BoxDecoration(color: RfColors.surface, border: Border(top: BorderSide(color: RfColors.line))),
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
        if (ride.riderNote.isNotEmpty) ...[const SizedBox(height: RfSpace.sm), Banner2(text: ride.riderNote, tone: Tone.info, icon: Icons.sticky_note_2_outlined)],
      ];

  List<Widget> _mapButton(LatLng? target, AppLocalizations t) => [
        if (target != null) ...[
          const SizedBox(height: RfSpace.sm),
          RfButton(key: const Key('openMap'), label: t.openInMaps, icon: Icons.near_me_rounded, kind: RfButtonKind.secondary, onPressed: () => _openMap(target)),
        ],
      ];

  Widget _route(Ride ride, AppLocalizations t) => RfCard(
        child: RouteStops(pickupLabel: t.pickup, pickup: ride.pickupLandmark, dropoffLabel: t.dropoff, dropoff: ride.dropoffLandmark, dense: true, showLabels: false),
      );

  List<Widget> _riderCard(Ride ride, AppLocalizations t) {
    final rider = ride.rider;
    if (rider == null) return const [];
    final name = _riderName(ride, t);
    return [
      const SizedBox(height: RfSpace.md),
      RfCard(
        padding: const EdgeInsets.all(RfSpace.sm),
        child: Row(children: [
          CircleAvatar(radius: 18, backgroundColor: RfColors.surfaceSunken, child: Text(name.characters.first, style: RfType.bodyStrong)),
          const SizedBox(width: RfSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: RfType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              if (ride.status == 'arrived' && ride.contactAttempts > 0)
                Text(t.contactCount('${ride.contactAttempts}'), style: RfType.caption.copyWith(color: RfColors.teal, fontWeight: FontWeight.w700))
              else
                RatingBadge(score: rider.ratingAvg, count: rider.ratingCount, provisional: rider.ratingProvisional, newLabel: t.newUser),
            ]),
          ),
          if (rider.phone != null)
            RfButton(key: const Key('callRider'), label: t.callRider, icon: Icons.phone_rounded, kind: RfButtonKind.live, expand: false, onPressed: _runner.busy ? null : () => _callRider(ride)),
        ]),
      ),
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

class _Destination extends StatelessWidget {
  const _Destination({required this.caption, required this.place, required this.pickup});
  final String caption, place;
  final bool pickup;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(caption, key: const Key('rideStatus'), style: RfType.body.copyWith(color: RfColors.textMuted)),
        const SizedBox(height: RfSpace.xs),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          pickup ? const Icon(Icons.radio_button_checked_rounded, size: 26, color: RfColors.teal) : const Icon(Icons.place_rounded, size: 26, color: RfColors.gold),
          const SizedBox(width: RfSpace.xs),
          Expanded(child: Text(place, style: RfType.h1)),
        ]),
      ]);
}

class _FareLine extends StatelessWidget {
  const _FareLine({required this.label, required this.fare});
  final String label, fare;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(RfSpace.xxs, RfSpace.sm, RfSpace.xxs, 0),
        child: Row(children: [
          Expanded(child: Text(label, style: RfType.body.copyWith(color: RfColors.textMuted))),
          MoneyText(fare, style: RfType.h2.copyWith(color: RfColors.gold)),
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
    final reasons = {'rider': t.cancelRiderAsked, 'car': t.cancelCarProblem, 'pickup': t.cancelWrongPickup, 'other': t.cancelOther};
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
            RfButton(key: const Key('confirmCancel'), label: t.action_driver_cancel, kind: RfButtonKind.danger, onPressed: reason.isEmpty ? null : () => Navigator.pop(context, reason)),
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
