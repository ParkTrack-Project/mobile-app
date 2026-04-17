import 'package:freezed_annotation/freezed_annotation.dart';

part 'zone_models.freezed.dart';
part 'zone_models.g.dart';

@freezed
class ZoneMapItemDto with _$ZoneMapItemDto {
  const factory ZoneMapItemDto({
    required int zoneId,
    required String zoneType,
    required int capacity,
    required int freeCount,
    required double confidence,
    required int pay,
    required Map<String, dynamic> geometry,
    @Default(true) bool isActive,
    String? locationType,
    bool? isPrivate,
    bool? isAccessible,
    String? confidenceLevel,
    String? occupancyUpdatedAt,
  }) = _ZoneMapItemDto;

  factory ZoneMapItemDto.fromJson(Map<String, dynamic> json) =>
      _$ZoneMapItemDtoFromJson(json);
}

@freezed
class ZoneDto with _$ZoneDto {
  const factory ZoneDto({
    required int zoneId,
    required String zoneType,
    required int capacity,
    required int freeCount,
    required double confidence,
    required int pay,
    required Map<String, dynamic> geometry,
    @Default(true) bool isActive,
    String? locationType,
    bool? isPrivate,
    bool? isAccessible,
    String? confidenceLevel,
    String? occupancyUpdatedAt,
    int? cameraId,
    int? partnerId,
    String? createdAt,
    String? updatedAt,
  }) = _ZoneDto;

  factory ZoneDto.fromJson(Map<String, dynamic> json) =>
      _$ZoneDtoFromJson(json);
}
