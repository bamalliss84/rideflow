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
