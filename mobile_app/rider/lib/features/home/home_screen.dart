import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/ride_map.dart';

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
    SavedPlace? ofKind(String kind) => places.where((p) => p.kind == kind).firstOrNull;
    void go(Place? dropoff) => context.push('/destination', extra: dropoff);
    return Stack(children: [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        bottom: 340,
        child: here == null && cities == null ? ColoredBox(color: RfColors.mapGround) : RideMap(key: ValueKey(here?.lat ?? 0), center: here ?? cities?.firstOrNull?.center, pickup: here),
      ),
      const Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(12, 10, 12, 0), child: _ProfileCard()))),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 370,
        child: Container(
          decoration: BoxDecoration(color: RfLayout.page, border: Border(top: BorderSide(color: RfColors.line)), borderRadius: const BorderRadius.vertical(top: Radius.circular(RfRadius.lg))),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 12), children: [
            if (active != null) ...[
              RfCard(
                key: const Key('activeRide'),
                color: RfColors.tealSoft,
                onTap: () => context.push('/ride/${active.id}'),
                child: Row(children: [
                  Expanded(child: Text(t.yourRide, style: RfType.bodyStrong)),
                  Text(t.open, style: RfType.bodyStrong.copyWith(color: RfColors.teal)),
                ]),
              ),
              const SizedBox(height: 8),
            ],
            Material(
              color: RfColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: RfColors.lineStrong, width: 1.5)),
              child: InkWell(
                key: const Key('whereTo'),
                borderRadius: BorderRadius.circular(12),
                onTap: active != null ? null : () => go(null),
                child: SizedBox(
                  height: 46,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [Icon(Icons.search_rounded, size: 20, color: RfColors.textMuted), const SizedBox(width: 8), Text(t.whereTo, style: RfType.body.copyWith(color: RfColors.textMuted))]),
                  ),
                ),
              ),
            ),
            RfGroup(title: t.myPlaces, plain: true, children: [
              Row(children: [
                _Tile(icon: Icons.home_rounded, color: RfColors.teal, label: ofKind('home')?.label ?? t.home_, onTap: () => ofKind('home') == null ? context.push('/places') : go(ofKind('home')!.place)),
                const SizedBox(width: 8),
                _Tile(icon: Icons.work_rounded, color: RfColors.gold, label: ofKind('work')?.label ?? t.work, onTap: () => ofKind('work') == null ? context.push('/places') : go(ofKind('work')!.place)),
                const SizedBox(width: 8),
                _Tile(icon: Icons.add_rounded, color: RfColors.text, label: t.add, onTap: () => context.push('/places')),
              ]),
            ]),
            if (recent.isNotEmpty)
              RfGroup(title: t.recent, children: [
                for (final place in recent.take(2))
                  RfRow(title: place.landmark, maxLines: 1, leading: RfRowIcon(Icons.history_rounded, color: RfColors.textMuted), onTap: active != null ? null : () => go(place)),
              ]),
          ]),
        ),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Material(
          color: RfColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: RfColors.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              height: RfLayout.compact ? 60 : 70,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                Text(label, style: RfType.caption.copyWith(color: RfColors.text, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        ),
      );
}

/// Name, day or night and the notifications, over the map (D049, model 1). Riders have no photo, so the first letter stands in.
class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final name = me?.fullName.trim() ?? '';
    final first = name.split(RegExp(r'\s+')).first;
    final night = ref.watch(appearanceProvider) == RfAppearance.night;
    final unread = ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.read).length ?? 0;
    Widget tool(Key key, IconData icon, String label, VoidCallback onTap, {int badge = 0}) => Stack(clipBehavior: Clip.none, children: [
          IconButton.filledTonal(
            key: key,
            tooltip: label,
            style: IconButton.styleFrom(backgroundColor: RfColors.surfaceSunken, minimumSize: const Size(44, 44)),
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
    return Material(
      key: const Key('profileCard'),
      color: RfColors.surface,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          DriverAvatar(name: name.isEmpty ? '؟' : name, radius: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(first.isEmpty ? t.appTitle : t.hello(first), style: RfType.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(t.homeHint, style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          tool(const Key('appearanceToggle'), night ? Icons.light_mode_outlined : Icons.dark_mode_outlined, night ? t.appearanceDay : t.appearanceNight,
              () => ref.read(appearanceProvider.notifier).set(night ? RfAppearance.day : RfAppearance.night)),
          const SizedBox(width: 6),
          tool(const Key('notifications'), Icons.notifications_none_rounded, t.notificationsTitle, () => context.push('/notifications'), badge: unread),
        ]),
      ),
    );
  }
}
