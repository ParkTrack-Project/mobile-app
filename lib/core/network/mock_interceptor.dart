import 'package:dio/dio.dart';

const bool kUseMocks = false;

class MockInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    final path = options.path;

    if (method == 'POST' && path == '/auth/register') {
      return handler.resolve(_response(options, _authPayload('registered@mock.dev', 'New User')));
    }
    if (method == 'POST' && path == '/auth/login') {
      return handler.resolve(_response(options, _authPayload('user@mock.dev', 'Mock User')));
    }
    if (method == 'GET' && path == '/auth/me') {
      return handler.resolve(_response(options, _userPayload('user@mock.dev', 'Mock User')));
    }
    if (method == 'POST' && path == '/auth/logout') {
      return handler.resolve(_response(options, {}));
    }

    if (method == 'GET' && path.startsWith('/zones')) {
      return handler.resolve(_response(options, [
        _mockZone(
          zoneId: 101,
          zoneType: 'standard',
          freeCount: 5,
          pay: 0,
          ring: [
            [30.398, 59.733],
            [30.402, 59.733],
            [30.402, 59.737],
            [30.398, 59.737],
            [30.398, 59.733],
          ],
        ),
        _mockZone(
          zoneId: 102,
          zoneType: 'standard',
          freeCount: 2,
          pay: 100,
          ring: [
            [30.406, 59.739],
            [30.410, 59.739],
            [30.410, 59.743],
            [30.406, 59.743],
            [30.406, 59.739],
          ],
        ),
        _mockZone(
          zoneId: 103,
          zoneType: 'parallel',
          freeCount: 0,
          pay: 50,
          ring: [
            [30.403, 59.735],
            [30.403, 59.736],
            [30.412, 59.736],
            [30.412, 59.735],
            [30.403, 59.735],
          ],
        ),
      ]));
    }

    if (method == 'GET' && path.startsWith('/occupancy')) {
      return handler.resolve(_response(options, [
        _mockOccupancy(zoneId: 101, freeCount: 3),
        _mockOccupancy(zoneId: 102, freeCount: 0),
        _mockOccupancy(zoneId: 103, freeCount: 1),
      ]));
    }
    if (method == 'GET' && path.startsWith('/forecasts')) {
      return handler.resolve(_response(options, [
        _mockForecast(zoneId: 101, predictedFreeCount: 4, confidence: 0.85),
        _mockForecast(zoneId: 103, predictedFreeCount: 2, confidence: 0.71),
      ]));
    }
    if (method == 'POST' && path == '/routing/search') {
      return handler.resolve(_response(options, {
        'mode': 'find_parking',
        'provider': 'mock',
        'generated_at': '2024-01-01T12:00:00Z',
        'selected_zone_id': 101,
        'total_candidates': 2,
        'candidates': [
          {
            'zone_id': 101,
            'rank': 1,
            'current_free_count': 5,
            'current_confidence': 0.87,
            'pay': 0,
            'distance_to_destination_meters': 150,
            'duration_from_origin_seconds': 420,
            'predicted_free_count': 4,
            'route_geometry': null,
          },
          {
            'zone_id': 102,
            'rank': 2,
            'current_free_count': 2,
            'current_confidence': 0.72,
            'pay': 100,
            'distance_to_destination_meters': 280,
            'duration_from_origin_seconds': 540,
            'predicted_free_count': 1,
            'route_geometry': null,
          },
        ],
      }));
    }
    if (method == 'POST' && path == '/routing/new') {
      final body = options.data as Map<String, dynamic>? ?? {};
      final zoneId = body['selected_zone_id'] as int? ?? 101;
      final zone = zoneId == 102
          ? {'lat': 55.7495, 'lon': 37.622, 'time': '14:37'}
          : {'lat': 55.7520, 'lon': 37.612, 'time': '14:35'};
      return handler.resolve(_response(options, {
        'route_id': zoneId,
        'status': 'active',
        'mode': 'find_parking',
        'selected_zone_id': zoneId,
        'arrival_time': zone['time'],
        'deeplink_url':
            'yandexnavi://build_route_on_map?lat_to=${zone['lat']}&lon_to=${zone['lon']}&appmetrica_tracking_id=1178268795219767552',
      }));
    }

    handler.next(options);
  }

  Response<dynamic> _response(RequestOptions options, dynamic data) {
    return Response(
      requestOptions: options,
      statusCode: 200,
      data: data,
    );
  }

  Map<String, dynamic> _authPayload(String email, String name) => {
        'access_token': 'mock-token-${DateTime.now().millisecondsSinceEpoch}',
        'expires_in': 86400,
        'user': _userPayload(email, name),
      };

  Map<String, dynamic> _mockZone({
    required int zoneId,
    required String zoneType,
    required int freeCount,
    required int pay,
    required List<List<double>> ring,
  }) {
    return {
      'zone_id': zoneId,
      'zone_type': zoneType,
      'capacity': 20,
      'free_count': freeCount,
      'confidence': 0.9,
      'pay': pay,
      'geometry': {
        'type': 'Polygon',
        'coordinates': [ring],
      },
      'is_active': true,
      'location_type': 'street',
      'is_private': false,
      'is_accessible': true,
      'confidence_level': 'high',
    };
  }

  Map<String, dynamic> _userPayload(String email, String name) => {
        'user_id': 1,
        'email': email,
        'full_name': name,
        'global_roles': ['user'],
      };

  Map<String, dynamic> _mockOccupancy({
    required int zoneId,
    required int freeCount,
  }) =>
      {
        'zone_id': zoneId,
        'zone_type': 'standard',
        'capacity': 20,
        'free_count': freeCount,
        'confidence': 0.9,
        'pay': 0,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [30.398, 59.733],
              [30.402, 59.733],
              [30.402, 59.737],
              [30.398, 59.737],
              [30.398, 59.733],
            ]
          ],
        },
        'observed_at': '2024-01-01T12:00:00Z',
      };

  Map<String, dynamic> _mockForecast({
    required int zoneId,
    required int predictedFreeCount,
    required double confidence,
  }) =>
      {
        'zone_id': zoneId,
        'predicted_free_count': predictedFreeCount,
        'confidence': confidence,
      };
}
