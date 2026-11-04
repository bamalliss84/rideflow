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
import '../../shared/widgets.dart' show ActionRunner, AsyncBody;

/// Default price step: 50 whole currency units. A ride's own snapshot carries the operator's step once it exists.
int defaultStepMinor(int minorUnits) {
  var step = 50;
  for (var i = 0; i < minorUnits; i++) {
    step *= 10;
  }
  return step;
}

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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final units = ref.watch(authProvider).valueOrNull?.minorUnits ?? 2;
    final value = ref.watch(estimateProvider(widget.draft));
    final d = widget.draft;
    return Scaffold(
      appBar: AppBar(title: Text(t.price), leading: const BackButton()),
      bottomNavigationBar: value.valueOrNull == null ? null : RfFoot(child: RfButton(key: const Key('requestOffers'), label: t.requestOffers, large: true, loading: _runner.busy, onPressed: _send)),
      body: AsyncBody<Estimate>(
        value: value,
        onRetry: () => ref.invalidate(estimateProvider(widget.draft)),
        data: (e) {
          String money(int? v) => formatMoney(v, e.currency, units);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            RfGroup(title: t.sectionTrip, children: [
              RfStops(fromLabel: t.from, from: d.pickup.landmark, toLabel: t.to, to: d.dropoff.landmark),
              RfFacts([RfFact(t.distance, formatDistance(e.distanceM), ltr: true), RfFact(t.payment, t.cash)]),
            ]),
            RfGroup(title: t.estimate, children: [
              Padding(
                padding: RfLayout.box,
                child: Column(children: [
                  MoneyText('${formatMoney(e.minMinor, '', units)} – ${money(e.maxMinor)}', style: RfLayout.price),
                  const SizedBox(height: 2),
                  Text(t.estimateNote, style: RfType.caption, textAlign: TextAlign.center),
                ]),
              ),
              RfRow(
                key: const Key('addPrice'),
                title: _price == null ? t.addPrice : t.yourPrice,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_price != null) MoneyText(money(_price), style: RfType.bodyStrong.copyWith(color: RfColors.gold)),
                  Icon(Icons.chevron_left_rounded, color: RfColors.textMuted),
                ]),
                onTap: () async {
                  final picked = await showPriceSheet(context, start: _price ?? e.riderMinMinor, minimum: e.riderMinMinor, step: defaultStepMinor(units), currency: e.currency, minorUnits: units, estimate: '${formatMoney(e.minMinor, '', units)} – ${money(e.maxMinor)}', allowNone: true);
                  if (picked != null && mounted) setState(() => _price = picked == 0 ? null : picked);
                },
              ),
            ]),
            RfGroup(title: t.sectionNotes, children: [
              Padding(
                padding: RfLayout.box,
                child: Column(children: [
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
                    decoration: InputDecoration(hintText: t.dropoffNoteHint, counterText: '', prefixIcon: Icon(Icons.place_rounded, color: RfColors.gold, size: 18)),
                  ),
                ]),
              ),
            ]),
            RfGroup(children: [
              RfRow(
                title: t.startCodeTitle,
                sub: _code ? t.on_ : t.off_,
                trailing: Switch(key: const Key('codeSwitch'), value: _code, activeTrackColor: RfColors.teal, onChanged: (v) => setState(() => _code = v)),
              ),
            ]),
          ]);
        },
      ),
    );
  }
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
