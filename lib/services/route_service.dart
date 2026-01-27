import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Service สำหรับคำนวณระยะทางตามถนนจริงผ่าน OpenRouteService API
class RouteService {
  static const String _apiKey =
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjIxM2Q0MDZhZWI3ZDQ2OTU5ODFkNzczYjI3YTBjNDUwIiwiaCI6Im11cm11cjY0In0=';
  static const String _baseUrl =
      'https://api.openrouteservice.org/v2/directions/driving-car';

  // Cache เพื่อลด API calls
  static final Map<String, _CachedDistance> _cache = {};
  static const Duration _cacheExpiry = Duration(seconds: 30);

  /// คำนวณระยะทางตามถนน (เมตร)
  /// Returns null ถ้า API fail
  static Future<double?> getRoadDistance(LatLng from, LatLng to) async {
    final cacheKey =
        '${from.latitude},${from.longitude}-${to.latitude},${to.longitude}';

    // เช็ค cache ก่อน
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (DateTime.now().difference(cached.timestamp) < _cacheExpiry) {
        return cached.distance;
      }
    }

    try {
      final url = Uri.parse(
        '$_baseUrl?start=${from.longitude},${from.latitude}&end=${to.longitude},${to.latitude}',
      );

      final response = await http
          .get(url, headers: {'Authorization': _apiKey})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final distance =
            data['features'][0]['properties']['segments'][0]['distance'] as num;
        final distanceInMeters = distance.toDouble();

        // เก็บ cache
        _cache[cacheKey] = _CachedDistance(distanceInMeters, DateTime.now());

        return distanceInMeters;
      } else {
        print('OpenRouteService error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('RouteService error: $e');
      return null;
    }
  }

  /// ล้าง cache
  static void clearCache() {
    _cache.clear();
  }
}

class _CachedDistance {
  final double distance;
  final DateTime timestamp;

  _CachedDistance(this.distance, this.timestamp);
}
