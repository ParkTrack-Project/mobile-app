import 'package:yandex_mapkit/yandex_mapkit.dart';

class YandexWebRoute {
  const YandexWebRoute({
    required this.points,
    required this.durationSeconds,
    required this.distanceMeters,
  });

  final List<Point> points;
  final double durationSeconds;
  final double distanceMeters;
}
