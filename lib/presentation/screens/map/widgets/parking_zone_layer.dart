import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../../../domain/models/zone.dart';
import '../../../../core/constants.dart';
import '../../../../core/theme/app_colors.dart';

List<MapObject> buildZoneMapObjects({
  required List<Zone> zones,
  required void Function(Zone) onTap,
  Set<int> highlightedIds = const {},
}) {
  final result = <MapObject>[];
  for (final zone in zones) {
    if (_isDegenerate(zone.geometry)) continue;
    final color = zoneColor(zone);
    final highlighted = highlightedIds.contains(zone.zoneId);
    if (zone.zoneType == ZoneType.parallel) {
      result.add(_buildParallelLine(zone, color, onTap, highlighted: highlighted));
    } else {
      result.add(_buildPolygon(zone, color, onTap, highlighted: highlighted));
    }
  }
  return result;
}

List<MapObject> buildHighlightZone(List<Zone> zones, int zoneId) {
  final matches = zones.where((z) => z.zoneId == zoneId && !_isDegenerate(z.geometry));
  if (matches.isEmpty) return [];
  final zone = matches.first;
  final color = zoneColor(zone);
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
        strokeColor: Colors.white,
        strokeWidth: 10,
      ),
      PolylineMapObject(
        mapId: MapObjectId('zone_highlight_inner_${zone.zoneId}'),
        polyline: Polyline(points: [mid1, mid2]),
        strokeColor: color,
        strokeWidth: 6,
      ),
    ];
  } else {
    return [
      PolygonMapObject(
        mapId: MapObjectId('zone_highlight_${zone.zoneId}'),
        polygon: Polygon(outerRing: LinearRing(points: zone.geometry), innerRings: []),
        fillColor: color.withValues(alpha: 0.6),
        strokeColor: Colors.white,
        strokeWidth: 4,
      ),
    ];
  }
}

MapObject buildZoneLabels({
  required List<Zone> zones,
  required Map<int, Uint8List> bitmapCache,
  required Map<int, Zone> zonesById,
  ClusterTapCallback? onClusterTap,
}) {
  final placemarks = zones
      .where((z) => !_isDegenerate(z.geometry) && bitmapCache.containsKey(z.zoneId))
      .map((zone) => PlacemarkMapObject(
            mapId: MapObjectId('zone_label_${zone.zoneId}'),
            point: centroid(zone.geometry),
            opacity: 1.0,
            icon: PlacemarkIcon.single(PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(bitmapCache[zone.zoneId]!),
              scale: 1.0,
            )),
          ))
      .toList();

  return ClusterizedPlacemarkCollection(
    mapId: const MapObjectId('zone_labels'),
    placemarks: placemarks,
    radius: 60,
    minZoom: 15,
    onClusterTap: onClusterTap,
    onClusterAdded: (collection, cluster) async {
      final zoneIds = cluster.placemarks
          .map((p) => int.tryParse(p.mapId.value.replaceFirst('zone_label_', '')))
          .whereType<int>()
          .toList();
      final totalFree = zoneIds
          .map((id) => zonesById[id]?.freeCount ?? 0)
          .fold(0, (a, b) => a + b);
      final hasForecast = zoneIds.any((id) => zonesById[id]?.hasForecast == true);
      final Color clusterColor;
      if (!hasForecast) {
        clusterColor = AppColors.parkingUnknown;
      } else if (totalFree == 0) {
        clusterColor = AppColors.parkingFull;
      } else {
        clusterColor = AppColors.primary;
      }
      final bytes = await buildClusterBitmap(totalFree, cluster.placemarks.length, clusterColor);
      return cluster.copyWith(
        appearance: cluster.appearance.copyWith(
          opacity: 1.0,
          icon: PlacemarkIcon.single(PlacemarkIconStyle(
            image: BitmapDescriptor.fromBytes(bytes),
            scale: 1.0,
          )),
        ),
      );
    },
  );
}

Future<Uint8List> buildCountBitmap(int count, Color color) async {
  const size = 72.0;
  final center = Offset(size / 2, size / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // White outer ring for contrast against any map background
  canvas.drawCircle(center, size / 2 - 1, Paint()..color = Colors.white);
  // Colored fill
  canvas.drawCircle(center, size / 2 - 3, Paint()..color = color);
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
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Uint8List> buildClusterBitmap(int totalFree, int clusterSize, Color color) async {
  const size = 84.0;
  final center = Offset(size / 2, size / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(center, size / 2 - 1, Paint()..color = Colors.white);
  canvas.drawCircle(center, size / 2 - 4, Paint()..color = color);
  final label = clusterSize <= 1 ? '$totalFree' : '$totalFree\n($clusterSize)';
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

Color zoneColor(Zone zone) {
  if (!zone.isActive || zone.geometry.isEmpty) return AppColors.parkingUnknown;
  if (!zone.hasForecast) return AppColors.parkingUnknown;
  if (zone.freeCount == 0) return AppColors.parkingFull;
  if (zone.freeCount == 1) return AppColors.parkingOne;
  if (zone.confidence >= kConfidenceThreshold) return AppColors.parkingFewHigh;
  return AppColors.parkingFewLow;
}

MapObject _buildPolygon(Zone zone, Color color, void Function(Zone) onTap,
    {bool highlighted = false}) {
  return PolygonMapObject(
    mapId: MapObjectId('zone_polygon_${zone.zoneId}'),
    polygon: Polygon(
      outerRing: LinearRing(points: zone.geometry),
      innerRings: [],
    ),
    fillColor: color.withValues(alpha: 0.5),
    strokeColor: highlighted ? Colors.white : color,
    strokeWidth: highlighted ? 4 : 2,
    onTap: (_, __) => onTap(zone),
  );
}

MapObject _buildParallelLine(Zone zone, Color color, void Function(Zone) onTap,
    {bool highlighted = false}) {
  final points = zone.geometry;
  if (points.length < 4) return _buildPolygon(zone, color, onTap);

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
    strokeColor: highlighted ? Colors.white : color,
    strokeWidth: highlighted ? 9 : 6,
    onTap: (_, __) => onTap(zone),
  );
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
  final pts = points.length > 1 &&
          points.first.latitude == points.last.latitude &&
          points.first.longitude == points.last.longitude
      ? points.sublist(0, points.length - 1)
      : points;
  final lat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
  final lon = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
  return Point(latitude: lat, longitude: lon);
}
