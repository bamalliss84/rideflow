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
          decoration: BoxDecoration(color: RfColors.ink2, border: Border(top: BorderSide(color: RfColors.line)), borderRadius: const BorderRadius.vertical(top: Radius.circular(RfRadius.xl))),
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 12), children: [
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
              const SizedBox(height: 12),
            ],
            Material(
              color: RfColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RfRadius.pill), side: BorderSide(color: RfColors.teal, width: 1.5)),
              child: InkWell(
                key: const Key('whereTo'),
                borderRadius: BorderRadius.circular(RfRadius.pill),
                onTap: active != null ? null : () => go(null),
                child: SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [Icon(Icons.search_rounded, color: RfColors.text), const SizedBox(width: 10), Text(t.whereTo, style: RfType.bodyStrong)]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _Tile(icon: Icons.home_rounded, color: RfColors.teal, label: ofKind('home')?.label ?? t.home_, onTap: () => ofKind('home') == null ? context.push('/places') : go(ofKind('home')!.place)),
              const SizedBox(width: 10),
              _Tile(icon: Icons.work_rounded, color: RfColors.gold, label: ofKind('work')?.label ?? t.work, onTap: () => ofKind('work') == null ? context.push('/places') : go(ofKind('work')!.place)),
              const SizedBox(width: 10),
              _Tile(icon: Icons.add_rounded, color: RfColors.text, label: t.add, onTap: () => context.push('/places')),
            ]),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(t.recent, style: RfType.h3),
              const SizedBox(height: 8),
              for (final place in recent.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RfCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    onTap: active != null ? null : () => go(place),
                    child: Row(children: [
                      Icon(Icons.history_rounded, color: RfColors.textMuted, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(place.landmark, style: RfType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ),
            ],
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
          borderRadius: BorderRadius.circular(RfRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(RfRadius.md),
            onTap: onTap,
            child: SizedBox(
              height: 70,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(label, style: RfType.caption.copyWith(color: RfColors.text, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        ),
      );
}
