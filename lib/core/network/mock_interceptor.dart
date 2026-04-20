import 'package:dio/dio.dart';

const bool kUseMocks = true;

class MockInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    final path = options.path;

    if (method == 'POST' && path == '/auth/register') {
      return handler.resolve(_response(options, _authPayload('registered@mock.dev', 'Новый пользователь')));
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
            [37.611, 55.7515],
            [37.613, 55.7515],
            [37.613, 55.7525],
            [37.611, 55.7525],
            [37.611, 55.7515],
          ],
        ),
        _mockZone(
          zoneId: 102,
          zoneType: 'standard',
          freeCount: 2,
          pay: 100,
          ring: [
            [37.621, 55.749],
            [37.623, 55.749],
            [37.623, 55.750],
            [37.621, 55.750],
            [37.621, 55.749],
          ],
        ),
      ]));
    }

    if (method == 'GET' && path.startsWith('/occupancy')) {
      return handler.resolve(_response(options, []));
    }
    if (method == 'GET' && path.startsWith('/forecasts')) {
      return handler.resolve(_response(options, []));
    }
    if (method == 'POST' && path == '/routing/search') {
      return handler.resolve(_response(options, {
        'mode': 'find_parking',
        'provider': 'mock',
        'generatedAt': '2024-01-01T12:00:00Z',
        'selectedZoneId': 101,
        'totalCandidates': 2,
        'candidates': [
          {
            'zoneId': 101,
            'rank': 1,
            'freeCount': 5,
            'confidence': 0.87,
            'pay': 0,
            'distanceToDestinationMeters': 150,
            'durationFromOriginSeconds': 420,
            'predictedFreeCount': 4,
            'eta': '14:35',
            'routeGeometry': null,
          },
          {
            'zoneId': 102,
            'rank': 2,
            'freeCount': 2,
            'confidence': 0.72,
            'pay': 100,
            'distanceToDestinationMeters': 280,
            'durationFromOriginSeconds': 540,
            'predictedFreeCount': 1,
            'eta': '14:37',
            'routeGeometry': null,
          },
        ],
      }));
    }
    if (method == 'POST' && path == '/routing/new') {
      return handler.resolve(_response(options, {
        'routeId': 1,
        'status': 'active',
        'mode': 'find_parking',
        'selectedZoneId': 101,
        'arrivalTime': '14:35',
        'deeplinkUrl':
            'yandexnavi://build_route_on_map?lat_to=55.7558&lon_to=37.6173&appmetrica_tracking_id=1178268795219767552',
        'routeGeometry': null,
        'candidates': [],
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
        'accessToken': 'mock-token-123',
        'expiresIn': 86400,
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
      'zoneId': zoneId,
      'zoneType': zoneType,
      'capacity': 20,
      'freeCount': freeCount,
      'confidence': 0.9,
      'pay': pay,
      'geometry': {
        'type': 'Polygon',
        'coordinates': [ring],
      },
      'isActive': true,
      'locationType': 'street',
      'isPrivate': false,
      'isAccessible': true,
      'confidenceLevel': 'high',
    };
  }

  Map<String, dynamic> _userPayload(String email, String name) => {
        'userId': 1,
        'email': email,
        'fullName': name,
        'globalRoles': ['user'],
      };
}
