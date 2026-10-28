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
import '../../shared/widgets.dart' show errorMessage;

enum _Outcome { pending, expired, gone }

/// The rider selected this driver's offer (`match_pending`). Full-screen, unmistakable, with the server's deadline.
/// The backend decides: `confirm` -> assigned; deadline passes -> `match_timeout` back to bidding.
class ConfirmRideScreen extends ConsumerStatefulWidget {
  const ConfirmRideScreen({super.key, required this.rideId});
  final String rideId;
  @override
  ConsumerState<ConfirmRideScreen> createState() => _ConfirmRideScreenState();
}

class _ConfirmRideScreenState extends ConsumerState<ConfirmRideScreen> {
  bool _busy = false;
  _Outcome _outcome = _Outcome.pending;
  final _keys = <String, String>{};

  /// One idempotency key per (action, version): a retried tap replays instead of confirming twice.
  String _key(String action, int version) => _keys.putIfAbsent('$action@$version', newActionKey);

  @override
  void initState() {
    super.initState();
    // This screen takes over from wherever the driver was: an older toast ("offer sent") must not cover Confirm.
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? ScaffoldMessenger.maybeOf(context)?.clearSnackBars() : null);
  }

  Future<void> _refreshOutcome() async {
    try {
      final ride = await ref.read(driverApiProvider).ride(widget.rideId);
      if (!mounted) return;
      if (ride.status == 'match_pending' && ride.viewerRole == 'driver') return;
      if (ride.isActiveForDriver) {
        context.go('/ride/${ride.id}');
        return;
      }
      setState(() => _outcome = ride.status == 'bidding' ? _Outcome.expired : _Outcome.gone);
    } catch (e) {
      if (!mounted) return;
      setState(() => _outcome = e is ApiException && e.status == 404 ? _Outcome.gone : _outcome);
    } finally {
      ref.read(pendingMatchProvider.notifier).reconcile();
    }
  }

  Future<void> _act(Ride ride, String action, {Json extra = const {}}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    try {
      final next = await ref.read(driverApiProvider).transition(ride, action, actionKey: _key(action, ride.version), extra: extra);
      ref.invalidate(rideProvider(ride.id)); // the cached snapshot is still match_pending
      ref.invalidate(ridesProvider);
      ref.invalidate(offersProvider);
      ref.read(pendingMatchProvider.notifier).reconcile();
      if (!mounted) return;
      if (action == 'confirm' && next.isActiveForDriver) {
        showToast(context, t.rideConfirmed);
        context.go('/ride/${next.id}');
      } else {
        context.go('/');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 409 || e.status == 404) {
        await _refreshOutcome(); // expired / released / changed: show why instead of a raw error
      } else {
        showToast(context, errorMessage(context, e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline(Ride ride) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.declineButton),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t.confirm, style: const TextStyle(color: RfColors.coral))),
        ],
      ),
    );
    if (ok == true) await _act(ride, 'decline', extra: {'reason': ''});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final units = ref.watch(authProvider).valueOrNull?.minorUnits ?? 2;
    final value = ref.watch(rideProvider(widget.rideId));
    return Scaffold(
      backgroundColor: RfColors.ink,
      body: SafeArea(
        child: value.when(
          loading: () => const Center(child: CircularProgressIndicator(color: RfColors.teal)),
          error: (e, _) => _Result(
            icon: Icons.wifi_off_rounded,
            title: t.errorTitle,
            body: errorMessage(context, e),
            action: RfButton(label: t.retry, kind: RfButtonKind.onInk, onPressed: () => ref.invalidate(rideProvider(widget.rideId))),
          ),
          data: (ride) {
            final stillMine = ride.status == 'match_pending' && ride.viewerRole == 'driver';
            if (_outcome == _Outcome.expired || (!stillMine && ride.status == 'bidding')) {
              return _Result(icon: Icons.timer_off_rounded, title: t.confirmExpiredTitle, body: t.confirmExpiredBody, action: RfButton(label: t.backHome, kind: RfButtonKind.onInk, onPressed: () => context.go('/')));
            }
            if (_outcome == _Outcome.gone || !stillMine) {
              if (ride.isActiveForDriver) {
                WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? context.go('/ride/${ride.id}') : null);
              }
              return _Result(icon: Icons.info_outline_rounded, title: t.confirmGoneTitle, body: t.confirmGoneBody, action: RfButton(label: t.backHome, kind: RfButtonKind.onInk, onPressed: () => context.go('/')));
            }
            final deadline = ride.matchDeadline ?? DateTime.now().add(const Duration(seconds: 60));
            final total = ride.selectedAt != null ? deadline.difference(ride.selectedAt!) : const Duration(seconds: 60);
            final fare = ride.agreedFareMinor ?? ride.myBid?.amountMinor;
            return Column(children: [
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(RfSpace.lg, RfSpace.lg, RfSpace.lg, 0), children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StatusPill(t.ride_match_pending, tone: Tone.warning, icon: Icons.notifications_active_rounded),
                  ),
                  const SizedBox(height: RfSpace.md),
                  Text(t.confirmTitle, key: const Key('confirmTitle'), style: RfType.display.copyWith(color: RfColors.onInk)),
                  const SizedBox(height: 6),
                  Text(t.confirmSubtitle, style: RfType.body.copyWith(color: RfColors.onInkMuted)),
                  const SizedBox(height: RfSpace.xl),
                  Center(
                    child: CountdownRing(
                      deadline: deadline,
                      total: total.isNegative || total == Duration.zero ? const Duration(seconds: 60) : total,
                      unitLabel: t.secondsUnit,
                      onExpired: _refreshOutcome,
                    ),
                  ),
                  const SizedBox(height: RfSpace.xl),
                  Container(
                    padding: const EdgeInsets.all(RfSpace.md),
                    decoration: BoxDecoration(color: RfColors.ink2, borderRadius: BorderRadius.circular(RfRadius.lg)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(t.agreedFare, style: RfType.caption.copyWith(color: RfColors.onInkMuted)),
                      const SizedBox(height: 4),
                      MoneyText(formatMoney(fare, ride.currency, units), style: RfType.display.copyWith(color: RfColors.onInk, fontSize: 34)),
                      const SizedBox(height: RfSpace.md),
                      const Divider(color: RfColors.ink3),
                      const SizedBox(height: RfSpace.md),
                      RouteStops(pickupLabel: t.pickup, pickup: ride.pickupLandmark, dropoffLabel: t.dropoff, dropoff: ride.dropoffLandmark, onInk: true),
                      const SizedBox(height: RfSpace.md),
                      Row(children: [
                        Expanded(child: _InkFact(label: t.distanceLabel, value: formatDistance(ride.distanceM))),
                        Expanded(child: _InkFact(label: t.etaLabel, value: ride.myBid == null ? '—' : t.minutesShort('${(ride.myBid!.etaSeconds / 60).round()}'))),
                      ]),
                    ]),
                  ),
                  if (ride.rider != null) ...[
                    const SizedBox(height: RfSpace.sm),
                    Container(
                      padding: const EdgeInsets.all(RfSpace.md),
                      decoration: BoxDecoration(color: RfColors.ink2, borderRadius: BorderRadius.circular(RfRadius.lg)),
                      child: Row(children: [
                        const CircleAvatar(backgroundColor: RfColors.ink3, child: Icon(Icons.person_rounded, color: RfColors.onInk)),
                        const SizedBox(width: RfSpace.sm),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(ride.rider!.displayName.isEmpty ? t.rider : ride.rider!.displayName, style: RfType.bodyStrong.copyWith(color: RfColors.onInk)),
                            Text(
                              ride.rider!.ratingAvg == null ? t.newRider : t.riderRating(ride.rider!.ratingAvg!.toStringAsFixed(1)),
                              style: RfType.caption.copyWith(color: RfColors.onInkMuted),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ],
                  if (ride.riderNote.isNotEmpty) ...[
                    const SizedBox(height: RfSpace.sm),
                    Text(ride.riderNote, style: RfType.body.copyWith(color: RfColors.onInkMuted)),
                  ],
                  const SizedBox(height: RfSpace.lg),
                ]),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(RfSpace.lg, RfSpace.sm, RfSpace.lg, RfSpace.md),
                child: Column(children: [
                  if (ride.allowedActions.contains('confirm'))
                    RfButton(
                      key: const Key('confirmRide'),
                      label: t.confirmButton,
                      icon: Icons.check_circle_rounded,
                      kind: RfButtonKind.go,
                      large: true,
                      loading: _busy,
                      onPressed: () => _act(ride, 'confirm'),
                    ),
                  if (ride.allowedActions.contains('decline')) ...[
                    const SizedBox(height: RfSpace.xs),
                    TextButton(
                      key: const Key('declineRide'),
                      onPressed: _busy ? null : () => _decline(ride),
                      child: Text(t.declineButton, style: RfType.bodyStrong.copyWith(color: RfColors.onInkMuted)),
                    ),
                  ],
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _InkFact extends StatelessWidget {
  const _InkFact({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: RfType.caption.copyWith(color: RfColors.onInkMuted)),
        const SizedBox(height: 2),
        Ltr(value, style: RfType.bodyStrong.copyWith(color: RfColors.onInk)),
      ]);
}

class _Result extends StatelessWidget {
  const _Result({required this.icon, required this.title, required this.body, required this.action});
  final IconData icon;
  final String title, body;
  final Widget action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(RfSpace.xl),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(icon, size: 64, color: RfColors.amber),
          const SizedBox(height: RfSpace.md),
          Text(title, key: const Key('confirmOutcome'), textAlign: TextAlign.center, style: RfType.h1.copyWith(color: RfColors.onInk)),
          const SizedBox(height: RfSpace.xs),
          Text(body, textAlign: TextAlign.center, style: RfType.body.copyWith(color: RfColors.onInkMuted)),
          const SizedBox(height: RfSpace.xl),
          action,
        ]),
      );
}
