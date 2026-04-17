import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../../../domain/models/zone.dart';
import '../../../../core/constants.dart';
import '../../../../core/theme/app_colors.dart';

List<MapObject> buildZoneMapObjects({
  required List<Zone> zones,
  required void Function(Zone) onTap,
}) {
  return zones.map((zone) {
    final color = _zoneColor(zone);
    if (zone.zoneType == ZoneType.parallel) {
      return _buildParallelLine(zone, color, onTap);
    } else {
      return _buildPolygon(zone, color, onTap);
    }
  }).toList();
}

Color _zoneColor(Zone zone) {
  if (!zone.isActive || zone.geometry.isEmpty) return AppColors.parkingUnknown;
  if (zone.freeCount == 0) return AppColors.parkingFull;
  if (zone.freeCount == 1) return AppColors.parkingOne;
  if (zone.confidence >= kConfidenceThreshold) return AppColors.parkingFewHigh;
  return AppColors.parkingFewLow;
}

MapObject _buildPolygon(Zone zone, Color color, void Function(Zone) onTap) {
  return PolygonMapObject(
    mapId: MapObjectId('zone_polygon_${zone.zoneId}'),
    polygon: Polygon(
      outerRing: LinearRing(points: zone.geometry),
      innerRings: [],
    ),
    fillColor: color.withOpacity(0.5),
    strokeColor: color,
    strokeWidth: 2,
    onTap: (_, __) => onTap(zone),
  );
}

MapObject _buildParallelLine(Zone zone, Color color, void Function(Zone) onTap) {
  final points = zone.geometry;
  if (points.length < 4) {
    return _buildPolygon(zone, color, onTap);
  }
  // Centers of short sides: midpoints of sides 0→1 and 2→3
  final mid1 = _midpoint(points[0], points[1]);
  final mid2 = _midpoint(points[2], points[3]);

  return PolylineMapObject(
    mapId: MapObjectId('zone_line_${zone.zoneId}'),
    polyline: Polyline(points: [mid1, mid2]),
    strokeColor: color,
    strokeWidth: 6,
    onTap: (_, __) => onTap(zone),
  );
}

Point _midpoint(Point a, Point b) => Point(
      latitude: (a.latitude + b.latitude) / 2,
      longitude: (a.longitude + b.longitude) / 2,
    );
