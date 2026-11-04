import 'package:flutter/material.dart';
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
      bottomNavigationBar: value.valueOrNull == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: RfButton(key: const Key('requestOffers'), label: t.requestOffers, large: true, loading: _runner.busy, onPressed: _send),
              ),
            ),
      body: AsyncBody<Estimate>(
        value: value,
        onRetry: () => ref.invalidate(estimateProvider(widget.draft)),
        data: (e) {
          String money(int? v) => formatMoney(v, e.currency, units);
          return ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 18), children: [
            ClipRRect(borderRadius: BorderRadius.circular(RfRadius.lg), child: SizedBox(height: 190, child: RideMap(pickup: d.pickup.point, dropoff: d.dropoff.point))),
            const SizedBox(height: 12),
            RfCard(
              child: Row(children: [
                Expanded(child: StatColumn(label: t.distance, value: formatDistance(e.distanceM))),
                Expanded(child: StatColumn(label: t.payment, value: t.cash)),
              ]),
            ),
            const SizedBox(height: 12),
            RfCard(
              border: RfColors.teal,
              child: Column(children: [
                Text(t.estimate, style: RfType.label),
                const SizedBox(height: 4),
                MoneyText('${formatMoney(e.minMinor, '', units)} – ${money(e.maxMinor)}', style: RfType.display.copyWith(color: RfColors.gold, fontSize: 22)),
                const SizedBox(height: 4),
                Text(t.estimateNote, style: RfType.caption, textAlign: TextAlign.center),
              ]),
            ),
            const SizedBox(height: 12),
            RfButton(
              key: const Key('addPrice'),
              label: _price == null ? t.addPrice : '${t.yourPrice} · ${money(_price)}',
              kind: RfButtonKind.secondary,
              onPressed: () async {
                final picked = await showPriceSheet(context, start: _price ?? e.riderMinMinor, minimum: e.riderMinMinor, step: defaultStepMinor(units), currency: e.currency, minorUnits: units, estimate: '${formatMoney(e.minMinor, '', units)} – ${money(e.maxMinor)}', allowNone: true);
                if (picked != null && mounted) setState(() => _price = picked == 0 ? null : picked);
              },
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('pickupNote'),
              controller: _pickupNote,
              maxLength: 300,
              decoration: InputDecoration(hintText: t.pickupNoteHint, counterText: '', prefixIcon: Icon(Icons.radio_button_checked_rounded, color: RfColors.teal, size: 20)),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('dropoffNote'),
              controller: _dropoffNote,
              maxLength: 300,
              decoration: InputDecoration(hintText: t.dropoffNoteHint, counterText: '', prefixIcon: Icon(Icons.place_rounded, color: RfColors.gold, size: 20)),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              key: const Key('codeSwitch'),
              contentPadding: EdgeInsets.zero,
              value: _code,
              activeTrackColor: RfColors.teal,
              title: Text(t.startCodeTitle, style: RfType.bodyStrong),
              subtitle: Text(_code ? t.on_ : t.off_, style: RfType.caption),
              onChanged: (v) => setState(() => _code = v),
            ),
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
  late int _price = widget.start;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    String money(int v) => formatMoney(v, widget.currency, widget.minorUnits);
    final down = _price - widget.step >= widget.minimum;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t.howMuch, style: RfType.h2),
          const SizedBox(height: 4),
          Text('${t.estimate} ${widget.estimate}', style: RfType.caption),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton.filledTonal(key: const Key('priceUp'), iconSize: 28, style: IconButton.styleFrom(minimumSize: const Size(56, 56), backgroundColor: RfColors.ink3), onPressed: () => setState(() => _price += widget.step), icon: const Icon(Icons.add_rounded)),
            Expanded(child: Center(child: MoneyText(money(_price), style: RfType.display.copyWith(color: RfColors.gold, fontSize: 26)))),
            IconButton.filledTonal(key: const Key('priceDown'), iconSize: 28, style: IconButton.styleFrom(minimumSize: const Size(56, 56), backgroundColor: RfColors.ink3), onPressed: down ? () => setState(() => _price -= widget.step) : null, icon: const Icon(Icons.remove_rounded)),
          ]),
          const SizedBox(height: 20),
          Text(t.minPrice(money(widget.minimum)), style: RfType.caption.copyWith(height: 1.6), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          RfButton(key: const Key('usePrice'), label: t.usePrice(money(_price)), large: true, onPressed: () => Navigator.pop(context, _price)),
          if (widget.allowNone) RfButton(label: t.noPrice, kind: RfButtonKind.ghost, onPressed: () => Navigator.pop(context, 0)),
        ]),
      ),
    );
  }
}
