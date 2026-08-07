import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/api/forecasts_api.dart';
import 'package:mobile/data/api/occupancy_api.dart';
import 'package:mobile/data/api/zones_api.dart';

void main() {
  test(
    'occupancy keeps latest data and applies active filter conditionally',
    () async {
      final request = await _captureRequest(
        (dio) => OccupancyApi(dio).getOccupancyMap(
          bbox: '34.32714,61.81808,34.39237,61.76014',
          at: '2026-08-07T10:00:00Z',
          isActive: true,
        ),
      );

      expect(request.uri.path, '/occupancy');
      expect(request.uri.queryParameters['latest_only'], 'true');
      expect(request.uri.queryParameters['is_active'], 'true');
      _expectLiteralBbox(request);
    },
  );

  test(
    'forecasts keeps latest model and omits inactive filter when disabled',
    () async {
      final request = await _captureRequest(
        (dio) => ForecastsApi(dio).getForecastsMap(
          bbox: '34.32714,61.81808,34.39237,61.76014',
          at: '2026-08-09T10:00:00Z',
        ),
      );

      expect(request.uri.path, '/forecasts');
      expect(request.uri.queryParameters['latest_model_only'], 'true');
      expect(request.uri.queryParameters, isNot(contains('is_active')));
      _expectLiteralBbox(request);
    },
  );

  test(
    'zones uses the same literal bbox and conditional active filter',
    () async {
      final activeRequest = await _captureRequest(
        (dio) => ZonesApi(
          dio,
        ).getZones(bbox: '34.32714,61.81808,34.39237,61.76014', isActive: true),
      );
      final allRequest = await _captureRequest(
        (dio) =>
            ZonesApi(dio).getZones(bbox: '34.32714,61.81808,34.39237,61.76014'),
      );

      expect(activeRequest.uri.queryParameters['is_active'], 'true');
      expect(allRequest.uri.queryParameters, isNot(contains('is_active')));
      _expectLiteralBbox(activeRequest);
      _expectLiteralBbox(allRequest);
    },
  );
}

Future<RequestOptions> _captureRequest(
  Future<Object?> Function(Dio dio) execute,
) async {
  late RequestOptions captured;
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(Response(requestOptions: options, data: const []));
        },
      ),
    );

  await execute(dio);
  return captured;
}

void _expectLiteralBbox(RequestOptions request) {
  expect(
    request.uri.toString(),
    contains('bbox=34.32714,61.81808,34.39237,61.76014'),
  );
  expect(request.uri.toString(), isNot(contains('%2C')));
}
