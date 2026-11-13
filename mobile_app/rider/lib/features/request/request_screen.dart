import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/ride_map.dart';
import '../../shared/widgets.dart' show ActionRunner, AsyncBody;

/// Default price step: 50 whole currency units. A ride's own snapshot carries the operator's step once it exists.
int defaultStepMinor(int minorUnits) {
  var step = 50;
  for (var i = 0; i < minorUnits; i++) {
    step *= 10;
  }
  return step;
}

/// Confirm the request (direction A, screen 3): the route on the map, the expected range large, the optional price on
/// one line, cash and a note for the driver as chips, one button.
class RequestScreen extends ConsumerStatefulWidget {
  const RequestScreen({super.key, required this.draft});
  final RideDraft draft;
  @override
  ConsumerState<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends ConsumerState<RequestScreen> {
  final _runner = ActionRunner();
  final _key = newActionKey(); // a retried request replays instead of creating a second ride
  late final _pickupNote = TextEditingController(text: widget.draft.pickupNote);
  late final _dropoffNote = TextEditingController(text: widget.draft.dropoffNote);
  late bool _code = widget.draft.requireCode;
  int? _price;

  @override
  void initState() {
    super.initState();
    _price = widget.draft.priceMinor;
  }

  @override
  void dispose() {
    _pickupNote.dispose();
    _dropoffNote.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final draft = widget.draft;
    Ride? ride;
    await _runner.run(context, () async {
      ride = await ref.read(riderApiProvider).createRide(
            RideDraft(pickup: draft.pickup, dropoff: draft.dropoff, pickupNote: _pickupNote.text.trim(), dropoffNote: _dropoffNote.text.trim(), requireCode: _code, priceMinor: _price),
            actionKey: _key,
          );
    }, onChanged: () => setState(() {}));
    if (ride == null || !mounted) return;
    ref.invalidate(ridesProvider);
    context.go('/ride/${ride!.id}');
  }

  Future<void> _notes() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RfColors.canvas,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) {
          final t = AppLocalizations.of(context);
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(t.sectionNotes, style: RfType.h2),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('pickupNote'),
                  controller: _pickupNote,
                  maxLength: 300,
                  decoration: InputDecoration(hintText: t.pickupNoteHint, counterText: '', prefixIcon: Icon(Icons.radio_button_checked_rounded, color: RfColors.teal, size: 18)),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('dropoffNote'),
                  controller: _dropoffNote,
                  maxLength: 300,
                  decoration: InputDecoration(hintText: t.dropoffNoteHint, counterText: '', prefixIcon: Icon(Icons.square_rounded, color: RfColors.text, size: 14)),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  key: const Key('codeSwitch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.startCodeTitle, style: RfType.bodyStrong),
                  subtitle: Text(_code ? t.on_ : t.off_, style: RfType.caption),
                  value: _code,
                  activeTrackColor: RfColors.teal,
                  onChanged: (v) {
                    setSheet(() {});
                    setState(() => _code = v);
                  },
                ),
                const SizedBox(height: 8),
                RfButton(key: const Key('notesDone'), label: t.done, onPressed: () => Navigator.pop(context)),
              ]),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final units = ref.watch(authProvider).valueOrNull?.minorUnits ?? 2;
    final value = ref.watch(estimateProvider(widget.draft));
    final d = widget.draft;
    final noted = _pickupNote.text.trim().isNotEmpty || _dropoffNote.text.trim().isNotEmpty || _code;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(bottom: 300, child: RideMap(pickup: d.pickup.point, dropoff: d.dropoff.point)),
        PositionedDirectional(
          top: 0,
          start: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: RfColors.canvas,
                shape: const CircleBorder(),
                elevation: 2,
                child: IconButton(icon: Icon(Icons.arrow_back_rounded, color: RfColors.text), tooltip: MaterialLocalizations.of(context).backButtonTooltip, onPressed: () => context.pop()),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
            decoration: BoxDecoration(
              color: RfColors.canvas,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 30, offset: Offset(0, -8))],
            ),
            child: SafeArea(
              top: false,
              child: AsyncBody<Estimate>(
                value: value,
                onRetry: () => ref.invalidate(estimateProvider(widget.draft)),
                data: (e) {
                  String money(int? v) => formatMoney(v, e.currency, units);
                  final range = '${formatMoney(e.minMinor, '', units)} – ${money(e.maxMinor)}';
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: RfColors.line, borderRadius: BorderRadius.circular(4)))),
                      const SizedBox(height: 12),
                      RouteStops(pickupLabel: t.from, pickup: d.pickup.landmark, dropoffLabel: t.to, dropoff: d.dropoff.landmark, dense: true, showLabels: false),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Container(height: 1, color: RfColors.line)),
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.estimate, style: RfType.caption),
                            FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: MoneyText(range, key: const Key('estimateRange'), style: RfLayout.priceBig)),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(color: RfColors.surfaceSunken, borderRadius: BorderRadius.circular(RfRadius.pill)),
                          child: Ltr(formatDistance(e.distanceM), style: RfType.bodyStrong),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Material(
                        color: RfColors.surfaceSunken,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          key: const Key('addPrice'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            final picked = await showPriceSheet(context, start: _price ?? e.riderMinMinor, minimum: e.riderMinMinor, step: defaultStepMinor(units), currency: e.currency, minorUnits: units, estimate: range, allowNone: true);
                            if (picked != null && mounted) setState(() => _price = picked == 0 ? null : picked);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [
                                Expanded(child: Text(t.yourPriceOptional, style: RfType.bodyStrong)),
                                if (_price != null) MoneyText(money(_price), style: RfLayout.price) else Icon(Icons.add_rounded, color: RfColors.text),
                              ]),
                              const SizedBox(height: 2),
                              Text(t.priceLineHint(money(e.riderMinMinor)), style: RfType.caption),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        _Chip(icon: Icons.payments_outlined, label: t.cash),
                        const SizedBox(width: 8),
                        _Chip(key: const Key('noteChip'), icon: noted ? Icons.check_rounded : Icons.edit_note_rounded, label: t.noteForDriver, onTap: _notes),
                      ]),
                      const SizedBox(height: 14),
                      RfButton(key: const Key('requestOffers'), label: t.requestOffers, large: true, loading: _runner.busy, onPressed: _send),
                    ]),
                  );
                },
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: RfColors.surfaceSunken,
        borderRadius: BorderRadius.circular(RfRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(RfRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: RfColors.text),
              const SizedBox(width: 6),
              Text(label, style: RfType.bodyStrong),
            ]),
          ),
        ),
      );
}

/// Returns the chosen price, 0 for "no price", or null when dismissed.
Future<int?> showPriceSheet(BuildContext context, {required int start, required int minimum, required int step, required String currency, required int minorUnits, required String estimate, bool allowNone = false}) =>
    showModalBottomSheet<int>(
      context: context,
      backgroundColor: RfColors.ink2,
      isScrollControlled: true, // the sheet rises above the keyboard
      builder: (_) => _PriceSheet(start: start, minimum: minimum, step: step, currency: currency, minorUnits: minorUnits, estimate: estimate, allowNone: allowNone),
    );

class _PriceSheet extends StatefulWidget {
  const _PriceSheet({required this.start, required this.minimum, required this.step, required this.currency, required this.minorUnits, required this.estimate, required this.allowNone});
  final int start, minimum, step, minorUnits;
  final String currency, estimate;
  final bool allowNone;
  @override
  State<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<_PriceSheet> {
  // Starts selected, so the first digit typed replaces it.
  late final _input = TextEditingController.fromValue(() {
    final text = minorToInput(widget.start, widget.minorUnits);
    return TextEditingValue(text: text, selection: TextSelection(baseOffset: 0, extentOffset: text.length));
  }());

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  int? get _price => inputToMinor(_input.text, widget.minorUnits);

  /// Moves from what is typed, or from the lowest allowed price when nothing valid is.
  void _add(int delta) {
    final next = (_price ?? widget.minimum) + delta;
    _input.value = TextEditingValue(text: minorToInput(next, widget.minorUnits), selection: TextSelection.collapsed(offset: minorToInput(next, widget.minorUnits).length));
    setState(() {});
  }

  Widget _chip(String key, int delta, {bool enabled = true}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: TextButton(
            key: Key(key),
            style: TextButton.styleFrom(minimumSize: const Size(0, 44), padding: EdgeInsets.zero, backgroundColor: RfColors.ink3, foregroundColor: RfColors.text, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: enabled ? () => _add(delta) : null,
            child: Opacity(opacity: enabled ? 1 : 0.4, child: Ltr('${delta > 0 ? '+' : '\u2212'}${minorToInput(delta.abs(), widget.minorUnits)}', style: RfType.bodyStrong)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    String money(int v) => formatMoney(v, widget.currency, widget.minorUnits);
    final price = _price;
    final valid = price != null && price >= widget.minimum;
    final step = widget.step;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.howMuch, style: RfType.h2),
          const SizedBox(height: 4),
          Text('${t.estimate} ${widget.estimate}', style: RfType.caption),
          const SizedBox(height: 14),
          TextField(
            key: const Key('priceInput'),
            controller: _input,
            autofocus: true,
            maxLength: 9,
            keyboardType: TextInputType.numberWithOptions(decimal: widget.minorUnits > 0),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(widget.minorUnits > 0 ? r'[\d.]' : r'\d'))],
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: RfType.display.copyWith(color: RfColors.gold, fontSize: 26),
            decoration: InputDecoration(counterText: '', suffixText: widget.currency, contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _chip('priceDown', -step, enabled: price != null && price - step >= widget.minimum),
            _chip('priceUp', step),
            _chip('priceUp2', step * 2),
            _chip('priceUp4', step * 4),
          ]),
          const SizedBox(height: 12),
          Text(
            t.minPrice(money(widget.minimum)),
            key: const Key('priceMinimum'),
            style: RfType.caption.copyWith(height: 1.6, color: valid || _input.text.isEmpty ? null : RfColors.coral),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          RfButton(key: const Key('usePrice'), label: t.usePrice(valid ? money(price) : ''), large: true, onPressed: valid ? () => Navigator.pop(context, price) : null),
          if (widget.allowNone) RfButton(label: t.noPrice, kind: RfButtonKind.ghost, onPressed: () => Navigator.pop(context, 0)),
        ]),
      ),
    );
  }
}
