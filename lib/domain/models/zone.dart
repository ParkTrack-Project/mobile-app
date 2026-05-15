import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

part 'zone.freezed.dart';

enum ZoneType { parallel, standard }

enum LocationType { street, yard, openLot, underground, multilevel }

@freezed
class Zone with _$Zone {
  const factory Zone({
    required int zoneId,
    required ZoneType zoneType,
    required int capacity,
    required int freeCount,
    required double confidence,
    required int pay,
    required List<Point> geometry,
    @Default(true) bool isActive,
    @Default(true) bool hasForecast,
    LocationType? locationType,
    bool? isPrivate,
    bool? isAccessible,
    String? confidenceLevel,
    DateTime? occupancyUpdatedAt,
  }) = _Zone;
}
