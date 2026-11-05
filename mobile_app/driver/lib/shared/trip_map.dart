import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../core/config.dart';
import '../data/models.dart';
import '../design/tokens.dart';
import 'arrived_flag.dart';

ll.LatLng _ll(LatLng p) => ll.LatLng(p.lat, p.lng);

/// The trip on a map, above the step (D049, model 1). The line is straight: it shows the direction, not a road
/// (no routing service, D036). With no tile address it still draws on a plain ground, so the trip works without map data.
class TripMap extends StatelessWidget {
  const TripMap({super.key, this.pickup, this.dropoff, this.me, this.arrived = false, this.height = 220});
  final LatLng? pickup, dropoff, me;
  final bool arrived;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = [if (pickup != null) _ll(pickup!), if (dropoff != null) _ll(dropoff!), if (me != null && !arrived) _ll(me!)];
    if (points.isEmpty) return const SizedBox.shrink();
    final night = RfColors.isNight;
    return ClipRRect(
      key: const Key('tripMap'),
      borderRadius: BorderRadius.circular(RfRadius.md),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: RfColors.mapGround,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: points.first,
              initialZoom: 15,
              initialCameraFit: points.length > 1 ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(40), maxZoom: 16) : null,
              backgroundColor: RfColors.mapGround,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
            ),
            children: [
              if (AppConfig.mapTileUrl.isNotEmpty)
                TileLayer(
                  urlTemplate: AppConfig.mapTileUrl,
                  userAgentPackageName: 'com.rideflow.rideflow_driver',
                  tileBuilder: night ? darkModeTileBuilder : null,
                  errorTileCallback: (_, __, ___) {},
                ),
              if (pickup != null && dropoff != null)
                PolylineLayer(
                  polylines: me != null && !arrived
                      ? [
                          Polyline(points: [_ll(me!), _ll(dropoff!)], strokeWidth: 5, color: RfColors.teal.withOpacity(0.35)),
                          Polyline(points: [_ll(pickup!), _ll(me!)], strokeWidth: 5, color: RfColors.teal),
                        ]
                      : [Polyline(points: [_ll(pickup!), _ll(dropoff!)], strokeWidth: 5, color: RfColors.teal)],
                )
              else if (pickup != null && me != null)
                PolylineLayer(polylines: [Polyline(points: [_ll(me!), _ll(pickup!)], strokeWidth: 4, color: RfColors.gold.withOpacity(0.7))]),
              MarkerLayer(markers: [
                if (pickup != null)
                  Marker(
                    point: _ll(pickup!),
                    width: 24,
                    height: 24,
                    child: Container(decoration: BoxDecoration(color: RfColors.canvas, shape: BoxShape.circle, border: Border.all(color: RfColors.teal, width: 5))),
                  ),
                if (dropoff != null && arrived) Marker(point: _ll(dropoff!), width: 96, height: 96, child: const ArrivedFlag()),
                if (dropoff != null && !arrived) Marker(point: _ll(dropoff!), width: 34, height: 34, child: Icon(Icons.place_rounded, color: RfColors.gold, size: 34)),
                if (me != null && !arrived)
                  Marker(
                    point: _ll(me!),
                    width: 38,
                    height: 38,
                    child: Container(
                      key: const Key('myCar'),
                      decoration: BoxDecoration(color: RfColors.text, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)]),
                      child: Icon(Icons.directions_car_rounded, size: 22, color: RfColors.canvas),
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
        ),
      ),
    );
  }
}
