import 'package:dio/dio.dart';

import '../core/config.dart';
import 'models.dart';

/// A place found on the map: what the rider reads, and the point the fare and the driver use.
class PlaceHit {
  const PlaceHit({required this.name, this.detail = '', required this.point});
  final String name, detail;
  final Point point;
}

/// Search and "what is at this point". Failures throw; a screen falls back to the rider's own words.
abstract class PlaceSearch {
  bool get available;
  Future<List<PlaceHit>> search(String query, {Point? near});
  Future<PlaceHit?> reverse(Point point);
}

/// Speaks the Photon API (OpenStreetMap data). Which host runs it in production is still undecided (D041).
class PhotonPlaceSearch implements PlaceSearch {
  PhotonPlaceSearch({String? baseUrl, Dio? dio})
      : _base = baseUrl ?? AppConfig.geocoderUrl,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: {'User-Agent': 'RideFlow-Rider'},
            ));
  final String _base;
  final Dio _dio;

  /// Keeps results to the rider's region: the same names exist in other countries.
  static const _regionDegrees = 0.5;

  @override
  bool get available => _base.isNotEmpty;

  @override
  Future<List<PlaceHit>> search(String query, {Point? near}) async {
    if (!available) return const [];
    final response = await _dio.get<Map<String, dynamic>>('$_base/api', queryParameters: {
      'q': query,
      'limit': 8,
      if (near != null) ...{
        'lat': near.lat,
        'lon': near.lng,
        'bbox': '${near.lng - _regionDegrees},${near.lat - _regionDegrees},${near.lng + _regionDegrees},${near.lat + _regionDegrees}',
      },
    });
    return _hits(response.data);
  }

  @override
  Future<PlaceHit?> reverse(Point point) async {
    if (!available) return null;
    final response = await _dio.get<Map<String, dynamic>>('$_base/reverse', queryParameters: {'lat': point.lat, 'lon': point.lng, 'limit': 1});
    final hits = _hits(response.data);
    return hits.isEmpty ? null : PlaceHit(name: hits.first.name, detail: hits.first.detail, point: point);
  }

  List<PlaceHit> _hits(Map<String, dynamic>? data) {
    final hits = <PlaceHit>[];
    for (final feature in (data?['features'] as List? ?? const [])) {
      final f = feature as Map;
      final p = f['properties'] as Map? ?? const {};
      final coordinates = (f['geometry'] as Map?)?['coordinates'] as List?;
      final name = (p['name'] ?? p['street'] ?? p['district']) as String?;
      if (name == null || coordinates == null || coordinates.length < 2) continue;
      final parts = <String>{};
      for (final key in ['district', 'city']) {
        final part = p[key];
        if (part is String && part != name) parts.add(part);
      }
      hits.add(PlaceHit(name: name, detail: parts.join('، '), point: Point((coordinates[1] as num).toDouble(), (coordinates[0] as num).toDouble())));
    }
    return hits;
  }
}
