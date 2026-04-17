import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../api/zones_api.dart';
import '../api/occupancy_api.dart';
import '../api/forecasts_api.dart';
import '../models/zone_models.dart';
import '../../domain/models/zone.dart';

class ZonesRepository {
  final ZonesApi _zonesApi;
  final OccupancyApi _occupancyApi;
  final ForecastsApi _forecastsApi;

  ZonesRepository(this._zonesApi, this._occupancyApi, this._forecastsApi);

  Future<List<Zone>> getZonesNow(String bbox) async {
    final dtos = await _zonesApi.getZones(bbox: bbox, view: 'map');
    return dtos.map(_mapZone).toList();
  }

  Future<List<Zone>> getZonesPast(String bbox, DateTime at) async {
    final items = await _occupancyApi.getOccupancyMap(
      bbox: bbox,
      at: at.toUtc().toIso8601String(),
    );
    return items.map(_mapFromOccupancy).toList();
  }

  Future<List<Zone>> getZonesFuture(String bbox, DateTime at) async {
    final items = await _forecastsApi.getForecastsMap(
      bbox: bbox,
      at: at.toUtc().toIso8601String(),
    );
    return items.map(_mapFromForecast).toList();
  }

  Future<Zone> getZoneDetails(int zoneId) async {
    final dto = await _zonesApi.getZone(zoneId);
    return _mapFromFull(dto);
  }

  Zone _mapZone(ZoneMapItemDto dto) => Zone(
        zoneId: dto.zoneId,
        zoneType: _parseZoneType(dto.zoneType),
        capacity: dto.capacity,
        freeCount: dto.freeCount,
        confidence: dto.confidence,
        pay: dto.pay,
        geometry: _parseGeometry(dto.geometry),
        isActive: dto.isActive,
        locationType: _parseLocationType(dto.locationType),
        isPrivate: dto.isPrivate,
        isAccessible: dto.isAccessible,
        confidenceLevel: dto.confidenceLevel,
        occupancyUpdatedAt: dto.occupancyUpdatedAt != null
            ? DateTime.tryParse(dto.occupancyUpdatedAt!)
            : null,
      );

  Zone _mapFromFull(ZoneDto dto) => Zone(
        zoneId: dto.zoneId,
        zoneType: _parseZoneType(dto.zoneType),
        capacity: dto.capacity,
        freeCount: dto.freeCount,
        confidence: dto.confidence,
        pay: dto.pay,
        geometry: _parseGeometry(dto.geometry),
        isActive: dto.isActive,
        locationType: _parseLocationType(dto.locationType),
        isPrivate: dto.isPrivate,
        isAccessible: dto.isAccessible,
        confidenceLevel: dto.confidenceLevel,
        occupancyUpdatedAt: dto.occupancyUpdatedAt != null
            ? DateTime.tryParse(dto.occupancyUpdatedAt!)
            : null,
      );

  Zone _mapFromOccupancy(Map<String, dynamic> json) => Zone(
        zoneId: json['zone_id'] as int,
        zoneType: _parseZoneType(json['zone_type'] as String? ?? 'standard'),
        capacity: json['capacity'] as int? ?? 0,
        freeCount: json['free_count'] as int? ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        pay: json['pay'] as int? ?? 0,
        geometry: _parseGeometry(json['geometry'] as Map<String, dynamic>? ?? {}),
        isActive: true,
        occupancyUpdatedAt: json['observed_at'] != null
            ? DateTime.tryParse(json['observed_at'] as String)
            : null,
      );

  Zone _mapFromForecast(Map<String, dynamic> json) => Zone(
        zoneId: json['zone_id'] as int,
        zoneType: ZoneType.standard,
        capacity: json['capacity'] as int? ?? 0,
        freeCount: json['predicted_free_count'] as int? ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        pay: 0,
        geometry: _parseGeometry(json['geometry'] as Map<String, dynamic>? ?? {}),
        isActive: true,
      );

  ZoneType _parseZoneType(String type) =>
      type == 'parallel' ? ZoneType.parallel : ZoneType.standard;

  LocationType? _parseLocationType(String? type) => switch (type) {
        'street' => LocationType.street,
        'yard' => LocationType.yard,
        'open_lot' => LocationType.openLot,
        'underground' => LocationType.underground,
        'multilevel' => LocationType.multilevel,
        _ => null,
      };

  List<Point> _parseGeometry(Map<String, dynamic> geometry) {
    final coordinates = geometry['coordinates'];
    if (coordinates == null) return [];
    final ring = (coordinates as List).first as List;
    return ring.map((c) {
      final coord = c as List;
      // GeoJSON: [longitude, latitude] → Yandex: Point(latitude, longitude)
      return Point(latitude: (coord[1] as num).toDouble(), longitude: (coord[0] as num).toDouble());
    }).toList();
  }
}
