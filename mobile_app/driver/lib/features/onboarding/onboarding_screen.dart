import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart';

/// Document types the backend accepts (apps/drivers DocumentType); the operator's policy decides which are required.
const documentTypes = ['national_id', 'driving_license', 'vehicle_registration', 'vehicle_photo', 'driver_photo', 'insurance'];

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.onboardingTitle)),
      body: AsyncBody<DriverProfile>(
        value: ref.watch(profileProvider),
        onRetry: ref.retry(profileProvider),
        data: (p) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(profileProvider),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _StatusCard(profile: p),
            const SizedBox(height: 12),
            const _NameCard(),
            const SizedBox(height: 12),
            _VehicleCard(profile: p),
            const SizedBox(height: 12),
            _DocumentsCard(profile: p),
            const SizedBox(height: 16),
            if (p.status == 'pending_documents' || p.status == 'rejected') _SubmitButton(),
          ]),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.profile});
  final DriverProfile profile;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SectionCard(
      title: t.applicationStatus,
      trailing: StatusChip(driverStatusLabel(t, profile.status), tone: toneFor(profile.status)),
      child: profile.reviewNote.isEmpty
          ? const SizedBox.shrink()
          : Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Brand.amberSoft, borderRadius: BorderRadius.circular(10)),
              child: Text(t.reviewNote(profile.reviewNote)),
            ),
    );
  }
}

class _NameCard extends ConsumerStatefulWidget {
  const _NameCard();
  @override
  ConsumerState<_NameCard> createState() => _NameCardState();
}

class _NameCardState extends ConsumerState<_NameCard> {
  late final TextEditingController _name = TextEditingController(text: ref.read(authProvider).valueOrNull?.fullName ?? '');
  final _runner = ActionRunner();
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SectionCard(
      title: t.profileTitle,
      child: Row(children: [
        Expanded(child: TextField(controller: _name, maxLength: 120, decoration: InputDecoration(labelText: t.fullName, counterText: ''))),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          icon: const Icon(Icons.check),
          tooltip: t.save,
          onPressed: _runner.busy || _name.text.trim().isEmpty
              ? null
              : () => _runner.run(context, () async {
                    await ref.read(driverApiProvider).updateName(_name.text.trim());
                    await ref.read(authProvider.notifier).refreshMe();
                  }, onChanged: () => setState(() {}), success: t.nameSaved),
        ),
      ]),
    );
  }
}

class _VehicleCard extends ConsumerWidget {
  const _VehicleCard({required this.profile});
  final DriverProfile profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return SectionCard(
      title: t.vehiclesTitle,
      trailing: TextButton.icon(
        icon: const Icon(Icons.add),
        label: Text(t.addVehicle),
        onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _VehicleForm()),
      ),
      child: Column(children: [
        if (profile.vehicles.isEmpty) EmptyView(text: t.docMissing, icon: Icons.directions_car_outlined),
        for (final v in profile.vehicles)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.directions_car_rounded),
            title: Text('${v.make} ${v.model} · ${v.color}'),
            subtitle: v.reviewNote.isEmpty ? Ltr(v.plate) : Text('${v.plate} — ${v.reviewNote}'),
            trailing: StatusChip(driverStatusLabel(t, v.status), tone: toneFor(v.status)),
          ),
      ]),
    );
  }
}

class _VehicleForm extends ConsumerStatefulWidget {
  const _VehicleForm();
  @override
  ConsumerState<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends ConsumerState<_VehicleForm> {
  final _plate = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  final _year = TextEditingController();
  final _runner = ActionRunner();
  final _key = newActionKey();
  ApiException? _error;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget field(TextEditingController c, String label, String name, {TextInputType? type}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: c, keyboardType: type, decoration: InputDecoration(labelText: label, errorText: _error?.fieldError(name))),
        );
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.addVehicle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        field(_plate, t.plate, 'plate_number'),
        field(_make, t.make, 'make'),
        field(_model, t.model, 'model'),
        field(_color, t.color, 'color'),
        field(_year, t.year, 'year', type: TextInputType.number),
        FilledButton(
          onPressed: _runner.busy
              ? null
              : () async {
                  if ([_plate, _make, _model, _color].any((c) => c.text.trim().isEmpty)) {
                    setState(() => _error = ApiException(400, 'invalid', errors: {
                          for (final e in {'plate_number': _plate, 'make': _make, 'model': _model, 'color': _color}.entries)
                            if (e.value.text.trim().isEmpty) e.key: [t.required],
                        }));
                    return;
                  }
                  try {
                    await ref.read(driverApiProvider).addVehicle(
                        plate: _plate.text.trim(),
                        make: _make.text.trim(),
                        model: _model.text.trim(),
                        color: _color.text.trim(),
                        year: int.tryParse(_year.text),
                        actionKey: _key);
                    ref.invalidate(profileProvider);
                    if (context.mounted) Navigator.pop(context);
                  } on ApiException catch (e) {
                    setState(() => _error = e);
                    if (e.errors == null && context.mounted) showMessage(context, errorMessage(context, e), error: true);
                  }
                },
          child: Text(t.save),
        ),
      ]),
    );
  }
}

class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard({required this.profile});
  final DriverProfile profile;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SectionCard(
      title: t.documentsTitle,
      child: Column(children: [
        for (final type in documentTypes) _DocumentRow(type: type, profile: profile),
      ]),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.type, required this.profile});
  final String type;
  final DriverProfile profile;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final docs = profile.documents.where((d) => d.docType == type).toList();
    final latest = docs.isEmpty ? null : docs.last;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(latest == null ? Icons.upload_file_rounded : Icons.description_rounded, color: latest == null ? Brand.muted : Brand.navy),
      title: Text(docTypeLabel(t, type)),
      subtitle: latest == null
          ? Text(t.docMissing)
          : Text([latest.number, latest.expiresAt, if (latest.reviewNote.isNotEmpty) latest.reviewNote].join(' · ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (latest != null) StatusChip(driverStatusLabel(t, latest.status), tone: toneFor(latest.status)),
        IconButton(
          tooltip: latest == null ? t.uploadDocument : t.replaceDocument,
          icon: const Icon(Icons.add_a_photo_outlined),
          onPressed: () {
            if (type == 'vehicle_registration' && profile.vehicles.isEmpty) {
              showMessage(context, t.needsVehicleFirst, error: true);
              return;
            }
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _UploadForm(type: type, vehicleId: type == 'vehicle_registration' ? profile.vehicles.first.id : null),
            );
          },
        ),
      ]),
    );
  }
}

class _UploadForm extends ConsumerStatefulWidget {
  const _UploadForm({required this.type, this.vehicleId});
  final String type;
  final String? vehicleId;
  @override
  ConsumerState<_UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends ConsumerState<_UploadForm> {
  final _number = TextEditingController();
  DateTime? _expiry;
  Uint8List? _bytes;
  String _filename = 'document.jpg';
  final _runner = ActionRunner();
  final _key = newActionKey();

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _bytes = bytes;
      _filename = file.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ready = _bytes != null && _number.text.trim().isNotEmpty && _expiry != null;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(docTypeLabel(t, widget.type), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(controller: _number, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t.docNumber)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(_expiry == null ? t.docExpiry : '${t.docExpiry}: ${formatDate(_expiry)}'),
          onPressed: () async {
            final now = DateTime.now();
            final d = await showDatePicker(context: context, firstDate: now, lastDate: DateTime(now.year + 20), initialDate: now.add(const Duration(days: 365)));
            if (d != null) setState(() => _expiry = d);
          },
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.photo_camera), label: Text(t.takePhoto), onPressed: () => _pick(ImageSource.camera))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.photo_library), label: Text(t.pickImage), onPressed: () => _pick(ImageSource.gallery))),
        ]),
        if (_bytes != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t.imageSelected, style: const TextStyle(color: Brand.teal700))),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: !ready || _runner.busy
              ? null
              : () async {
                  final ok = await _runner.run(
                    context,
                    () => ref.read(driverApiProvider).uploadDocument(
                          docType: widget.type,
                          number: _number.text.trim(),
                          expiresAt: _expiry!.toIso8601String().substring(0, 10),
                          bytes: _bytes!,
                          filename: _filename,
                          vehicleId: widget.vehicleId,
                          actionKey: _key,
                        ),
                    onChanged: () => setState(() {}),
                  );
                  if (ok && context.mounted) {
                    ref.invalidate(profileProvider);
                    Navigator.pop(context);
                  }
                },
          child: _runner.busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(t.uploadDocument),
        ),
      ]),
    );
  }
}

class _SubmitButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends ConsumerState<_SubmitButton> {
  final _runner = ActionRunner();
  final _key = newActionKey();
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return FilledButton(
      key: const Key('submitApplication'),
      onPressed: _runner.busy
          ? null
          : () async {
              await _runner.run(context, () => ref.read(driverApiProvider).submit(actionKey: _key), onChanged: () => setState(() {}), success: t.submitted);
              ref.invalidate(profileProvider);
              ref.invalidate(eligibilityProvider);
            },
      child: Text(t.submitApplication),
    );
  }
}
