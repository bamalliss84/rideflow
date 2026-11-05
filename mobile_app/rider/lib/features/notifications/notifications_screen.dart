import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/widgets.dart' show AsyncBody, EmptyView;

String notificationText(AppLocalizations t, String kind) => switch (kind) {
      'ride.bid_created' => t.noteOffer,
      'ride.assigned' => t.noteAssigned,
      'ride.match_released' => t.noteReleased,
      'ride.en_route' => t.noteEnRoute,
      'ride.driver_arrived' => t.noteArrived,
      'ride.driver_waiting' => t.noteWaiting,
      'ride.started' => t.noteStarted,
      'ride.completed' => t.noteCompleted,
      'ride.cancelled' => t.noteCancelled,
      'ride.expired' => t.noteExpired,
      'ride.no_show_recorded' => t.noteNoShow,
      _ => t.noteGeneric,
    };

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, NotificationItem n) async {
    if (!n.read) {
      try {
        await ref.read(riderApiProvider).markRead(cursor: n.cursor);
      } catch (_) {}
      ref.invalidate(notificationsProvider);
    }
    if (n.rideId != null && context.mounted) await context.push('/ride/${n.rideId}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final value = ref.watch(notificationsProvider);
    final latest = value.valueOrNull?.firstOrNull?.cursor;
    final unread = value.valueOrNull?.any((n) => !n.read) ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(t.notificationsTitle), leading: const BackButton(), actions: [
        if (latest != null && unread)
          TextButton(
            key: const Key('markAllRead'),
            onPressed: () async {
              try {
                await ref.read(riderApiProvider).markRead(upTo: latest);
              } catch (_) {}
              ref.invalidate(notificationsProvider);
            },
            child: Text(t.markAllRead),
          ),
      ]),
      body: AsyncBody<List<NotificationItem>>(
        value: value,
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(notificationsProvider),
          child: items.isEmpty
              ? ListView(children: [EmptyView(text: t.notificationsEmpty, icon: Icons.notifications_off_outlined)])
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                  RfGroup(children: [
                    for (final n in items)
                      RfRow(
                        key: Key('note_${n.cursor}'),
                        leading: RfRowIcon(n.read ? Icons.notifications_none_rounded : Icons.notifications_active_rounded, color: n.read ? RfColors.textMuted : RfColors.teal),
                        title: notificationText(t, n.kind),
                        titleStyle: n.read ? RfType.body : RfType.bodyStrong,
                        sub: formatDateTime(n.createdAt),
                        onTap: () => _open(context, ref, n),
                      ),
                  ]),
                ]),
        ),
      ),
    );
  }
}
