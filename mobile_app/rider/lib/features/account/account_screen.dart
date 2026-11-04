import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/widgets.dart' show ActionRunner, AsyncBody, errorMessage;
import '../request/map_picker.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _runner = ActionRunner();

  Future<void> _rename(String current) async {
    final t = AppLocalizations.of(context);
    final c = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.yourName),
        content: TextField(key: const Key('nameInput'), controller: c, maxLength: 60, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          TextButton(key: const Key('saveName'), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(t.save)),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await _runner.run(context, () => ref.read(authProvider.notifier).rename(name), onChanged: () => setState(() {}));
  }

  Future<void> _pickFont() async {
    final t = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: RfColors.ink2,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final family in RfFonts.available)
            ListTile(
              key: Key('font_$family'),
              title: Text(family, style: RfType.bodyStrong.copyWith(fontFamily: family)),
              trailing: ref.read(fontProvider) == family ? Icon(Icons.check_rounded, color: RfColors.teal) : null,
              onTap: () => Navigator.pop(ctx, family),
            ),
          if (!RfFonts.available.contains(RfFonts.cairo)) ListTile(enabled: false, title: Text(RfFonts.cairo, style: RfType.bodyStrong), subtitle: Text(t.fontUnavailable, style: RfType.caption)),
        ]),
      ),
    );
    if (picked != null) await ref.read(fontProvider.notifier).set(picked);
  }

  Future<void> _pickDestinationModel() async {
    final t = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: RfColors.ink2,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (model, label) in [(1, t.destinationModel1), (3, t.destinationModel3)])
            ListTile(
              key: Key('destinationModel_$model'),
              title: Text(label, style: RfType.bodyStrong),
              trailing: ref.read(destinationModelProvider) == model ? Icon(Icons.check_rounded, color: RfColors.teal) : null,
              onTap: () => Navigator.pop(ctx, model),
            ),
        ]),
      ),
    );
    if (picked != null) await ref.read(destinationModelProvider.notifier).set(picked);
  }

  Future<void> _pickAppearance() async {
    final t = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<RfAppearance>(
      context: context,
      backgroundColor: RfColors.ink2,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (mode, label) in [(RfAppearance.day, t.appearanceDay), (RfAppearance.night, t.appearanceNight)])
            ListTile(
              key: Key('appearance_${mode.name}'),
              title: Text(label, style: RfType.bodyStrong),
              trailing: ref.read(appearanceProvider) == mode ? Icon(Icons.check_rounded, color: RfColors.teal) : null,
              onTap: () => Navigator.pop(ctx, mode),
            ),
        ]),
      ),
    );
    if (picked != null) await ref.read(appearanceProvider.notifier).set(picked);
  }

  Future<void> _pickLayout() async {
    final t = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<RfLayoutModel>(
      context: context,
      backgroundColor: RfColors.ink2,
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

  Future<void> _delete(String phone) async {
    final deleted = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, backgroundColor: RfColors.ink2, builder: (_) => _DeleteSheet(phone: phone));
    if (deleted == true) await ref.read(authProvider.notifier).afterAccountDeleted();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(authProvider).valueOrNull;
    final rating = ref.watch(myRatingProvider).valueOrNull;
    final name = me?.fullName ?? '';
    final layoutName = switch (ref.watch(layoutProvider)) { RfLayoutModel.a => t.layoutA, RfLayoutModel.b => t.layoutB, RfLayoutModel.c => t.layoutC };
    final chevron = Icon(Icons.chevron_left_rounded, color: RfColors.textMuted);
    Widget row(String title, {String? value, VoidCallback? onTap, Widget? trailing, Key? key}) => RfRow(
          key: key,
          title: title,
          trailing: trailing ?? (value == null ? null : ConstrainedBox(constraints: const BoxConstraints(maxWidth: 170), child: Text(value, style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis))),
          onTap: onTap,
        );
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
        Text(t.navAccount, style: RfType.h1),
        const SizedBox(height: 8),
        RfGroup(children: [
          RfRow(
            leading: DriverAvatar(name: name.isEmpty ? '؟' : name, radius: RfLayout.avatar),
            title: name,
            subChild: Ltr(me?.phone ?? '', style: RfType.caption),
            maxLines: 1,
            trailing: TextButton(key: const Key('editName'), onPressed: () => _rename(name), child: Text(t.edit)),
          ),
        ]),
        RfGroup(title: t.sectionActivity, children: [
          row(t.myPlaces, key: const Key('myPlaces'), onTap: () => context.push('/places'), trailing: chevron),
          if (rating != null)
            RfRow(
              title: t.yourRating,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.star_rounded, color: RfColors.gold, size: 16), const SizedBox(width: 4), Text(rating.toStringAsFixed(1), style: RfType.bodyStrong)]),
            ),
        ]),
        RfGroup(title: t.sectionSettings, children: [
          row(t.alwaysCode, trailing: Switch(key: const Key('alwaysCode'), value: ref.watch(alwaysCodeProvider), activeTrackColor: RfColors.teal, onChanged: (v) => ref.read(alwaysCodeProvider.notifier).set(v))),
          row(t.appearance, value: ref.watch(appearanceProvider) == RfAppearance.night ? t.appearanceNight : t.appearanceDay, key: const Key('appearanceRow'), onTap: _pickAppearance),
          row(t.layoutModel, value: layoutName, key: const Key('layoutRow'), onTap: _pickLayout),
          row(t.language, value: t.languageName, key: const Key('language'), onTap: () {
            final current = ref.read(localeProvider);
            ref.read(localeProvider.notifier).state = Locale(current.languageCode == 'ar' ? 'en' : 'ar');
          }),
          row(t.fontKind, value: ref.watch(fontProvider), key: const Key('fontRow'), onTap: _pickFont),
          row(t.destinationModel, value: ref.watch(destinationModelProvider) == 3 ? t.destinationModel3 : t.destinationModel1, key: const Key('destinationModelRow'), onTap: _pickDestinationModel),
        ]),
        RfGroup(title: t.sectionSupport, children: [
          row(t.help, onTap: () => showToast(context, t.notReady), trailing: chevron),
          row(t.terms, onTap: () => showToast(context, t.notReady), trailing: chevron),
        ]),
        const SizedBox(height: 8),
        TextButton(key: const Key('logout'), onPressed: _runner.busy ? null : () => ref.read(authProvider.notifier).signOut(), child: Text(t.logout, style: RfType.bodyStrong)),
        TextButton(key: const Key('deleteAccount'), onPressed: () => _delete(me?.phone ?? ''), child: Text(t.deleteAccount, style: RfType.bodyStrong.copyWith(color: RfColors.coral))),
      ]),
    );
  }
}

class _DeleteSheet extends ConsumerStatefulWidget {
  const _DeleteSheet({required this.phone});
  final String phone;
  @override
  ConsumerState<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends ConsumerState<_DeleteSheet> {
  final _code = TextEditingController();
  bool _sent = false, _busy = false;
  Object? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.deleteTitle, style: RfType.h2),
            const SizedBox(height: 6),
            Text(t.deleteNote, style: RfType.caption.copyWith(height: 1.6)),
            const SizedBox(height: 14),
            if (_sent) ...[
              TextField(key: const Key('deleteCode'), controller: _code, keyboardType: TextInputType.number, textDirection: TextDirection.ltr, textAlign: TextAlign.center, decoration: InputDecoration(labelText: t.codeLabel)),
              const SizedBox(height: 12),
              RfButton(
                key: const Key('confirmDelete'),
                label: t.confirmDelete,
                kind: RfButtonKind.danger,
                loading: _busy,
                onPressed: () => _run(() async {
                  await ref.read(riderApiProvider).deleteAccount(_code.text.trim());
                  if (context.mounted) Navigator.pop(context, true);
                }),
              ),
            ] else
              RfButton(
                key: const Key('sendDeleteCode'),
                label: t.sendDeleteCode,
                kind: RfButtonKind.danger,
                loading: _busy,
                onPressed: () => _run(() async {
                  await ref.read(riderApiProvider).requestOtp(widget.phone);
                  setState(() => _sent = true);
                }),
              ),
            if (_error != null) ...[const SizedBox(height: 10), Text(errorMessage(context, _error!), style: RfType.caption.copyWith(color: RfColors.coral))],
            RfButton(label: t.back, kind: RfButtonKind.ghost, onPressed: () => Navigator.pop(context, false)),
          ]),
        ),
      ),
    );
  }
}

class PlacesScreen extends ConsumerStatefulWidget {
  const PlacesScreen({super.key});
  @override
  ConsumerState<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends ConsumerState<PlacesScreen> {
  final _runner = ActionRunner();

  Future<void> _add(String kind, String label) async {
    final t = AppLocalizations.of(context);
    final center = ref.read(myLocationProvider).valueOrNull ?? ref.read(citiesProvider).valueOrNull?.firstOrNull?.center;
    final place = await pickOnMap(context, center: center);
    if (place == null || !mounted) return;
    var name = label;
    if (kind == 'other') {
      final c = TextEditingController(text: place.landmark);
      final typed = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.placeLabel),
          content: TextField(key: const Key('labelInput'), controller: c, maxLength: 60),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            TextButton(key: const Key('saveLabel'), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(t.save)),
          ],
        ),
      );
      if (typed == null || typed.isEmpty || !mounted) return;
      name = typed;
    }
    await _runner.run(context, () => ref.read(riderApiProvider).addPlace(kind: kind, label: name, place: place), onChanged: () => setState(() {}));
    ref.invalidate(placesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.myPlaces), leading: const BackButton()),
      body: AsyncBody<List<SavedPlace>>(
        value: ref.watch(placesProvider),
        onRetry: () => ref.invalidate(placesProvider),
        data: (places) {
          final has = places.map((p) => p.kind).toSet();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
            if (places.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(t.placesEmpty, textAlign: TextAlign.center, style: RfType.caption)),
            for (final p in places)
              Padding(
                padding: EdgeInsets.only(bottom: RfLayout.listGap),
                child: RfCard(
                  key: Key('place_${p.id}'),
                  inList: true,
                  padding: EdgeInsets.zero,
                  child: RfRow(
                    title: p.label,
                    sub: p.landmark,
                    maxLines: 1,
                    trailing: IconButton(
                      key: Key('removePlace_${p.id}'),
                      tooltip: t.cancel,
                      icon: Icon(Icons.delete_outline_rounded, color: RfColors.coral),
                      onPressed: () async {
                        await _runner.run(context, () => ref.read(riderApiProvider).deletePlace(p.id), onChanged: () => setState(() {}));
                        ref.invalidate(placesProvider);
                      },
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 10),
            if (!has.contains('home')) ...[RfButton(key: const Key('addHome'), label: t.home_, icon: Icons.home_rounded, kind: RfButtonKind.secondary, onPressed: () => _add('home', t.home_)), const SizedBox(height: 8)],
            if (!has.contains('work')) ...[RfButton(key: const Key('addWork'), label: t.work, icon: Icons.work_rounded, kind: RfButtonKind.secondary, onPressed: () => _add('work', t.work)), const SizedBox(height: 8)],
            RfButton(key: const Key('addOther'), label: t.otherPlace, icon: Icons.add_rounded, kind: RfButtonKind.secondary, onPressed: () => _add('other', '')),
          ]);
        },
      ),
    );
  }
}
