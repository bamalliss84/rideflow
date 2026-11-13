import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/ride_map.dart';

/// Home, direction A model 2 (D053): the greeting and the search first, saved places as chips, the map as a card with
/// the drivers around, and how many are near. Without a map the card is plain and everything else still works.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final here = ref.watch(myLocationProvider).valueOrNull;
    final cities = ref.watch(citiesProvider).valueOrNull;
    final active = ref.watch(activeRideProvider).valueOrNull;
    final places = ref.watch(placesProvider).valueOrNull ?? const <SavedPlace>[];
    final recent = ref.watch(recentPlacesProvider).valueOrNull ?? const <Place>[];
    final nearby = ref.watch(nearbyDriversProvider).valueOrNull;
    SavedPlace? ofKind(String kind) => places.where((p) => p.kind == kind).firstOrNull;
    void go(Place? dropoff) => context.push('/destination', extra: dropoff);
    final others = places.where((p) => p.kind != 'home' && p.kind != 'work');
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Header(),
          const SizedBox(height: 14),
          if (active != null) ...[
            Material(
              color: RfColors.tealSoft,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                key: const Key('activeRide'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/ride/${active.id}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    const LiveDot(),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t.yourRide, style: RfType.bodyStrong)),
                    Text(t.open, style: RfType.bodyStrong.copyWith(color: RfColors.tealDeep)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Material(
            color: RfColors.surfaceSunken,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: const Key('whereTo'),
              borderRadius: BorderRadius.circular(14),
              onTap: active != null ? null : () => go(null),
              child: SizedBox(
                height: 54,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(children: [
                    Icon(Icons.search_rounded, size: 22, color: RfColors.text),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t.whereToShort, style: RfType.h2)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _Chip(
                key: const Key('chipHome'),
                icon: Icons.home_rounded,
                label: ofKind('home')?.label ?? t.home_,
                onTap: () => ofKind('home') == null ? context.push('/places') : go(ofKind('home')!.place),
              ),
              _Chip(
                key: const Key('chipWork'),
                icon: Icons.work_rounded,
                label: ofKind('work')?.label ?? t.work,
                onTap: () => ofKind('work') == null ? context.push('/places') : go(ofKind('work')!.place),
              ),
              for (final p in others) _Chip(icon: Icons.place_rounded, label: p.label, onTap: () => go(p.place)),
              for (final p in recent.take(3)) _Chip(icon: Icons.history_rounded, label: p.landmark, onTap: active != null ? null : () => go(p)),
              _Chip(key: const Key('chipAdd'), icon: Icons.add_rounded, label: t.add, onTap: () => context.push('/places')),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              key: const Key('homeMap'),
              borderRadius: BorderRadius.circular(18),
              child: here == null && cities == null
                  ? ColoredBox(color: RfColors.mapGround, child: Center(child: Icon(Icons.map_outlined, size: 40, color: RfColors.textMuted)))
                  : RideMap(key: ValueKey(here?.lat ?? 0), center: here ?? cities?.firstOrNull?.center, pickup: here, cars: nearby?.drivers ?? const []),
            ),
          ),
          const SizedBox(height: 10),
          _Nearby(here: here, nearby: nearby),
        ]),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final name = me?.fullName.trim() ?? '';
    final first = name.split(RegExp(r'\s+')).first;
    final night = ref.watch(appearanceProvider) == RfAppearance.night;
    final unread = ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0;
    final morning = DateTime.now().hour < 12;
    Widget tool(Key key, IconData icon, String label, VoidCallback onTap, {int badge = 0}) => Stack(clipBehavior: Clip.none, children: [
          IconButton(
            key: key,
            tooltip: label,
            style: IconButton.styleFrom(backgroundColor: RfColors.surfaceSunken, minimumSize: const Size(42, 42)),
            icon: Icon(icon, size: 20, color: RfColors.text),
            onPressed: onTap,
          ),
          if (badge > 0)
            PositionedDirectional(
              top: 2,
              end: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: RfColors.coral, borderRadius: BorderRadius.circular(RfRadius.pill)),
                child: Ltr(badge > 9 ? '9+' : '$badge', style: RfType.caption.copyWith(color: RfColors.canvas, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
        ]);
    return Row(key: const Key('profileCard'), children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(morning ? t.greetingMorning : t.greetingEvening, style: RfType.caption),
          Text(first.isEmpty ? t.appTitle : first, style: RfType.display, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
      tool(const Key('appearanceToggle'), night ? Icons.light_mode_outlined : Icons.dark_mode_outlined, night ? t.appearanceDay : t.appearanceNight,
          () => ref.read(appearanceProvider.notifier).set(night ? RfAppearance.day : RfAppearance.night)),
      const SizedBox(width: 6),
      tool(const Key('notifications'), Icons.notifications_none_rounded, t.notificationsTitle, () => context.push('/notifications'), badge: unread),
      const SizedBox(width: 8),
      GestureDetector(onTap: () => context.go('/account'), child: DriverAvatar(name: name.isEmpty ? '؟' : name, radius: 22)),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Material(
          color: RfColors.surfaceSunken,
          borderRadius: BorderRadius.circular(RfRadius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(RfRadius.pill),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 17, color: RfColors.text),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(label, style: RfType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// How many drivers are near and how far the nearest is; nothing while the position is unknown.
class _Nearby extends StatelessWidget {
  const _Nearby({required this.here, required this.nearby});
  final Point? here;
  final NearbyDrivers? nearby;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final n = nearby;
    if (here == null || n == null) return const SizedBox.shrink();
    final nearest = n.drivers.isEmpty ? null : n.drivers.map((d) => metersBetween(here!, d)).reduce(math.min);
    return Container(
      key: const Key('nearbyDrivers'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        if (n.count > 0) const LiveDot() else Icon(Icons.info_outline_rounded, size: 18, color: RfColors.textMuted),
        const SizedBox(width: 10),
        Expanded(child: Text(n.count > 0 ? nearbyCount(t, n.count) : t.noDriversNearby, style: RfType.bodyStrong)),
        if (nearest != null) Text(t.nearestAway(formatDistance(nearest.round())), style: RfType.caption),
      ]),
    );
  }
}

/// "سائق واحد قريب", "سائقان قريبان", "6 سائقين قريبين", "12 سائقًا قريبًا".
String nearbyCount(AppLocalizations t, int n) {
  if (n == 1) return t.nearbyOne;
  if (n == 2) return t.nearbyTwo;
  return n <= 10 ? t.nearbyFew('$n') : t.nearbyMany('$n');
}

/// Straight-line distance; enough to say how far the nearest driver is.
double metersBetween(Point a, Point b) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// The small green dot of a live state, with its soft halo.
class LiveDot extends StatelessWidget {
  const LiveDot({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: RfColors.teal, shape: BoxShape.circle, boxShadow: [BoxShadow(color: RfColors.teal.withOpacity(0.25), spreadRadius: 4)]),
      );
}
