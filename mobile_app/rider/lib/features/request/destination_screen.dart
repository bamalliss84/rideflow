import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/place_search.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/ride_map.dart';

int _metres(Point a, Point b) => const Distance().as(LengthUnit.Meter, LatLng(a.lat, a.lng), LatLng(b.lat, b.lng)).round();

String _label(PlaceHit hit) => hit.detail.isEmpty ? hit.name : '${hit.name}، ${hit.detail}';

/// The stop's point and name both come from the map; words typed by the rider are only the fallback (D041).
/// Model 1: the map is the screen, with a fixed pin and a search field on top; typing there opens the results over the
/// map, on this same screen. Model 3: a sheet under the map holds the search and the rider's places, and shrinks once a
/// place is chosen. The rider switches between them in settings. Coming from "where to", the keyboard is already open.
class DestinationScreen extends ConsumerStatefulWidget {
  const DestinationScreen({super.key, this.initialDropoff});
  final Place? initialDropoff;
  @override
  ConsumerState<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends ConsumerState<DestinationScreen> {
  /// Two stops this close are almost always a pin nobody moved.
  static const _minTripMetres = 100;

  /// A place that was chosen shows close enough to nudge the pin onto the exact door.
  static const _placeZoom = 18.0;

  /// A new reading this close is the same spot, and keeps its name.
  static const _sameSpotMetres = 30;

  final _map = MapController();
  final _typed = TextEditingController();
  Timer? _debounce;
  int _lookup = 0;

  bool _mapReady = false;
  bool _editingPickup = false;
  Place? _dropoff;

  Point? _pickupPoint;
  String? _pickupName;
  bool _pickupFromDevice = false;
  Future<PlaceHit?>? _pickupLookup;
  bool _waitingName = false;

  Point? _center;
  String? _centerName;
  bool _resolving = false;
  bool _chosen = false;

  // Model 1's results over the map. Back leaves the screen until the rider has been on the map.
  bool _searchOpen = false;
  bool _beenOnMap = false;

  // Model 3's sheet.
  bool _sheetOpen = false;
  bool _listDismissed = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDropoff;
    if (initial != null) {
      _dropoff = initial;
      _center = initial.point;
      _centerName = initial.landmark;
      _chosen = true;
      _beenOnMap = true;
    } else {
      _searchOpen = true;
      _sheetOpen = ref.read(destinationModelProvider) == 3;
    }
    // The home screen's fix shows at once. A pickup must not stay where the rider was at launch, so a new reading follows
    // and replaces it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final known = ref.read(myLocationProvider).valueOrNull;
      if (known != null) _gotDeviceLocation(known);
      ref.invalidate(myLocationProvider);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _typed.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<PlaceHit?> _reverse(Point point) async {
    try {
      return await ref.read(placeSearchProvider).reverse(point);
    } catch (_) {
      return null;
    }
  }

  void _fly(Point point, {double zoom = 15}) {
    if (_mapReady) _map.move(LatLng(point.lat, point.lng), _map.camera.zoom < zoom ? zoom : _map.camera.zoom);
  }

  Future<void> _gotDeviceLocation(Point? here) async {
    if (_pickupPoint != null && !_pickupFromDevice) return;
    if (here == null) {
      if (_pickupPoint == null) setState(() => _editingPickup = true);
      return;
    }
    bool near(Point other) => _metres(other, here) < _sameSpotMetres;
    final previous = _pickupPoint;
    final named = ref.read(namedSpotProvider);
    final name = previous != null && near(previous) && _pickupName != null ? _pickupName : (named != null && near(named.$1) ? named.$2 : null);
    setState(() {
      _pickupPoint = here;
      _pickupFromDevice = true;
      _pickupName = name;
    });
    if (_center == null) {
      _center = here;
      _fly(here);
    }
    if (name != null) {
      _pickupLookup = null;
      return;
    }
    final lookup = _pickupLookup = _reverse(here);
    final hit = await lookup;
    if (!mounted || !identical(_pickupLookup, lookup)) return;
    _pickupLookup = null;
    if (!_pickupFromDevice) return;
    final label = hit == null ? null : _label(hit);
    if (label != null) ref.read(namedSpotProvider.notifier).state = (here, label);
    setState(() => _pickupName = label);
  }

  void _onMoved(Point point, bool byUser) {
    if (!byUser) return;
    _debounce?.cancel();
    _typed.clear();
    setState(() {
      _center = point;
      _centerName = null;
      _chosen = true;
      _resolving = true;
      _sheetOpen = false;
    });
    final lookup = ++_lookup;
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final hit = await _reverse(point);
      if (!mounted || lookup != _lookup) return;
      setState(() {
        _centerName = hit == null ? null : _label(hit);
        _resolving = false;
      });
    });
  }

  void _use(PlaceHit hit) {
    _debounce?.cancel();
    _lookup++;
    _typed.clear();
    setState(() {
      _center = hit.point;
      _centerName = _label(hit);
      _chosen = true;
      _resolving = false;
      _sheetOpen = false;
      _searchOpen = false;
      _beenOnMap = true;
    });
    _fly(hit.point, zoom: _placeZoom);
  }

  void _reopenSearch() {
    _debounce?.cancel();
    _lookup++;
    _typed.clear();
    setState(() {
      _chosen = false;
      _centerName = null;
      _resolving = false;
      _listDismissed = false;
      _sheetOpen = true;
    });
  }

  void _editPickup() {
    final point = _pickupPoint;
    setState(() {
      if (!_editingPickup && _chosen && _center != null && _centerName != null) _dropoff = Place(_centerName!, _center!);
      _editingPickup = true;
      _chosen = point != null;
      _center = point ?? _center;
      _centerName = _pickupName;
    });
    if (point != null) _fly(point, zoom: _placeZoom);
  }

  void _toDevice() {
    final here = ref.read(myLocationProvider).valueOrNull;
    if (here == null) return;
    _fly(here);
    if (_editingPickup) {
      _onMoved(here, true);
    }
  }

  String get _name => _typed.text.trim().isNotEmpty ? _typed.text.trim() : (_centerName ?? '');

  void _confirmPickup() {
    _pickupLookup = null;
    setState(() {
      _pickupPoint = _center;
      _pickupName = _name;
      _pickupFromDevice = false;
      _editingPickup = false;
      _typed.clear();
      final dropoff = _dropoff;
      _chosen = dropoff != null;
      _listDismissed = false;
      _center = dropoff?.point ?? _center;
      _centerName = dropoff?.landmark;
    });
    if (_center != null) _fly(_center!, zoom: _chosen ? _placeZoom : 15);
  }

  Future<void> _showPrice() async {
    // The pickup's name may still be on its way: wait for it rather than sending the rider back to word the pickup.
    final lookup = _pickupLookup;
    if (lookup != null) {
      setState(() => _waitingName = true);
      await lookup;
      if (!mounted) return;
      setState(() => _waitingName = false);
    }
    final name = _pickupName;
    if (name == null || name.isEmpty) {
      // The driver reads this, so a point with no name goes back to the rider for words.
      _dropoff = Place(_name, _center!);
      _editPickup();
      return;
    }
    context.push('/request', extra: RideDraft(pickup: Place(name, _pickupPoint!), dropoff: Place(_name, _center!), requireCode: ref.read(alwaysCodeProvider)));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    ref.listen(myLocationProvider, (_, next) {
      if (!next.isLoading && !next.isRefreshing) _gotDeviceLocation(next.valueOrNull);
    });
    final location = ref.watch(myLocationProvider);
    final locating = location.isLoading || location.isRefreshing;
    final start = _center ?? location.valueOrNull ?? ref.watch(citiesProvider).valueOrNull?.firstOrNull?.center;

    final far = !_editingPickup && _pickupPoint != null && _center != null ? _metres(_pickupPoint!, _center!) : null;
    final tooClose = _chosen && far != null && far < _minTripMetres;
    final needsWords = _chosen && !_resolving && _centerName == null;
    final ready = _chosen && !_resolving && _name.isNotEmpty && _center != null && !tooClose && (_editingPickup || _pickupPoint != null);
    final sheetModel = ref.watch(destinationModelProvider) == 3;
    final showList = sheetModel && !_chosen && !_listDismissed;

    final String title;
    final String hint;
    if (_resolving) {
      title = t.resolvingPlace;
      hint = '';
    } else if (needsWords) {
      title = t.pointOnMap;
      hint = '';
    } else if (_chosen && _centerName != null) {
      title = _centerName!;
      hint = tooClose ? t.tooCloseToPickup : (far == null ? t.moveMapHint : t.distanceAway(formatDistance(far)));
    } else {
      title = t.moveMapToChoose;
      hint = t.moveMapHint;
    }

    final fromRow = InkWell(
      key: const Key('fromRow'),
      onTap: _editPickup,
      child: SizedBox(
        height: 44,
        child: Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: RfColors.teal, width: 3.5))),
          const SizedBox(width: 10),
          Text('${t.from} ', style: RfType.caption),
          Expanded(child: Text(_fromText(t, locating), key: const Key('fromText'), style: RfType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
    final wordsField = TextField(key: const Key('placeName'), controller: _typed, maxLength: 200, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: t.placeName, counterText: ''));
    final mainButton = _editingPickup
        ? RfButton(key: const Key('confirmPickup'), label: t.confirmPickup, large: true, onPressed: ready ? _confirmPickup : null)
        : RfButton(key: const Key('showPrice'), label: _chosen ? t.showPrice : t.confirmDestination, large: true, loading: _waitingName, onPressed: ready ? _showPrice : null);
    final hintText = hint.isEmpty ? null : Text(hint, key: const Key('placeHint'), style: RfType.caption.copyWith(color: tooClose ? RfColors.coral : RfColors.textMuted));

    void toMap() => setState(() {
          _searchOpen = false;
          _beenOnMap = true;
        });
    final searching = !sheetModel && _searchOpen;
    return PopScope(
      canPop: !_sheetOpen && !(searching && _beenOnMap),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() {
            _sheetOpen = false;
            _searchOpen = false;
          });
        }
      },
      child: Scaffold(
      body: LayoutBuilder(builder: (context, box) => Column(children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: start == null
                  ? ColoredBox(color: RfColors.mapGround)
                  : RideMap(
                      key: const Key('destinationMap'),
                      center: start,
                      zoom: _chosen ? _placeZoom : 15,
                      controller: _map,
                      pickup: _editingPickup ? null : _pickupPoint,
                      onMoved: _onMoved,
                      onReady: () => _mapReady = true,
                    ),
            ),
            if (!showList && !searching) Center(child: IgnorePointer(child: Padding(padding: const EdgeInsets.only(bottom: 44), child: Icon(Icons.place_rounded, key: const Key('pin'), color: RfColors.gold, size: 48)))),
            if (searching) Positioned.fill(child: ColoredBox(color: RfLayout.page)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Spacer(),
                  if (!searching)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: _RoundButton(key: const Key('toMyLocation'), icon: Icons.my_location_rounded, color: RfColors.teal, tooltip: t.myLocation, onTap: location.valueOrNull == null ? null : _toDevice),
                    ),
                ]),
              ),
            ),
            // Empty parts of this let the map below take its gestures.
            if (sheetModel)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: _RoundButton(icon: Icons.arrow_back_rounded, tooltip: MaterialLocalizations.of(context).backButtonTooltip, onTap: () => Navigator.of(context).maybePop(), flip: true),
                ),
              )
            else
              SafeArea(
                bottom: false,
                child: _SearchPanel(
                  near: _center ?? _pickupPoint,
                  from: _pickupPoint,
                  autofocus: searching,
                  floating: true,
                  open: searching,
                  hint: _editingPickup ? t.searchPickup : t.searchDestination,
                  header: _editingPickup ? null : fromRow,
                  leading: _RoundButton(icon: Icons.arrow_back_rounded, tooltip: MaterialLocalizations.of(context).backButtonTooltip, onTap: () => Navigator.of(context).maybePop(), flip: true),
                  onFocus: () => setState(() => _searchOpen = true),
                  onChoose: _use,
                  onMap: toMap,
                ),
              ),
          ]),
        ),
        if (searching)
          const SizedBox.shrink()
        else if (showList)
          AnimatedContainer(
            key: const Key('placeSheet'),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: (_sheetOpen ? box.maxHeight - 170 : box.maxHeight * 0.48).clamp(0, box.maxHeight - 60),
            decoration: BoxDecoration(color: RfColors.ink2, borderRadius: const BorderRadius.vertical(top: Radius.circular(RfRadius.xl))),
            child: SafeArea(
              top: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const _Grab(),
                if (!_sheetOpen) Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 4), child: Text(_editingPickup ? t.searchPickup : t.whereTo, style: RfType.h2)),
                if (!_editingPickup) Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: fromRow),
                Expanded(
                  child: _SearchPanel(
                    near: _center ?? _pickupPoint,
                    from: _pickupPoint,
                    autofocus: _sheetOpen,
                    onFocus: () => setState(() => _sheetOpen = true),
                    onChoose: _use,
                    onMap: () => setState(() {
                      _listDismissed = true;
                      _sheetOpen = false;
                    }),
                  ),
                ),
              ]),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(color: RfColors.ink2, borderRadius: const BorderRadius.vertical(top: Radius.circular(RfRadius.xl))),
            child: SafeArea(
              top: false,
              child: sheetModel
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const _Grab(),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_editingPickup ? t.pickupLabel : t.destinationLabel, style: RfType.caption),
                              Text(title, key: const Key('placeTitle'), style: RfType.h2, maxLines: 2, overflow: TextOverflow.ellipsis),
                              if (hintText != null) hintText,
                            ]),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(key: const Key('editPlace'), onPressed: _reopenSearch, child: Text(t.edit)),
                        ]),
                        if (needsWords) ...[const SizedBox(height: 8), wordsField],
                        if (!_editingPickup) ...[const SizedBox(height: 4), fromRow],
                        const SizedBox(height: 8),
                        mainButton,
                      ]),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (!_editingPickup) ...[
                          fromRow,
                          Divider(height: 1, color: RfColors.line),
                          const SizedBox(height: 10),
                        ],
                        Text(_editingPickup ? t.pickupLabel : t.destinationLabel, style: RfType.caption),
                        const SizedBox(height: 2),
                        Text(title, key: const Key('placeTitle'), style: RfType.h2, maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (hintText != null) ...[const SizedBox(height: 2), hintText],
                        if (needsWords) ...[const SizedBox(height: 8), wordsField],
                        const SizedBox(height: 12),
                        mainButton,
                      ]),
                    ),
            ),
          ),
      ])),
    ));
  }

  String _fromText(AppLocalizations t, bool locating) {
    if (_pickupPoint == null) return locating ? t.locating : t.chooseOnMap;
    final name = _pickupName;
    if (!_pickupFromDevice) return name ?? t.pointOnMap;
    return name == null || name.isEmpty ? t.myLocation : '${t.myLocation}، $name';
  }
}

class _Grab extends StatelessWidget {
  const _Grab();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(width: 44, height: 5, margin: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: RfColors.lineStrong, borderRadius: BorderRadius.circular(3))),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.color, this.flip = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final bool flip;
  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Material(
      color: RfColors.ink2,
      elevation: 4,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: Transform.flip(flipX: flip && rtl, child: Icon(icon, color: onTap == null ? RfColors.textSubtle : color ?? RfColors.text, size: 22)),
      ),
    );
  }
}

/// Search as you type, with the rider's own places first.
class _SearchPanel extends ConsumerStatefulWidget {
  const _SearchPanel({this.near, this.from, this.autofocus = false, this.floating = false, this.open = true, this.hint, this.header, this.leading, this.onFocus, required this.onChoose, required this.onMap});
  final Point? near, from;
  final bool autofocus;

  /// Model 1: the field sits on the map, and the results show only while [open].
  final bool floating, open;
  final String? hint;
  final Widget? header, leading;
  final VoidCallback? onFocus;
  final ValueChanged<PlaceHit> onChoose;
  final VoidCallback onMap;
  @override
  ConsumerState<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<_SearchPanel> {
  final _query = TextEditingController();
  Timer? _debounce;
  int _lookup = 0;
  List<PlaceHit> _hits = const [];
  bool _searching = false;
  bool _failed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Where to search. The device's first fix can take a while, and with no area at all the search returns the same
  /// names from other countries, so the operator's city stands in until it arrives.
  Future<Point?> _area() async {
    final known = widget.near ?? ref.read(myLocationProvider).valueOrNull;
    if (known != null) return known;
    try {
      return (await ref.read(citiesProvider.future)).firstOrNull?.center;
    } catch (_) {
      return null;
    }
  }

  void _changed(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final lookup = ++_lookup;
    if (query.length < 2) {
      setState(() {
        _hits = const [];
        _searching = false;
        _failed = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      List<PlaceHit> hits = const [];
      var failed = false;
      try {
        hits = await ref.read(placeSearchProvider).search(query, near: await _area());
      } catch (_) {
        failed = true;
      }
      if (!mounted || lookup != _lookup) return;
      setState(() {
        _hits = hits;
        _failed = failed;
        _searching = false;
      });
    });
  }

  void _leave() {
    _debounce?.cancel();
    _lookup++;
    _query.clear();
    _hits = const [];
    _searching = false;
    _failed = false;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String? _away(Point point) => widget.from == null ? null : formatDistance(_metres(widget.from!, point));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final saved = ref.watch(placesProvider).valueOrNull ?? const <SavedPlace>[];
    final recent = ref.watch(recentPlacesProvider).valueOrNull ?? const <Place>[];
    final query = _query.text.trim();
    bool matches(String text) => query.isEmpty || text.contains(query);
    void choose(PlaceHit hit) {
      _leave();
      widget.onChoose(hit);
    }

    final mine = [
      for (final p in saved.where((p) => matches(p.label) || matches(p.landmark)))
        _ResultRow(icon: p.kind == 'home' ? Icons.home_rounded : (p.kind == 'work' ? Icons.work_rounded : Icons.star_rounded), title: p.label, subtitle: p.landmark, trailing: _away(p.place.point), onTap: () => choose(PlaceHit(name: p.landmark, point: p.place.point))),
      for (final p in recent.where((p) => matches(p.landmark))) _ResultRow(icon: Icons.history_rounded, title: p.landmark, trailing: _away(p.point), onTap: () => choose(PlaceHit(name: p.landmark, point: p.point))),
    ];
    final status = !ref.watch(placeSearchProvider).available
        ? t.searchOff
        : (_failed ? t.searchFailed : (query.length >= 2 && !_searching && _hits.isEmpty && mine.isEmpty ? t.searchEmpty : null));
    final field = TextField(
      key: const Key('searchInput'),
      controller: _query,
      autofocus: widget.autofocus,
      onTap: widget.onFocus,
      onChanged: (value) {
        if (widget.floating && !widget.open) widget.onFocus?.call();
        _changed(value);
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint ?? t.searchPlaceHint,
        filled: true,
        fillColor: widget.floating ? RfColors.canvas : RfColors.surfaceSunken,
        isDense: widget.floating,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: RfColors.pri, width: 1.5)),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null,
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: widget.floating ? const EdgeInsets.fromLTRB(14, 12, 14, 8) : const EdgeInsetsDirectional.fromSTEB(18, 6, 18, 6),
        child: Row(children: [
          if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 10)],
          Expanded(child: widget.floating ? Material(color: Colors.transparent, elevation: widget.open ? 0 : 4, borderRadius: BorderRadius.circular(RfRadius.md), child: field) : field),
        ]),
      ),
      if (widget.open)
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 2, 16, 12), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, children: [
            if (widget.header != null) RfGroup(children: [Padding(padding: EdgeInsets.symmetric(horizontal: RfLayout.inset), child: widget.header!)]),
            if (mine.isNotEmpty) _Section(title: t.recent, children: mine),
            if (_hits.isNotEmpty)
              _Section(title: t.sectionResults, children: [
                for (final (i, hit) in _hits.indexed) _ResultRow(key: Key('hit_$i'), icon: Icons.place_outlined, title: hit.name, subtitle: hit.detail.isEmpty ? null : hit.detail, trailing: _away(hit.point), onTap: () => choose(hit)),
              ]),
            if (status != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(status, key: const Key('searchStatus'), style: RfType.caption)),
            _Section(children: [
              _ResultRow(key: const Key('backToMap'), icon: Icons.map_outlined, title: t.chooseOnMap, onTap: () {
                _leave();
                widget.onMap();
              }),
            ]),
          ]),
        ),
    ]);
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, required this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle, trailing;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final sub = [if (subtitle != null && subtitle!.isNotEmpty) subtitle!, if (trailing != null) trailing!].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: RfColors.surfaceSunken, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: RfColors.text),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: RfType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (sub.isNotEmpty) Text(sub, style: RfType.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A flat list section (direction A): a small label, then the rows, no card around them.
class _Section extends StatelessWidget {
  const _Section({this.title, required this.children});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(title!, style: RfType.caption.copyWith(fontWeight: FontWeight.w700))),
          ...children,
        ]),
      );
}
