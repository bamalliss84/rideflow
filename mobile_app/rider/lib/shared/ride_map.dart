import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/config.dart';
import '../data/models.dart';
import '../design/tokens.dart';
import '../core/app_settings.dart';
import 'arrived_flag.dart';

LatLng _ll(Point p) => LatLng(p.lat, p.lng);

/// The map under every screen that has one. With no tile address configured it still draws the stops and
/// the driver on a plain ground, so the app works without map data. The line between stops is straight:
/// it shows the direction, not a road route (no routing service, D036).
class RideMap extends StatelessWidget {
  const RideMap({super.key, this.center, this.pickup, this.dropoff, this.driver, this.driverStale = false, this.arrived = false, this.controller, this.onMoved, this.onReady, this.zoom});
  final Point? center, pickup, dropoff, driver;
  final bool driverStale;

  /// The trip is over: the destination shows the arrival mark instead of a pin (D049).
  final bool arrived;
  final MapController? controller;
  final void Function(Point center, bool byUser)? onMoved;
  final VoidCallback? onReady;
  /// Null uses the operator's `app.map_zoom` (D051).
  final double? zoom;

  @override
  Widget build(BuildContext context) {
    final stops = [if (pickup != null) _ll(pickup!), if (dropoff != null) _ll(dropoff!), if (driver != null) _ll(driver!)];
    final focus = center ?? pickup ?? dropoff ?? driver;
    final fit = onMoved == null && stops.length > 1 ? CameraFit.coordinates(coordinates: stops, padding: const EdgeInsets.all(56), maxZoom: 16) : null;
    return ColoredBox(
      color: RfColors.mapGround,
      child: FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCenter: focus == null ? const LatLng(0, 0) : _ll(focus),
          initialZoom: focus == null ? 2 : (zoom ?? currentSettings.mapZoom.toDouble()),
          initialCameraFit: fit,
          backgroundColor: RfColors.mapGround,
          onMapReady: onReady,
          interactionOptions: InteractionOptions(flags: onMoved == null ? InteractiveFlag.pinchZoom | InteractiveFlag.drag : InteractiveFlag.all & ~InteractiveFlag.rotate),
          onPositionChanged: onMoved == null ? null : (camera, byUser) => onMoved!(Point(camera.center.latitude, camera.center.longitude), byUser),
        ),
        children: [
          if (AppConfig.mapTileUrl.isNotEmpty)
            TileLayer(
              urlTemplate: AppConfig.mapTileUrl,
              userAgentPackageName: 'com.rideflow.rideflow_rider',
              tileBuilder: RfColors.isNight && AppConfig.mapDarken ? darkModeTileBuilder : null,
              errorTileCallback: (_, __, ___) {},
            ),
          if (pickup != null && dropoff != null)
            PolylineLayer(
              polylines: driver != null && !arrived
                  // On the way: the part behind the car is solid, the part ahead is faint.
                  ? [
                      Polyline(points: [_ll(driver!), _ll(dropoff!)], strokeWidth: 5, color: RfColors.teal.withOpacity(0.35)),
                      Polyline(points: [_ll(pickup!), _ll(driver!)], strokeWidth: 5, color: RfColors.teal),
                    ]
                  : [Polyline(points: [_ll(pickup!), _ll(dropoff!)], strokeWidth: 5, color: RfColors.teal)],
            ),
          MarkerLayer(markers: [
            if (pickup != null) Marker(point: _ll(pickup!), width: 26, height: 26, child: const _Ring()),
            if (dropoff != null && arrived) Marker(point: _ll(dropoff!), width: 96, height: 96, child: const ArrivedFlag()),
            if (dropoff != null && !arrived) Marker(point: _ll(dropoff!), width: 34, height: 34, child: Icon(Icons.place_rounded, color: RfColors.gold, size: 34)),
            if (driver != null && !arrived)
              Marker(
                point: _ll(driver!),
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(color: driverStale ? RfColors.ink3 : RfColors.text, shape: BoxShape.circle),
                  child: Icon(Icons.directions_car_rounded, size: 24, color: driverStale ? RfColors.textMuted : RfColors.canvas),
                ),
              ),
          ]),
          if (AppConfig.mapTileUrl.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.bottomStart,
              child: Padding(padding: const EdgeInsets.all(6), child: Text(AppConfig.mapAttribution, style: TextStyle(fontSize: 10, color: RfColors.textMuted))),
            ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring();
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: RfColors.canvas, shape: BoxShape.circle, border: Border.all(color: RfColors.teal, width: 5)),
      );
}
