import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../shared/widgets.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(t.navAccount)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Brand.navy, child: Icon(Icons.person, color: Colors.white)),
            title: Text(me?.fullName.isNotEmpty == true ? me!.fullName : (me?.phone ?? '')),
            subtitle: Ltr(me?.phone ?? ''),
            trailing: me?.tenantName != null ? StatusChip(me!.tenantName!, tone: Tone.info) : null,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(leading: const Icon(Icons.badge_outlined), title: Text(t.onboardingTitle), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/onboarding')),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.workspace_premium_outlined), title: Text(t.subscriptionTitle), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/subscription')),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.notifications_none_rounded), title: Text(t.notificationsTitle), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/notifications')),
          ]),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: t.trustTitle,
          child: AsyncBody<TrustSnapshot>(
            value: ref.watch(trustProvider),
            onRetry: ref.retry(trustProvider),
            data: (s) => Wrap(spacing: 24, runSpacing: 12, children: [
              _Kv(t.ratingAvg, s.ratingAvg == null ? '—' : s.ratingAvg!.toStringAsFixed(2)),
              _Kv(t.ratingCount, '${s.ratingCount}'),
              _Kv(t.completedRides, '${s.completedRides}'),
              _Kv(t.completionRate, s.completionRate == null ? '—' : '${(s.completionRate! * 100).toStringAsFixed(0)}%'),
              _Kv(t.tier, s.tier),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: t.violationsTitle,
          child: AsyncBody<List<Violation>>(
            value: ref.watch(violationsProvider),
            onRetry: ref.retry(violationsProvider),
            data: (items) => items.isEmpty
                ? EmptyView(text: t.violationsEmpty, icon: Icons.verified_user_outlined)
                : Column(children: [
                    for (final v in items)
                      ListTile(contentPadding: EdgeInsets.zero, title: Text(v.kind), subtitle: Text(formatDateTime(v.createdAt)), trailing: StatusChip(v.status, tone: toneFor(v.status))),
                  ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.translate),
              title: Text(t.language),
              trailing: Text(t.switchLanguage),
              onTap: () {
                final current = ref.read(localeProvider);
                ref.read(localeProvider.notifier).state = Locale(current.languageCode == 'ar' ? 'en' : 'ar');
              },
            ),
            const Divider(height: 1),
            ListTile(
              key: const Key('logout'),
              leading: const Icon(Icons.logout, color: Brand.coral),
              title: Text(t.logout, style: const TextStyle(color: Brand.coral)),
              onTap: () => ref.read(authProvider.notifier).signOut(),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text(t.serverLabel(AppConfig.apiBaseUrl), textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted, fontSize: 11)),
      ]),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: Brand.muted, fontSize: 12)),
        Ltr(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ]);
}
