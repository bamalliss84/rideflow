import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/labels.dart';
import '../../shared/widgets.dart' show ActionRunner, AsyncBody, errorMessage, RefRetry;

/// What each document type asks for. The backend accepts number/expiry as optional; we only ask for what is
/// meaningful for the type (no expiry on a photo, no number on a selfie). Vehicle-scoped types attach a vehicle.
class DocSpec {
  const DocSpec(this.type, {this.number = true, this.expiry = false, this.expiryRequired = false, this.vehicle = false});
  final String type;
  final bool number, expiry, expiryRequired, vehicle;
}

const docSpecs = [
  DocSpec('national_id', expiry: true),
  DocSpec('driving_license', expiry: true, expiryRequired: true),
  DocSpec('driver_photo', number: false),
  DocSpec('vehicle_registration', expiry: true, vehicle: true),
  DocSpec('insurance', expiry: true, expiryRequired: true, vehicle: true),
  DocSpec('vehicle_photo', number: false, vehicle: true),
];

/// Required types reported by the server (eligibility `documents_missing_or_expired:<types>`), falling back to
/// the commonly required set. The operator's policy decides; the app never hardcodes it as truth.
Set<String> requiredTypes(Eligibility? e) {
  for (final r in e?.reasons ?? const <String>[]) {
    if (r.startsWith('documents_missing_or_expired:')) return r.split(':').last.split(',').toSet();
  }
  return const {'national_id', 'driving_license', 'vehicle_registration'};
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final steps = [t.stepPersonal, t.stepVehicle, t.stepDocuments, t.stepSubmit];
    return Scaffold(
      appBar: AppBar(title: Text(t.onboardingTitle)),
      body: AsyncBody<DriverProfile>(
        value: ref.watch(profileProvider),
        onRetry: ref.retry(profileProvider),
        data: (p) {
          final eligibility = ref.watch(eligibilityProvider).valueOrNull;
          final pages = [
            _PersonalStep(profile: p),
            _VehicleStep(profile: p),
            _DocumentsStep(profile: p, required: requiredTypes(eligibility)),
            _SubmitStep(profile: p, required: requiredTypes(eligibility)),
          ];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(RfSpace.md, 0, RfSpace.md, RfSpace.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _StatusHeader(profile: p),
                const SizedBox(height: RfSpace.md),
                StageStepper(labels: steps, current: _step),
              ]),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(profileProvider);
                  ref.invalidate(eligibilityProvider);
                },
                child: ListView(padding: const EdgeInsets.fromLTRB(RfSpace.md, RfSpace.xs, RfSpace.md, RfSpace.lg), children: [pages[_step]]),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(RfSpace.md, RfSpace.xs, RfSpace.md, RfSpace.md),
                child: Row(children: [
                  if (_step > 0) ...[
                    Expanded(child: RfButton(label: t.back, kind: RfButtonKind.secondary, onPressed: () => setState(() => _step--))),
                    const SizedBox(width: RfSpace.sm),
                  ],
                  if (_step < steps.length - 1)
                    Expanded(child: RfButton(key: const Key('onboardingNext'), label: t.next, kind: RfButtonKind.primary, onPressed: () => setState(() => _step++))),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.profile});
  final DriverProfile profile;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t.applicationStatus, style: RfType.label)),
          StatusPill(driverStatusLabel(t, profile.status), tone: toneFor(profile.status), dot: true),
        ]),
        if (profile.reviewNote.isNotEmpty) ...[
          const SizedBox(height: RfSpace.sm),
          Banner2(text: t.reviewNote(profile.reviewNote), tone: Tone.danger, icon: Icons.feedback_outlined),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- step 1: personal

class _PersonalStep extends ConsumerStatefulWidget {
  const _PersonalStep({required this.profile});
  final DriverProfile profile;
  @override
  ConsumerState<_PersonalStep> createState() => _PersonalStepState();
}

class _PersonalStepState extends ConsumerState<_PersonalStep> {
  late final TextEditingController _name = TextEditingController(text: ref.read(authProvider).valueOrNull?.fullName ?? widget.profile.fullName);
  final _runner = ActionRunner();
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return RfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.stepPersonal, style: RfType.h3),
        const SizedBox(height: RfSpace.md),
        TextField(controller: _name, maxLength: 120, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t.fullName, counterText: '')),
        const SizedBox(height: RfSpace.md),
        InputDecorator(decoration: InputDecoration(labelText: t.phoneLabel), child: Ltr(widget.profile.phone, style: RfType.bodyStrong)),
        const SizedBox(height: RfSpace.md),
        RfButton(
          label: t.save,
          kind: RfButtonKind.secondary,
          loading: _runner.busy,
          onPressed: _name.text.trim().isEmpty
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

// ---------------------------------------------------------------- step 2: vehicle

class _VehicleStep extends ConsumerWidget {
  const _VehicleStep({required this.profile});
  final DriverProfile profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final photos = profile.documents.where((d) => d.docType == 'vehicle_photo').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final v in profile.vehicles)
        Padding(
          padding: const EdgeInsets.only(bottom: RfSpace.sm),
          child: RfCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(RfRadius.md)),
                  child: const Icon(Icons.directions_car_rounded, color: RfColors.ink),
                ),
                const SizedBox(width: RfSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${v.make} ${v.model}', style: RfType.bodyStrong),
                    Text([v.color, if (v.year != null) '${v.year}'].join(' · '), style: RfType.caption),
                  ]),
                ),
                StatusPill(driverStatusLabel(t, v.status), tone: toneFor(v.status)),
              ]),
              const SizedBox(height: RfSpace.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: RfSpace.sm, vertical: RfSpace.xs),
                decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(RfRadius.sm)),
                child: Row(children: [Text('${t.plate}: ', style: RfType.caption), Ltr(v.plate, style: RfType.bodyStrong)]),
              ),
              if (v.reviewNote.isNotEmpty) ...[const SizedBox(height: RfSpace.xs), Banner2(text: v.reviewNote, tone: Tone.danger, icon: Icons.feedback_outlined)],
              const SizedBox(height: RfSpace.sm),
              Row(children: [
                Expanded(child: Text('${t.doc_vehicle_photo}: ${photos.where((d) => d.vehicleId == v.id).length}', style: RfType.caption)),
                TextButton.icon(
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(t.uploadDocument),
                  onPressed: () => RfSheet.show<void>(context, UploadSheet(spec: docSpecs.firstWhere((s) => s.type == 'vehicle_photo'), vehicleId: v.id)),
                ),
              ]),
            ]),
          ),
        ),
      if (profile.vehicles.isEmpty) EmptyState(icon: Icons.directions_car_outlined, title: t.vehiclesTitle, message: t.needsVehicleFirst),
      RfButton(
        key: const Key('addVehicle'),
        label: t.addVehicle,
        icon: Icons.add_rounded,
        kind: profile.vehicles.isEmpty ? RfButtonKind.primary : RfButtonKind.secondary,
        onPressed: () => RfSheet.show<void>(context, const _VehicleSheet()),
      ),
    ]);
  }
}

class _VehicleSheet extends ConsumerStatefulWidget {
  const _VehicleSheet();
  @override
  ConsumerState<_VehicleSheet> createState() => _VehicleSheetState();
}

class _VehicleSheetState extends ConsumerState<_VehicleSheet> {
  final _plate = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  final _year = TextEditingController();
  final _key = newActionKey();
  bool _busy = false;
  Map<String, String> _errors = {};

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final missing = {
      for (final e in {'plate_number': _plate, 'make': _make, 'model': _model, 'color': _color}.entries)
        if (e.value.text.trim().isEmpty) e.key: t.required,
    };
    if (missing.isNotEmpty) {
      setState(() => _errors = missing);
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      await ref.read(driverApiProvider).addVehicle(
          plate: _plate.text.trim(), make: _make.text.trim(), model: _model.text.trim(), color: _color.text.trim(), year: int.tryParse(_year.text), actionKey: _key);
      ref.invalidate(profileProvider);
      ref.invalidate(eligibilityProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() => _errors = {for (final f in ['plate_number', 'make', 'model', 'color', 'year']) if (e.fieldError(f) != null) f: e.fieldError(f)!});
      if (_errors.isEmpty && mounted) showToast(context, errorMessage(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget field(TextEditingController c, String label, String name, {String? hint, TextInputType? type, bool ltr = false}) => Padding(
          padding: const EdgeInsets.only(bottom: RfSpace.md),
          child: TextField(
            controller: c,
            keyboardType: type,
            textDirection: ltr ? TextDirection.ltr : null,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: label, helperText: hint, errorText: _errors[name]),
          ),
        );
    return RfSheet(
      title: t.addVehicle,
      body: [
        field(_plate, t.plate, 'plate_number', hint: t.plateHint, ltr: true),
        field(_make, t.make, 'make'),
        field(_model, t.model, 'model'),
        field(_color, t.color, 'color'),
        field(_year, '${t.year} (${t.optionalBadge})', 'year', type: TextInputType.number, ltr: true),
      ],
      action: RfButton(key: const Key('saveVehicle'), label: t.save, kind: RfButtonKind.primary, loading: _busy, onPressed: _save),
    );
  }
}

// ---------------------------------------------------------------- step 3: documents

class _DocumentsStep extends StatelessWidget {
  const _DocumentsStep({required this.profile, required this.required});
  final DriverProfile profile;
  final Set<String> required;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Banner2(text: t.draftNote, tone: Tone.info, icon: Icons.drafts_outlined),
      const SizedBox(height: RfSpace.sm),
      for (final spec in docSpecs.where((s) => s.type != 'vehicle_photo')) _DocumentTile(spec: spec, profile: profile, required: required.contains(spec.type)),
    ]);
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.spec, required this.profile, required this.required});
  final DocSpec spec;
  final DriverProfile profile;
  final bool required;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final docs = profile.documents.where((d) => d.docType == spec.type).toList();
    final latest = docs.isEmpty ? null : docs.last;
    final needsVehicle = spec.vehicle && profile.vehicles.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: RfSpace.sm),
      child: RfCard(
        onTap: () {
          if (needsVehicle) {
            showToast(context, t.needsVehicleFirst, error: true);
            return;
          }
          RfSheet.show<void>(context, UploadSheet(spec: spec, vehicleId: spec.vehicle ? profile.vehicles.first.id : null));
        },
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: latest == null ? RfColors.surfaceSunken : RfColors.tealSoft, borderRadius: BorderRadius.circular(RfRadius.md)),
            child: Icon(latest == null ? Icons.upload_file_rounded : Icons.description_rounded, color: latest == null ? RfColors.textMuted : RfColors.tealDeep),
          ),
          const SizedBox(width: RfSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(docTypeLabel(t, spec.type), style: RfType.bodyStrong)),
                const SizedBox(width: 6),
                StatusPill(required ? t.requiredBadge : t.optionalBadge, tone: required ? Tone.dark : Tone.neutral),
              ]),
              const SizedBox(height: 2),
              Text(
                latest == null
                    ? t.docMissing
                    : [if (latest.number.isNotEmpty) latest.number, if (latest.expiresAt.isNotEmpty) latest.expiresAt].join(' · '),
                style: RfType.caption,
              ),
              if (latest != null && latest.reviewNote.isNotEmpty) Text(latest.reviewNote, style: RfType.caption.copyWith(color: RfColors.coralDeep)),
            ]),
          ),
          if (latest != null) StatusPill(driverStatusLabel(t, latest.status), tone: toneFor(latest.status)) else const Icon(Icons.chevron_left_rounded, color: RfColors.textSubtle),
        ]),
      ),
    );
  }
}

/// Upload one document: only the fields its type needs, a real photo preview, explicit progress and errors.
class UploadSheet extends ConsumerStatefulWidget {
  const UploadSheet({super.key, required this.spec, this.vehicleId});
  final DocSpec spec;
  final String? vehicleId;
  @override
  ConsumerState<UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends ConsumerState<UploadSheet> {
  final _number = TextEditingController();
  DateTime? _expiry;
  Uint8List? _bytes;
  String _filename = 'document.jpg';
  bool _busy = false;
  String? _error;
  final _key = newActionKey();

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _bytes = bytes;
        _filename = file.name;
        _error = null;
      });
    } catch (e) {
      // e.g. no camera on an emulator / permission denied: say so instead of failing silently.
      if (mounted) showToast(context, '$e', error: true);
    }
  }

  bool get _ready =>
      _bytes != null && (!widget.spec.number || _number.text.trim().isNotEmpty) && (!widget.spec.expiryRequired || _expiry != null);

  Future<void> _upload() async {
    final t = AppLocalizations.of(context);
    if (_bytes == null) {
      setState(() => _error = t.photoRequired);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(driverApiProvider).uploadDocument(
            docType: widget.spec.type,
            number: _number.text.trim(),
            expiresAt: _expiry?.toIso8601String().substring(0, 10) ?? '',
            bytes: _bytes!,
            filename: _filename,
            vehicleId: widget.vehicleId,
            actionKey: _key,
          );
      ref.invalidate(profileProvider);
      ref.invalidate(eligibilityProvider);
      if (mounted) {
        showToast(context, t.uploaded);
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.fieldError('file') ?? e.fieldError('expires_at') ?? e.fieldError('number') ?? errorMessage(context, e));
    } catch (e) {
      setState(() => _error = errorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final spec = widget.spec;
    return RfSheet(
      title: docTypeLabel(t, spec.type),
      body: [
        if (spec.number) ...[
          TextField(
            key: const Key('docNumber'),
            controller: _number,
            textDirection: TextDirection.ltr,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: t.docNumber, helperText: t.docNumberHint),
          ),
          const SizedBox(height: RfSpace.md),
        ],
        if (spec.expiry) ...[
          RfButton(
            label: _expiry == null ? (spec.expiryRequired ? t.docExpiry : t.expiryOptional) : '${t.docExpiry}: ${formatDate(_expiry)}',
            icon: Icons.event_rounded,
            kind: RfButtonKind.secondary,
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, firstDate: now, lastDate: DateTime(now.year + 20), initialDate: _expiry ?? now.add(const Duration(days: 365)));
              if (d != null) setState(() => _expiry = d);
            },
          ),
          const SizedBox(height: RfSpace.md),
        ],
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: RfColors.surfaceSunken,
            borderRadius: BorderRadius.circular(RfRadius.lg),
            border: Border.all(color: _error != null && _bytes == null ? RfColors.coral : RfColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: _bytes == null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_photo_alternate_outlined, size: 40, color: RfColors.textMuted),
                  const SizedBox(height: 6),
                  Text(t.photoRequired, style: RfType.caption),
                ]))
              : Image.memory(_bytes!, fit: BoxFit.cover, width: double.infinity),
        ),
        const SizedBox(height: RfSpace.sm),
        Row(children: [
          Expanded(child: RfButton(label: t.useCamera, icon: Icons.photo_camera_rounded, kind: RfButtonKind.secondary, onPressed: () => _pick(ImageSource.camera))),
          const SizedBox(width: RfSpace.sm),
          Expanded(child: RfButton(label: t.chooseFromGallery, icon: Icons.photo_library_rounded, kind: RfButtonKind.secondary, onPressed: () => _pick(ImageSource.gallery))),
        ]),
        if (_error != null) ...[const SizedBox(height: RfSpace.sm), Banner2(text: _error!, tone: Tone.danger, icon: Icons.error_outline_rounded)],
      ],
      action: RfButton(
        key: const Key('uploadDocument'),
        label: _busy ? t.uploading : t.uploadDocument,
        icon: Icons.cloud_upload_rounded,
        kind: RfButtonKind.primary,
        loading: _busy,
        onPressed: _ready ? _upload : null,
      ),
    );
  }
}

// ---------------------------------------------------------------- step 4: submit

class _SubmitStep extends ConsumerStatefulWidget {
  const _SubmitStep({required this.profile, required this.required});
  final DriverProfile profile;
  final Set<String> required;
  @override
  ConsumerState<_SubmitStep> createState() => _SubmitStepState();
}

class _SubmitStepState extends ConsumerState<_SubmitStep> {
  final _runner = ActionRunner();
  final _key = newActionKey();
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = widget.profile;
    if (p.status == 'under_review') return Banner2(text: t.underReviewNote, tone: Tone.info, icon: Icons.hourglass_top_rounded);
    if (p.status == 'approved') return Banner2(text: t.approvedNote, tone: Tone.success, icon: Icons.verified_rounded);
    final present = p.documents.where((d) => d.status != 'rejected').map((d) => d.docType).toSet();
    final missing = widget.required.difference(present).toList();
    final noVehicle = p.vehicles.where((v) => v.status != 'rejected').isEmpty;
    final ready = missing.isEmpty && !noVehicle;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Banner2(text: t.draftNote, tone: Tone.info, icon: Icons.drafts_outlined),
      const SizedBox(height: RfSpace.sm),
      RfCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Check(done: !noVehicle, label: t.vehiclesTitle),
          for (final type in widget.required) _Check(done: present.contains(type), label: docTypeLabel(t, type)),
        ]),
      ),
      const SizedBox(height: RfSpace.md),
      Text(ready ? t.readyToSubmit : t.missingToSubmit([if (noVehicle) t.vehiclesTitle, ...missing.map((m) => docTypeLabel(t, m))].join('، ')), style: RfType.body),
      const SizedBox(height: RfSpace.md),
      RfButton(
        key: const Key('submitApplication'),
        label: t.submitApplication,
        icon: Icons.send_rounded,
        kind: RfButtonKind.go,
        large: true,
        loading: _runner.busy,
        onPressed: ready
            ? () async {
                await _runner.run(context, () => ref.read(driverApiProvider).submit(actionKey: _key), onChanged: () => setState(() {}), success: t.submitted);
                ref.invalidate(profileProvider);
                ref.invalidate(eligibilityProvider);
              }
            : null,
      ),
    ]);
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.done, required this.label});
  final bool done;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? RfColors.teal : RfColors.lineStrong),
          const SizedBox(width: RfSpace.sm),
          Expanded(child: Text(label, style: done ? RfType.body : RfType.bodyStrong)),
        ]),
      );
}
