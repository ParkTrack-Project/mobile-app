import 'package:freezed_annotation/freezed_annotation.dart';

part 'routing_models.freezed.dart';
part 'routing_models.g.dart';

@freezed
class RoutingSearchRequestDto with _$RoutingSearchRequestDto {
  const factory RoutingSearchRequestDto({
    required String mode,
    required LocationDto origin,
    LocationDto? destination,
    int? maxPay,
    int? minFreeCount,
    double? minConfidence,
    int? maxDistanceToDestinationMeters,
    bool? useForecast,
    @Default(5) int limit,
  }) = _RoutingSearchRequestDto;

  factory RoutingSearchRequestDto.fromJson(Map<String, dynamic> json) =>
      _$RoutingSearchRequestDtoFromJson(json);
}

@freezed
class LocationDto with _$LocationDto {
  const factory LocationDto({
    required double latitude,
    required double longitude,
  }) = _LocationDto;

  factory LocationDto.fromJson(Map<String, dynamic> json) =>
      _$LocationDtoFromJson(json);
}

@freezed
class RoutingSearchResponseDto with _$RoutingSearchResponseDto {
  const factory RoutingSearchResponseDto({
    required String mode,
    required String provider,
    required String generatedAt,
    int? selectedZoneId,
    required int totalCandidates,
    required List<RouteCandidateDto> candidates,
  }) = _RoutingSearchResponseDto;

  factory RoutingSearchResponseDto.fromJson(Map<String, dynamic> json) =>
      _$RoutingSearchResponseDtoFromJson(json);
}

@freezed
class RouteCandidateDto with _$RouteCandidateDto {
  const factory RouteCandidateDto({
    required int zoneId,
    required int rank,
    required int freeCount,
    required double confidence,
    required int pay,
    int? distanceToDestinationMeters,
    int? durationFromOriginSeconds,
    int? predictedFreeCount,
    String? eta,
    Map<String, dynamic>? routeGeometry,
  }) = _RouteCandidateDto;

  factory RouteCandidateDto.fromJson(Map<String, dynamic> json) =>
      _$RouteCandidateDtoFromJson(json);
}

@freezed
class RouteDto with _$RouteDto {
  const factory RouteDto({
    required int routeId,
    required String status,
    required String mode,
    int? selectedZoneId,
    String? arrivalTime,
    String? deeplinkUrl,
    Map<String, dynamic>? routeGeometry,
    List<RouteCandidateDto>? candidates,
  }) = _RouteDto;

  factory RouteDto.fromJson(Map<String, dynamic> json) =>
      _$RouteDtoFromJson(json);
}
