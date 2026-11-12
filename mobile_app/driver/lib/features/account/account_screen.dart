import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/config.dart';
import '../../core/api/api_client.dart' show newActionKey;
import '../../core/format.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/widgets.dart' show AsyncBody, EmptyView, RefRetry, StatusChip, errorMessage;

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  Future<void> _pickLayout(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<RfLayoutModel>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (model, label) in [(RfLayoutModel.a, t.layoutA), (RfLayoutModel.b, t.layoutB), (RfLayoutModel.c, t.layoutC)])
            ListTile(
              key: Key('layout_${model.name}'),
              title: Text(label, style: RfType.bodyStrong),
              trailing: ref.read(layoutProvider) == model ? Icon(Icons.check_rounded, color: RfColors.teal) : null,
              onTap: () => Navigator.pop(ctx, model),
            ),
        ]),
      ),
    );
    if (picked != null) await ref.read(layoutProvider.notifier).set(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final name = me?.fullName.isNotEmpty == true ? me!.fullName : (me?.phone ?? '');
    final layoutName = switch (ref.watch(layoutProvider)) { RfLayoutModel.a => t.layoutA, RfLayoutModel.b => t.layoutB, RfLayoutModel.c => t.layoutC };
    final chevron = Icon(Icons.chevron_left_rounded, color: RfColors.textMuted);
    return Scaffold(
      appBar: AppBar(title: Text(t.navAccount)),
      body: ListView(padding: const EdgeInsets.fromLTRB(RfSpace.md, 0, RfSpace.md, RfSpace.md), children: [
        _ProfileCard(name: name, phone: me?.phone ?? '', operator: me?.tenantName),
        RfGroup(title: t.sectionMyAccount, children: [
          RfRow(title: t.onboardingTitle, leading: const RfRowIcon(Icons.badge_outlined), trailing: chevron, onTap: () => context.push('/onboarding')),
          RfRow(title: t.subscriptionTitle, leading: const RfRowIcon(Icons.workspace_premium_outlined), trailing: chevron, onTap: () => context.push('/subscription')),
          RfRow(title: t.notificationsTitle, leading: const RfRowIcon(Icons.notifications_none_rounded), trailing: chevron, onTap: () => context.push('/notifications')),
          RfRow(key: const Key('howItWorks'), title: t.howItWorks, leading: const RfRowIcon(Icons.schedule_rounded), trailing: chevron, onTap: () => context.push('/waits')),
          RfRow(key: const Key('batteryGuide'), title: t.batteryGuide, leading: const RfRowIcon(Icons.battery_saver_rounded), trailing: chevron, onTap: () => context.push('/battery')),
        ]),
        RfGroup(title: t.trustTitle, children: [
          AsyncBody<TrustSnapshot>(
            value: ref.watch(trustProvider),
            onRetry: ref.retry(trustProvider),
            data: (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              RfFacts([
                RfFact(t.ratingAvg, s.ratingAvg == null ? '—' : s.ratingAvg!.toStringAsFixed(2), ltr: true),
                RfFact(t.ratingCount, '${s.ratingCount}', ltr: true),
                RfFact(t.completedRides, '${s.completedRides}', ltr: true),
              ]),
              Container(height: 1, color: RfLayout.softLine),
              RfFacts([
                RfFact(t.completionRate, s.completionRate == null ? '—' : '${(s.completionRate! * 100).toStringAsFixed(0)}%', ltr: true),
                RfFact(t.tier, s.tier),
              ]),
            ]),
          ),
        ]),
        RfGroup(title: t.violationsTitle, children: [
          AsyncBody<List<Violation>>(
            value: ref.watch(violationsProvider),
            onRetry: ref.retry(violationsProvider),
            data: (items) => items.isEmpty
                ? EmptyView(text: t.violationsEmpty, icon: Icons.verified_user_outlined)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final v in items) RfRow(title: v.kind, sub: formatDateTime(v.createdAt), trailing: StatusChip(v.status, tone: toneFor(v.status))),
                  ]),
          ),
        ]),
        RfGroup(title: t.sectionSettings, children: [
          RfRow(
            title: t.language,
            trailing: Text(t.switchLanguage, style: RfType.caption),
            onTap: () {
              final current = ref.read(localeProvider);
              ref.read(localeProvider.notifier).state = Locale(current.languageCode == 'ar' ? 'en' : 'ar');
            },
          ),
          RfRow(
            key: const Key('layoutRow'),
            title: t.layoutModel,
            trailing: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 170), child: Text(layoutName, style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
            onTap: () => _pickLayout(context, ref),
          ),
        ]),
        const SizedBox(height: RfSpace.xs),
        TextButton(
          key: const Key('logout'),
          onPressed: () => ref.read(authProvider.notifier).signOut(),
          child: Text(t.logout, style: RfType.bodyStrong.copyWith(color: RfColors.coral)),
        ),
        const SizedBox(height: RfSpace.xs),
        Text(t.serverLabel(AppConfig.apiBaseUrl), textAlign: TextAlign.center, style: RfType.caption.copyWith(fontSize: 11)),
      ]),
    );
  }
}

/// The driver's photo, name and operator. The photo shows to riders as soon as it is saved (D047).
class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({required this.name, required this.phone, required this.operator});
  final String name, phone;
  final String? operator;
  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  bool _busy = false;

  Future<void> _change(bool hasPhoto) async {
    final t = AppLocalizations.of(context);
    final choice = await RfSheet.show<String>(
      context,
      RfSheet(title: t.myPhoto, body: [
        RfGroup(children: [
          RfRow(key: const Key('photoCamera'), title: t.takePhoto, leading: const RfRowIcon(Icons.photo_camera_outlined), onTap: () => Navigator.pop(context, 'camera')),
          RfRow(key: const Key('photoGallery'), title: t.pickFromGallery, leading: const RfRowIcon(Icons.photo_library_outlined), onTap: () => Navigator.pop(context, 'gallery')),
          if (hasPhoto) RfRow(key: const Key('photoRemove'), title: t.removePhoto, leading: RfRowIcon(Icons.delete_outline_rounded, color: RfColors.coral), onTap: () => Navigator.pop(context, 'remove')),
        ]),
      ]),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(driverApiProvider);
      if (choice == 'remove') {
        await api.removePhoto();
      } else {
        final bytes = await ref.read(photoPickerProvider).pick(choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
        if (bytes == null) return;
        await api.setPhoto(bytes, actionKey: newActionKey());
      }
      ref.invalidate(profileProvider);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final path = ref.watch(profileProvider).valueOrNull?.photoUrl;
    final image = path == null ? null : ref.watch(photoBytesProvider(path)).valueOrNull;
    final hasPhoto = path != null;
    return RfGroup(children: [
      Padding(
        padding: const EdgeInsets.all(RfSpace.md),
        child: Column(children: [
          Semantics(
            button: true,
            label: t.myPhoto,
            child: InkWell(
              key: const Key('changePhoto'),
              customBorder: const CircleBorder(),
              onTap: _busy ? null : () => _change(hasPhoto),
              child: Stack(clipBehavior: Clip.none, children: [
                CircleAvatar(
                  key: const Key('profilePhoto'),
                  radius: 44,
                  backgroundColor: RfColors.surfaceSunken,
                  backgroundImage: image == null ? null : MemoryImage(image),
                  child: _busy
                      ? const CircularProgressIndicator()
                      : image == null
                          ? Text(widget.name.isEmpty ? '' : widget.name.characters.first, style: RfType.h1)
                          : null,
                ),
                PositionedDirectional(
                  bottom: 0,
                  end: 0,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: RfColors.gold, shape: BoxShape.circle, border: Border.all(color: RfColors.surface, width: 2)),
                    child: Icon(Icons.photo_camera_rounded, size: 15, color: RfColors.onGold),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: RfSpace.xs),
          Text(widget.name, style: RfType.h2, maxLines: 1, overflow: TextOverflow.ellipsis),
          Ltr(widget.phone, style: RfType.caption),
          if (widget.operator != null) ...[const SizedBox(height: RfSpace.xs), StatusChip(widget.operator!, tone: Tone.info)],
          const SizedBox(height: RfSpace.xs),
          Text(hasPhoto ? t.photoShownHint : t.photoAddHint, style: RfType.caption, textAlign: TextAlign.center),
          if (!hasPhoto) ...[
            const SizedBox(height: RfSpace.xs),
            RfButton(key: const Key('addPhoto'), label: t.addMyPhoto, kind: RfButtonKind.secondary, expand: false, loading: _busy, onPressed: () => _change(false)),
          ],
        ]),
      ),
    ]);
  }
}
