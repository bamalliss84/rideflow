import 'package:flutter_test/flutter_test.dart';
import 'package:rideflow_driver/core/location/location_service.dart';
import 'package:rideflow_driver/data/models.dart';
import 'package:rideflow_driver/features/home/home_screen.dart' show metersTo;

void main() {
  test('the distance to a pickup is the straight line, in metres', () {
    final here = Fix(lat: 14.5426, lng: 49.1242, accuracy: 5, deviceTs: DateTime(2026));
    expect(metersTo(here, const LatLng(14.5426, 49.1242)), closeTo(0, 0.01));
    // 0.01 degrees of latitude is about 1.11 km anywhere.
    expect(metersTo(here, const LatLng(14.5526, 49.1242)), closeTo(1112, 5));
  });
}
