import 'dart:convert';
import 'dart:js_interop';

import 'package:yandex_mapkit/yandex_mapkit.dart';

import 'yandex_web_route_models.dart';

@JS('parkTrackYandexMaps.route')
external JSPromise<JSString> _requestRoute(
  JSNumber fromLatitude,
  JSNumber fromLongitude,
  JSNumber toLatitude,
  JSNumber toLongitude,
);

Future<YandexWebRoute?> requestYandexWebRoute({
  required double fromLatitude,
  required double fromLongitude,
  required double toLatitude,
  required double toLongitude,
}) async {
  final response = await _requestRoute(
    fromLatitude.toJS,
    fromLongitude.toJS,
    toLatitude.toJS,
    toLongitude.toJS,
  ).toDart.timeout(const Duration(seconds: 10));
  final value = jsonDecode(response.toDart) as Map<String, dynamic>;
  final rawPoints = value['points'] as List<dynamic>? ?? const [];
  final points = rawPoints
      .map((rawPoint) {
        final point = rawPoint as List<dynamic>;
        return Point(
          latitude: (point[0] as num).toDouble(),
          longitude: (point[1] as num).toDouble(),
        );
      })
      .toList(growable: false);
  if (points.length < 2) return null;
  return YandexWebRoute(
    points: points,
    durationSeconds: (value['duration'] as num?)?.toDouble() ?? 0,
    distanceMeters: (value['distance'] as num?)?.toDouble() ?? 0,
  );
}
