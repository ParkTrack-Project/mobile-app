import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import '../../../../domain/models/zone.dart';
import '../../../../core/constants.dart';

final Map<
  ({int totalFree, int clusterSize, int color, int textColor}),
  Future<Uint8List>
>
_clusterBitmapCache = {};

const double parkingCounterDimmedOpacity = 0.38;
const int _dimmedFillAlpha = 0x2E;
const int _dimmedStrokeAlpha = 0x5C;

class ParkingZoneColors {
  const ParkingZoneColors({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  ParkingZoneColors dimmed() => ParkingZoneColors(
    fill: fill.withAlpha(_dimmedFillAlpha),
    stroke: stroke.withAlpha(_dimmedStrokeAlpha),
  );
}

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
  int totalFree,
  int clusterSize,
  Color color,
  Color textColor,
) {
  final key = (
    totalFree: totalFree,
    clusterSize: clusterSize,
    color: color.toARGB32(),
    textColor: textColor.toARGB32(),
  );
  if (_clusterBitmapCache.length > 128) _clusterBitmapCache.clear();
  return _clusterBitmapCache.putIfAbsent(
    key,
    () => buildClusterBitmap(totalFree, clusterSize, color, textColor),
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
    final colors = parkingZoneColors(zone, brightness: brightness);
    final isSelected = selectedId == zone.zoneId;
    final displayedColors = markerState.activeIds.contains(zone.zoneId)
        ? colors
        : colors.dimmed();
    if (zone.zoneType == ZoneType.parallel) {
      result.add(
        _buildParallelLine(
          zone,
          displayedColors,
          onTap,
          highlighted: isSelected,
        ),
      );
    } else {
      result.add(
        _buildPolygon(zone, displayedColors, onTap, highlighted: isSelected),
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
  final colors = parkingZoneColors(zone, brightness: brightness);
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
        strokeColor: colors.stroke,
        strokeWidth: 8,
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
        fillColor: colors.fill,
        strokeColor: colors.stroke,
        strokeWidth: 3,
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
          ? parkingCounterDimmedOpacity
          : resultIds.isNotEmpty &&
                !zoneIds.any((zoneId) => resultIds.contains(zoneId))
          ? parkingCounterDimmedOpacity
          : 1.0;
      final totalFree = zoneIds
          .map((id) => zonesById[id])
          .whereType<Zone>()
          .where((zone) => zone.isActive)
          .map((zone) => math.max(0, zone.freeCount))
          .fold<int>(0, (a, b) => a + b);
      final clusterColor = parkingClusterColor(
        totalFree,
        brightness: brightness,
      );
      final textColor = brightness == Brightness.dark
          ? const Color(0xFF09090B)
          : Colors.white;
      final bytes = await _cachedClusterBitmap(
        totalFree,
        cluster.placemarks.length,
        clusterColor,
        textColor,
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

Future<Uint8List> buildCountBitmap(
  int? count,
  Color color, {
  Color textColor = Colors.white,
}) async {
  const height = 40.0;
  final label = count == null ? '' : '$count';
  final textPainter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: textColor,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = math.max(height, textPainter.width + 24);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(height / 2),
    ),
    Paint()..color = color,
  );
  if (label.isNotEmpty) {
    textPainter.paint(
      canvas,
      Offset(
        (width - textPainter.width) / 2,
        (height - textPainter.height) / 2,
      ),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width.ceil(), height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Uint8List> buildClusterBitmap(
  int totalFree,
  int clusterSize,
  Color color,
  Color textColor,
) async {
  final logicalSize = parkingClusterSize(clusterSize);
  final size = logicalSize * 2;
  final center = Offset(size / 2, size / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(center, size / 2 - 4, Paint()..color = color);
  canvas.drawCircle(
    center,
    size / 2 - 3,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  final label = '$totalFree';
  final textPainter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: textColor,
        fontSize: logicalSize >= 38 ? 26 : 22,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: size - 12);
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

ParkingZoneColors parkingZoneColors(
  Zone zone, {
  Brightness brightness = Brightness.light,
}) {
  final isDark = brightness == Brightness.dark;
  if (!zone.isActive) {
    return isDark
        ? const ParkingZoneColors(
            fill: Color(0xD9E4E4E7),
            stroke: Color(0xFFD4D4D8),
          )
        : const ParkingZoneColors(
            fill: Color(0x8C9CA3AF),
            stroke: Color(0xFF4B5563),
          );
  }
  if (zone.freeCount == 0) {
    return isDark
        ? const ParkingZoneColors(
            fill: Color(0xE6FF5252),
            stroke: Color(0xFFFF5252),
          )
        : const ParkingZoneColors(
            fill: Color(0x96D81616),
            stroke: Color(0xFFCD2B2B),
          );
  }
  if (zone.freeCount == 1) {
    return isDark
        ? const ParkingZoneColors(
            fill: Color(0xEBFFC107),
            stroke: Color(0xFFFFC107),
          )
        : const ParkingZoneColors(
            fill: Color(0x96F5AB0B),
            stroke: Color(0xFFB48409),
          );
  }
  if (zone.confidence >= kConfidenceThreshold) {
    return isDark
        ? const ParkingZoneColors(
            fill: Color(0xEB00E676),
            stroke: Color(0xFF00E676),
          )
        : const ParkingZoneColors(
            fill: Color(0xAA16A34A),
            stroke: Color(0xFF155E2A),
          );
  }
  return isDark
      ? const ParkingZoneColors(
          fill: Color(0xE04ADE80),
          stroke: Color(0xFF4ADE80),
        )
      : const ParkingZoneColors(
          fill: Color(0x9686EFAC),
          stroke: Color(0xFF2D8714),
        );
}

Color zoneColor(Zone zone, {Brightness brightness = Brightness.light}) =>
    parkingZoneColors(zone, brightness: brightness).stroke;

Color parkingClusterColor(
  int freeCount, {
  Brightness brightness = Brightness.light,
}) {
  if (brightness == Brightness.dark) {
    if (freeCount == 0) return const Color(0xFFFF5252);
    if (freeCount <= 2) return const Color(0xFFFFC107);
    return const Color(0xFF00E676);
  }
  if (freeCount == 0) return const Color(0xFFCD2B2B);
  if (freeCount <= 2) return const Color(0xFFB48409);
  return const Color(0xFF155E2A);
}

double parkingClusterSize(int zoneCount) =>
    math.min(28 + (zoneCount ~/ 4) * 4, 44).toDouble();

double parkingClusterExpansionZoom(
  List<Point> points,
  double currentZoom, {
  double radius = 60,
  double maxZoom = 21,
}) {
  if (points.length < 2) return math.min(maxZoom, currentZoom + 0.5);
  var zoom = ((currentZoom + 0.5) * 2).ceil() / 2;
  while (zoom < maxZoom &&
      _parkingClusterComponentCount(points, zoom, radius) < 2) {
    zoom += 0.5;
  }
  return zoom.clamp(currentZoom + 0.5, maxZoom);
}

double parkingIsolationZoom(
  Point selected,
  Iterable<Point> others, {
  double minimumZoom = 17.5,
  double maximumZoom = 20,
  double radius = 60,
}) {
  var zoom = minimumZoom;
  final otherPoints = others.toList(growable: false);
  while (zoom < maximumZoom) {
    final selectedPixel = _worldPixel(selected, zoom);
    final isolated = otherPoints.every((point) {
      final pixel = _worldPixel(point, zoom);
      return (pixel - selectedPixel).distance > radius;
    });
    if (isolated) return zoom;
    zoom += 0.5;
  }
  return maximumZoom;
}

int _parkingClusterComponentCount(
  List<Point> points,
  double zoom,
  double radius,
) {
  final parents = List<int>.generate(points.length, (index) => index);
  int root(int index) {
    while (parents[index] != index) {
      parents[index] = parents[parents[index]];
      index = parents[index];
    }
    return index;
  }

  void union(int left, int right) {
    final leftRoot = root(left);
    final rightRoot = root(right);
    if (leftRoot != rightRoot) parents[rightRoot] = leftRoot;
  }

  final pixels = points.map((point) => _worldPixel(point, zoom)).toList();
  for (var left = 0; left < pixels.length; left++) {
    for (var right = left + 1; right < pixels.length; right++) {
      if ((pixels[left] - pixels[right]).distance <= radius) {
        union(left, right);
      }
    }
  }
  return List<int>.generate(points.length, root).toSet().length;
}

Offset _worldPixel(Point point, double zoom) {
  final scale = 256 * math.pow(2, zoom);
  final latitude = point.latitude.clamp(-85.05112878, 85.05112878);
  final sinLatitude = math.sin(latitude * math.pi / 180);
  return Offset(
    ((point.longitude + 180) / 360) * scale,
    (0.5 - math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi)) *
        scale,
  );
}

MapObject _buildPolygon(
  Zone zone,
  ParkingZoneColors colors,
  void Function(Zone) onTap, {
  bool highlighted = false,
}) {
  return PolygonMapObject(
    mapId: MapObjectId('zone_polygon_${zone.zoneId}'),
    polygon: Polygon(
      outerRing: LinearRing(points: zone.geometry),
      innerRings: [],
    ),
    fillColor: colors.fill,
    strokeColor: colors.stroke,
    strokeWidth: highlighted ? 3 : 1,
    onTap: (_, _) => onTap(zone),
  );
}

MapObject _buildParallelLine(
  Zone zone,
  ParkingZoneColors colors,
  void Function(Zone) onTap, {
  bool highlighted = false,
}) {
  final points = zone.geometry;
  if (points.length < 4) {
    return _buildPolygon(zone, colors, onTap);
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
    strokeColor: colors.stroke,
    strokeWidth: highlighted ? 8 : 6,
    onTap: (_, _) => onTap(zone),
  );
}

double _zoneOpacity(int zoneId, Set<int> resultIds, int? selectedId) {
  if (selectedId != null) {
    if (zoneId == selectedId) return 1;
    return parkingCounterDimmedOpacity;
  }
  if (resultIds.isNotEmpty && !resultIds.contains(zoneId)) {
    return parkingCounterDimmedOpacity;
  }
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
