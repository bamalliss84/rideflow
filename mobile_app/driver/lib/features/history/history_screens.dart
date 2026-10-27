import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart';

/// Rides where this user is the assigned driver (candidate-only offers are on the home screen).
List<Ride> driverRides(List<Ride> rides) => rides.where((r) => r.viewerRole == 'driver').toList();

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final units = ref.watch(authProvider).valueOrNull?.minorUnits ?? 2;
    return Scaffold(
      appBar: AppBar(title: Text(t.navRides)),
      body: AsyncBody<List<Ride>>(
        value: ref.watch(ridesProvider),
        onRetry: ref.retry(ridesProvider),
        data: (all) {
          final rides = driverRides(all);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(ridesProvider),
            child: rides.isEmpty
                ? ListView(children: [EmptyView(text: t.historyEmpty, icon: Icons.route_outlined)])
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rides.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = rides[i];
                      return Card(
                        child: ListTile(
                          onTap: () => context.push('/ride/${r.id}'),
                          title: Text('${r.pickupLandmark} ${Directionality.of(context) == TextDirection.rtl ? '←' : '→'} ${r.dropoffLandmark}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(formatDateTime(r.createdAt)),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            StatusChip(rideStatusLabel(t, r.status), tone: toneFor(r.status)),
                            const SizedBox(height: 4),
                            Ltr(formatMoney(r.agreedFareMinor, r.currency, units), style: const TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

/// Sums of agreed cash fares of completed rides, computed only from the driver's own ride records.
({int count, int total}) summarize(List<Ride> rides, DateTime since) {
  var count = 0, total = 0;
  for (final r in rides) {
    if (r.viewerRole != 'driver' || r.status != 'completed' || r.completedAt == null || r.completedAt!.isBefore(since)) continue;
    count++;
    total += r.agreedFareMinor ?? 0;
  }
  return (count: count, total: total);
}

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final units = me?.minorUnits ?? 2;
    final now = DateTime.now();
    final periods = [
      (t.periodToday, DateTime(now.year, now.month, now.day)),
      (t.period7, now.subtract(const Duration(days: 7))),
      (t.period30, now.subtract(const Duration(days: 30))),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t.earningsTitle)),
      body: AsyncBody<List<Ride>>(
        value: ref.watch(ridesProvider),
        onRetry: ref.retry(ridesProvider),
        data: (rides) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(ridesProvider),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(t.earningsNote, style: const TextStyle(color: Brand.muted)),
            const SizedBox(height: 12),
            for (final (label, since) in periods)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Builder(builder: (_) {
                  final s = summarize(rides, since);
                  return SectionCard(
                    title: label,
                    child: Row(children: [
                      Expanded(child: _Metric(label: t.completedRides, value: '${s.count}')),
                      Expanded(child: _Metric(label: t.totalFares, value: formatMoney(s.total, me?.currency ?? '', units))),
                    ]),
                  );
                }),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Brand.muted, fontSize: 12)),
        const SizedBox(height: 4),
        Ltr(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Brand.navy)),
      ]);
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final value = ref.watch(notificationsProvider);
    final latest = value.valueOrNull?.firstOrNull?.cursor;
    return Scaffold(
      appBar: AppBar(title: Text(t.notificationsTitle), actions: [
        if (latest != null)
          TextButton(
            onPressed: () async {
              try {
                await ref.read(driverApiProvider).markRead(upTo: latest);
                ref.invalidate(notificationsProvider);
              } catch (e) {
                if (context.mounted) showMessage(context, errorMessage(context, e), error: true);
              }
            },
            child: Text(t.markAllRead),
          ),
      ]),
      body: AsyncBody<List<NotificationItem>>(
        value: value,
        onRetry: ref.retry(notificationsProvider),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(notificationsProvider),
          child: items.isEmpty
              ? ListView(children: [EmptyView(text: t.notificationsEmpty, icon: Icons.notifications_off_outlined)])
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = items[i];
                    final rideStatus = n.kind.startsWith('ride.') ? n.kind.substring(5) : null;
                    return ListTile(
                      tileColor: n.read ? null : Brand.tealSoft,
                      leading: Icon(n.read ? Icons.notifications_none : Icons.notifications_active, color: n.read ? Brand.muted : Brand.teal700),
                      title: Text(rideStatus != null ? '${t.notificationGeneric}: ${rideStatusLabel(t, rideStatus)}' : n.kind,
                          style: TextStyle(fontWeight: n.read ? FontWeight.normal : FontWeight.w700)),
                      subtitle: Text(formatDateTime(n.createdAt)),
                      onTap: () async {
                        if (!n.read) {
                          await ref.read(driverApiProvider).markRead(cursor: n.cursor).catchError((_) {});
                          ref.invalidate(notificationsProvider);
                        }
                        if (n.rideId != null && context.mounted) unawaitedPush(context, '/ride/${n.rideId}');
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}

void unawaitedPush(BuildContext context, String location) => context.push(location);
