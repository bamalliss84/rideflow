import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/driver_photo.dart';
import '../../shared/widgets.dart' show errorMessage;

class RatingPanel extends ConsumerStatefulWidget {
  const RatingPanel({super.key, required this.ride, required this.onDone});
  final Ride ride;
  final VoidCallback onDone;
  @override
  ConsumerState<RatingPanel> createState() => _RatingPanelState();
}

class _RatingPanelState extends ConsumerState<RatingPanel> {
  final _key = newActionKey();
  final _note = TextEditingController();
  final _tags = <String>{};
  int _stars = 0;
  bool _busy = false;

  static const _good = ['safe_driving', 'punctual', 'polite', 'clean_vehicle'];
  static const _bad = ['late', 'rude', 'unsafe', 'price_dispute'];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _label(AppLocalizations t, String tag) => switch (tag) {
        'safe_driving' => t.tag_safe_driving,
        'punctual' => t.tag_punctual,
        'polite' => t.tag_polite,
        'clean_vehicle' => t.tag_clean_vehicle,
        'late' => t.tag_late,
        'rude' => t.tag_rude,
        'unsafe' => t.tag_unsafe,
        _ => t.tag_price_dispute,
      };

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await ref.read(riderApiProvider).rate(widget.ride.id, _stars, tags: _tags.toList(), comment: _note.text.trim(), actionKey: _key);
      ref.invalidate(rideProvider(widget.ride.id));
      ref.invalidate(ridesProvider);
      if (mounted) {
        showToast(context, AppLocalizations.of(context).rated);
        widget.onDone();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'already_rated') {
        widget.onDone();
      } else {
        showToast(context, errorMessage(context, e), error: true);
      }
    } catch (e) {
      if (mounted) showToast(context, errorMessage(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final name = widget.ride.driver?.name ?? t.driver;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(18), children: [
        Text(t.rateWith(name), style: RfType.h1),
        const SizedBox(height: 18),
        Center(child: DriverPhoto(driver: widget.ride.driver, name: name, radius: 36)),
        const SizedBox(height: 10),
        Text(name, textAlign: TextAlign.center, style: RfType.h2),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              key: Key('rate_$i'),
              tooltip: '$i',
              iconSize: 38,
              onPressed: () => setState(() {
                _stars = i;
                _tags.clear();
              }),
              icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: RfColors.star),
            ),
        ]),
        Text(t.howWasIt, textAlign: TextAlign.center, style: RfType.caption),
        if (_stars > 0) ...[
          const SizedBox(height: 14),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final tag in _stars >= 4 ? _good : _bad)
              FilterChip(
                key: Key('tag_$tag'),
                label: Text(_label(t, tag), style: RfType.caption.copyWith(color: _tags.contains(tag) ? RfColors.onPri : RfColors.text, fontWeight: FontWeight.w700)),
                selected: _tags.contains(tag),
                showCheckmark: false,
                selectedColor: RfColors.pri,
                backgroundColor: RfColors.surfaceSunken,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onSelected: (on) => setState(() => on ? _tags.add(tag) : _tags.remove(tag)),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(key: const Key('ratingNote'), controller: _note, maxLines: 3, maxLength: 500, decoration: InputDecoration(hintText: t.extraNote, counterText: '')),
          const SizedBox(height: 14),
          RfButton(key: const Key('sendRating'), label: t.sendRating, large: true, loading: _busy, onPressed: _send),
        ],
        RfButton(key: const Key('rateLater'), label: t.later, kind: RfButtonKind.ghost, onPressed: widget.onDone),
      ]),
    );
  }
}
