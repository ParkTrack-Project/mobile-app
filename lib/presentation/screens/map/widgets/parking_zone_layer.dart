import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../../../domain/models/zone.dart';
import '../../../../core/constants.dart';
import '../../../../core/theme/app_colors.dart';

final Map<({int? totalFree, int clusterSize, int color}), Future<Uint8List>>
_clusterBitmapCache = {};

class ParkingMarkerState {
  const ParkingMarkerState({
    required this.activeIds,
    required this.mutedResultIds,
    required this.contextIds,
  });

  final Set<int> activeIds;
  final Set<int> mutedResultIds;
  final Set<int> contextIds;
}

ParkingMarkerState resolveParkingMarkerState({
  required Set<int> allIds,
  required Set<int> resultIds,
  int? selectedId,
}) {
  if (selectedId != null && allIds.contains(selectedId)) {
    return ParkingMarkerState(
      activeIds: Set.unmodifiable({selectedId}),
      mutedResultIds: Set.unmodifiable(resultIds.difference({selectedId})),
      contextIds: Set.unmodifiable(
        allIds.difference({selectedId}).difference(resultIds),
      ),
    );
  }
  if (resultIds.isEmpty) {
    return ParkingMarkerState(
      activeIds: Set.unmodifiable(allIds),
      mutedResultIds: const {},
      contextIds: const {},
    );
  }
  return ParkingMarkerState(
    activeIds: Set.unmodifiable(resultIds),
    mutedResultIds: const {},
    contextIds: Set.unmodifiable(allIds.difference(resultIds)),
  );
}

Future<Uint8List> _cachedClusterBitmap(
  int? totalFree,
  int clusterSize,
  Color color,
) {
  final key = (
    totalFree: totalFree,
    clusterSize: clusterSize,
    color: color.toARGB32(),
  );
  if (_clusterBitmapCache.length > 128) _clusterBitmapCache.clear();
  return _clusterBitmapCache.putIfAbsent(
    key,
    () => buildClusterBitmap(totalFree, clusterSize, color),
  );
}

List<MapObject> buildZoneMapObjects({
  required List<Zone> zones,
  required void Function(Zone) onTap,
  Set<int> resultIds = const {},
  int? selectedId,
  Brightness brightness = Brightness.light,
}) {
  final result = <MapObject>[];
  final markerState = resolveParkingMarkerState(
    allIds: zones.map((zone) => zone.zoneId).toSet(),
    resultIds: resultIds,
    selectedId: selectedId,
  );
  for (final zone in zones) {
    if (_isDegenerate(zone.geometry)) continue;
    final color = zoneColor(zone, brightness: brightness);
    final isSelected = selectedId == zone.zoneId;
    final opacity = markerState.activeIds.contains(zone.zoneId) ? 1.0 : 0.22;
    if (zone.zoneType == ZoneType.parallel) {
      result.add(
        _buildParallelLine(
          zone,
          color,
          onTap,
          highlighted: isSelected,
          opacity: opacity,
        ),
      );
    } else {
      result.add(
        _buildPolygon(
          zone,
          color,
          onTap,
          highlighted: isSelected,
          opacity: opacity,
        ),
      );
    }
  }
  return result;
}

List<MapObject> buildHighlightZone(
  List<Zone> zones,
  int zoneId, {
  Brightness brightness = Brightness.light,
}) {
  final matches = zones.where(
    (z) => z.zoneId == zoneId && !_isDegenerate(z.geometry),
  );
  if (matches.isEmpty) return [];
  final zone = matches.first;
  final color = zoneColor(zone, brightness: brightness);
  if (zone.zoneType == ZoneType.parallel) {
    final points = zone.geometry;
    if (points.length < 4) return [];
    final len01 = _distance(points[0], points[1]);
    final len12 = _distance(points[1], points[2]);
    final Point mid1, mid2;
    if (len01 <= len12) {
      mid1 = _midpoint(points[0], points[1]);
      mid2 = _midpoint(points[2], points[3]);
    } else {
      mid1 = _midpoint(points[1], points[2]);
      mid2 = _midpoint(points[3], points[0]);
    }
    return [
      PolylineMapObject(
        mapId: MapObjectId('zone_highlight_${zone.zoneId}'),
        polyline: Polyline(points: [mid1, mid2]),
        strokeColor: color,
        strokeWidth: 12,
      ),
    ];
  } else {
    return [
      PolygonMapObject(
        mapId: MapObjectId('zone_highlight_${zone.zoneId}'),
        polygon: Polygon(
          outerRing: LinearRing(points: zone.geometry),
          innerRings: [],
        ),
        fillColor: color.withValues(alpha: 0.5),
        strokeColor: color,
        strokeWidth: 4,
      ),
    ];
  }
}

MapObject buildZoneLabels({
  required List<Zone> zones,
  required Map<int, Uint8List> bitmapCache,
  required Map<int, Zone> zonesById,
  Set<int> resultIds = const {},
  int? selectedId,
  ClusterTapCallback? onClusterTap,
  void Function(Zone)? onZoneTap,
  Brightness brightness = Brightness.light,
}) {
  final placemarks = zones
      .where(
        (z) => !_isDegenerate(z.geometry) && bitmapCache.containsKey(z.zoneId),
      )
      .map(
        (zone) => PlacemarkMapObject(
          mapId: MapObjectId('zone_label_${zone.zoneId}'),
          point: centroid(zone.geometry),
          opacity: _zoneOpacity(zone.zoneId, resultIds, selectedId),
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(bitmapCache[zone.zoneId]!),
              scale: 1.0,
              zIndex: zone.zoneId == selectedId
                  ? 20
                  : resultIds.contains(zone.zoneId)
                  ? 10
                  : 0,
            ),
          ),
          onTap: onZoneTap != null ? (_, _) => onZoneTap(zone) : null,
        ),
      )
      .toList();

  return ClusterizedPlacemarkCollection(
    mapId: const MapObjectId('zone_labels'),
    placemarks: placemarks,
    radius: 60,
    minZoom: 15,
    onClusterTap: onClusterTap,
    onClusterAdded: (collection, cluster) async {
      final zoneIds = cluster.placemarks
          .map(
            (p) => int.tryParse(p.mapId.value.replaceFirst('zone_label_', '')),
          )
          .whereType<int>()
          .toList();
      final opacity = zoneIds.contains(selectedId)
          ? 1.0
          : selectedId != null
          ? 0.22
          : resultIds.isNotEmpty &&
                !zoneIds.any((zoneId) => resultIds.contains(zoneId))
          ? 0.22
          : 1.0;
      final hasForecast = zoneIds.any(
        (id) => zonesById[id]?.hasForecast == true,
      );
      final int? totalFree = hasForecast
          ? zoneIds
                .where((id) => zonesById[id]?.hasForecast == true)
                .map((id) => zonesById[id]?.freeCount ?? 0)
                .fold<int>(0, (a, b) => a + b)
          : null;
      final Color clusterColor;
      if (totalFree == null) {
        clusterColor = AppColors.parkingUnknown;
      } else if (totalFree == 0) {
        clusterColor = AppColors.parkingFull;
      } else {
        clusterColor = brightness == Brightness.dark
            ? const Color(0xFF00C968)
            : AppColors.primary;
      }
      final bytes = await _cachedClusterBitmap(
        totalFree,
        cluster.placemarks.length,
        clusterColor,
      );
      return cluster.copyWith(
        appearance: cluster.appearance.copyWith(
          opacity: opacity,
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(bytes),
              scale: 1.0,
            ),
          ),
        ),
      );
    },
  );
}

Future<Uint8List> buildCountBitmap(int? count, Color color) async {
  const size = 72.0;
  final center = Offset(size / 2, size / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(center, size / 2 - 1, Paint()..color = Colors.white);
  canvas.drawCircle(center, size / 2 - 3, Paint()..color = color);
  if (count != null) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Uint8List> buildClusterBitmap(
  int? totalFree,
  int clusterSize,
  Color color,
) async {
  const size = 84.0;
  final center = Offset(size / 2, size / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(
    center,
    size / 2 - 1,
    Paint()..color = Colors.white.withValues(alpha: 0.82),
  );
  canvas.drawCircle(center, size / 2 - 8, Paint()..color = color);
  final String label;
  if (totalFree == null) {
    label = '$clusterSize';
  } else {
    label = '$totalFree';
  }
  final textPainter = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        height: 1.2,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: size - 10);
  textPainter.paint(
    canvas,
    Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

bool _isDegenerate(List<Point> points) {
  if (points.length < 3) return true;
  final lat0 = points.first.latitude;
  final lon0 = points.first.longitude;
  return points.every((p) => p.latitude == lat0 && p.longitude == lon0);
}

Color zoneColor(Zone zone, {Brightness brightness = Brightness.light}) {
  if (!zone.isActive || zone.geometry.isEmpty) return AppColors.parkingUnknown;
  if (!zone.hasForecast) return AppColors.parkingUnknown;
  final isDark = brightness == Brightness.dark;
  if (zone.freeCount == 0) {
    return isDark ? const Color(0xFFFF5D52) : AppColors.parkingFull;
  }
  if (zone.freeCount == 1) {
    return isDark ? const Color(0xFFFFC400) : const Color(0xFFC68A00);
  }
  if (zone.confidence >= kConfidenceThreshold) {
    return isDark ? const Color(0xFF00C968) : AppColors.parkingFewHigh;
  }
  return isDark ? const Color(0xFF48D986) : AppColors.parkingFewLow;
}

MapObject _buildPolygon(
  Zone zone,
  Color color,
  void Function(Zone) onTap, {
  bool highlighted = false,
  double opacity = 1,
}) {
  return PolygonMapObject(
    mapId: MapObjectId('zone_polygon_${zone.zoneId}'),
    polygon: Polygon(
      outerRing: LinearRing(points: zone.geometry),
      innerRings: [],
    ),
    fillColor: color.withValues(alpha: 0.5 * opacity),
    strokeColor: color.withValues(alpha: opacity),
    strokeWidth: highlighted ? 4 : 2,
    onTap: (_, _) => onTap(zone),
  );
}

MapObject _buildParallelLine(
  Zone zone,
  Color color,
  void Function(Zone) onTap, {
  bool highlighted = false,
  double opacity = 1,
}) {
  final points = zone.geometry;
  if (points.length < 4) {
    return _buildPolygon(zone, color, onTap, opacity: opacity);
  }

  final len01 = _distance(points[0], points[1]);
  final len12 = _distance(points[1], points[2]);

  final Point mid1, mid2;
  if (len01 <= len12) {
    // стороны 0→1 и 2→3 — короткие (торцы ряда)
    mid1 = _midpoint(points[0], points[1]);
    mid2 = _midpoint(points[2], points[3]);
  } else {
    // стороны 1→2 и 3→0 — короткие (торцы ряда)
    mid1 = _midpoint(points[1], points[2]);
    mid2 = _midpoint(points[3], points[0]);
  }

  return PolylineMapObject(
    mapId: MapObjectId('zone_line_${zone.zoneId}'),
    polyline: Polyline(points: [mid1, mid2]),
    strokeColor: color.withValues(alpha: opacity),
    strokeWidth: highlighted ? 12 : 6,
    onTap: (_, _) => onTap(zone),
  );
}

double _zoneOpacity(int zoneId, Set<int> resultIds, int? selectedId) {
  if (selectedId != null) {
    if (zoneId == selectedId) return 1;
    return 0.22;
  }
  if (resultIds.isNotEmpty && !resultIds.contains(zoneId)) return 0.22;
  return 1;
}

double _distance(Point a, Point b) {
  final dlat = a.latitude - b.latitude;
  final dlon = a.longitude - b.longitude;
  return math.sqrt(dlat * dlat + dlon * dlon);
}

Point _midpoint(Point a, Point b) => Point(
  latitude: (a.latitude + b.latitude) / 2,
  longitude: (a.longitude + b.longitude) / 2,
);

Point centroid(List<Point> points) {
  final pts =
      points.length > 1 &&
          points.first.latitude == points.last.latitude &&
          points.first.longitude == points.last.longitude
      ? points.sublist(0, points.length - 1)
      : points;
  final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
  final lon = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
  return Point(latitude: lat, longitude: lon);
}
