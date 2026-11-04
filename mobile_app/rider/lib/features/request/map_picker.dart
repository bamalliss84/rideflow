import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../data/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/ride_map.dart';

/// Saving a place: a point on the map plus the rider's own words for it.
Future<Place?> pickOnMap(BuildContext context, {Point? center}) =>
    Navigator.of(context).push<Place>(MaterialPageRoute(builder: (_) => MapPickerScreen(center: center)));

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.center});
  final Point? center;
  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late Point? _point = widget.center;
  bool _moved = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.pickPoint), leading: const BackButton()),
      body: Column(children: [
        Expanded(
          child: Stack(alignment: Alignment.center, children: [
            RideMap(
              center: widget.center,
              onMoved: (p, byUser) {
                if (!byUser) return;
                _point = p;
                if (!_moved) setState(() => _moved = true);
              },
            ),
            IgnorePointer(child: Padding(padding: const EdgeInsets.only(bottom: 34), child: Icon(Icons.place_rounded, color: RfColors.gold, size: 44))),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(key: const Key('placeName'), controller: _name, maxLength: 200, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t.placeName, counterText: '')),
              const SizedBox(height: 12),
              RfButton(
                key: const Key('usePoint'),
                label: t.usePoint,
                large: true,
                onPressed: !_moved || _name.text.trim().isEmpty || _point == null ? null : () => Navigator.pop(context, Place(_name.text.trim(), _point!)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
