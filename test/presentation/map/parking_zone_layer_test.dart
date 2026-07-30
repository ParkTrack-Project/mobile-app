import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/domain/models/zone.dart';
import 'package:mobile/presentation/screens/map/widgets/parking_zone_layer.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

Zone _zone(int id) => Zone(
  zoneId: id,
  zoneType: ZoneType.standard,
  capacity: 10,
  freeCount: 3,
  confidence: 0.9,
  pay: 0,
  geometry: const [
    Point(latitude: 1, longitude: 1),
    Point(latitude: 1, longitude: 2),
    Point(latitude: 2, longitude: 2),
  ],
);

Zone _zoneAt(
  int id, {
  required double latitude,
  required double longitude,
  int freeCount = 3,
  bool isActive = true,
}) {
  const epsilon = 0.000001;
  return Zone(
    zoneId: id,
    zoneType: ZoneType.standard,
    capacity: 1000,
    freeCount: freeCount,
    confidence: 0.9,
    pay: 0,
    isActive: isActive,
    geometry: [
      Point(latitude: latitude - epsilon, longitude: longitude - epsilon),
      Point(latitude: latitude - epsilon, longitude: longitude + epsilon),
      Point(latitude: latitude + 2 * epsilon, longitude: longitude),
    ],
  );
}

int _alpha(PolygonMapObject object) => object.fillColor.toARGB32() >>> 24;

void main() {
  test('resolves active, muted result, and context marker IDs', () {
    final results = resolveParkingMarkerState(
      allIds: {1, 2, 3, 4},
      resultIds: {1, 2, 3},
      selectedId: 2,
    );

    expect(results.activeIds, {2});
    expect(results.mutedResultIds, {1, 3});
    expect(results.contextIds, {4});
  });

  test('keeps selection mode when selected zone is outside the viewport', () {
    final results = resolveParkingMarkerState(
      allIds: {1, 3, 4},
      resultIds: const {},
      selectedId: 2,
    );

    expect(results.activeIds, isEmpty);
    expect(results.mutedResultIds, isEmpty);
    expect(results.contextIds, {1, 3, 4});
  });

  test('mutes zones outside results and keeps result zones active', () {
    final objects = buildZoneMapObjects(
      zones: [_zone(1), _zone(2)],
      resultIds: {1},
      onTap: (_) {},
    ).cast<PolygonMapObject>();

    expect(_alpha(objects[0]), greaterThan(_alpha(objects[1])));
  });

  test('mutes every zone except the selected result', () {
    final objects = buildZoneMapObjects(
      zones: [_zone(1), _zone(2)],
      resultIds: {1, 2},
      selectedId: 2,
      onTap: (_) {},
    ).cast<PolygonMapObject>();

    expect(_alpha(objects[1]), greaterThan(_alpha(objects[0])));
    expect(objects[1].strokeWidth, 3);
    expect(objects[1].strokeColor, zoneColor(_zone(2)));
  });

  test('mutes result and context zones equally after selection', () {
    final objects = buildZoneMapObjects(
      zones: [_zone(1), _zone(2), _zone(3)],
      resultIds: {1, 2},
      selectedId: 2,
      onTap: (_) {},
    ).cast<PolygonMapObject>();

    expect(_alpha(objects[1]), greaterThan(_alpha(objects[0])));
    expect(_alpha(objects[0]), _alpha(objects[2]));
  });

  test('direct map selection mutes every other zone', () {
    final objects = buildZoneMapObjects(
      zones: [_zone(1), _zone(2), _zone(3)],
      selectedId: 2,
      onTap: (_) {},
    ).cast<PolygonMapObject>();

    expect(_alpha(objects[1]), greaterThan(_alpha(objects[0])));
    expect(_alpha(objects[0]), _alpha(objects[2]));
    expect(objects[1].strokeWidth, objects[0].strokeWidth * 3);
  });

  test('uses a brighter parking palette on the dark map theme', () {
    final light = zoneColor(_zone(1), brightness: Brightness.light);
    final dark = zoneColor(_zone(1), brightness: Brightness.dark);

    expect(dark, isNot(light));
    expect(dark.computeLuminance(), greaterThan(light.computeLuminance()));
  });

  test('uses the project palette and exact dimmed geometry alphas', () {
    final active =
        buildZoneMapObjects(zones: [_zone(1)], onTap: (_) {}).single
            as PolygonMapObject;
    final dimmed =
        buildZoneMapObjects(
              zones: [_zone(1), _zone(2)],
              resultIds: {2},
              onTap: (_) {},
            ).first
            as PolygonMapObject;

    expect(active.fillColor, const Color(0xAA16A34A));
    expect(active.strokeColor, const Color(0xFF155E2A));
    expect(dimmed.fillColor.toARGB32() >>> 24, 0x66);
    expect(dimmed.strokeColor.toARGB32() >>> 24, 0xB3);
  });

  test('matches every light and dark semantic palette color', () {
    final inactive = _zone(1).copyWith(isActive: false);
    final full = _zone(2).copyWith(freeCount: 0);
    final one = _zone(3).copyWith(freeCount: 1);
    final lowConfidence = _zone(4).copyWith(freeCount: 2, confidence: 0.5);
    final highConfidence = _zone(5).copyWith(freeCount: 2, confidence: 0.9);

    expect(
      parkingZoneColors(inactive),
      isA<ParkingZoneColors>()
          .having((value) => value.fill, 'fill', const Color(0x8C9CA3AF))
          .having((value) => value.stroke, 'stroke', const Color(0xFF4B5563)),
    );
    expect(parkingZoneColors(full).fill, const Color(0x96D81616));
    expect(parkingZoneColors(full).stroke, const Color(0xFFCD2B2B));
    expect(parkingZoneColors(one).fill, const Color(0x96F5AB0B));
    expect(parkingZoneColors(one).stroke, const Color(0xFFB48409));
    expect(parkingZoneColors(lowConfidence).fill, const Color(0x9686EFAC));
    expect(parkingZoneColors(lowConfidence).stroke, const Color(0xFF2D8714));
    expect(parkingZoneColors(highConfidence).fill, const Color(0xAA16A34A));
    expect(parkingZoneColors(highConfidence).stroke, const Color(0xFF155E2A));

    expect(
      parkingZoneColors(inactive, brightness: Brightness.dark).fill,
      const Color(0xD9E4E4E7),
    );
    expect(
      parkingZoneColors(full, brightness: Brightness.dark).fill,
      const Color(0xE6FF5252),
    );
    expect(
      parkingZoneColors(one, brightness: Brightness.dark).fill,
      const Color(0xEBFFC107),
    );
    expect(
      parkingZoneColors(lowConfidence, brightness: Brightness.dark).fill,
      const Color(0xE04ADE80),
    );
    expect(
      parkingZoneColors(highConfidence, brightness: Brightness.dark).fill,
      const Color(0xEB00E676),
    );
  });

  test('single-link joins an A-B-C chain into one cluster', () {
    final zones = [
      _zoneAt(1, latitude: 0, longitude: 0),
      _zoneAt(2, latitude: 0, longitude: 0.0017),
      _zoneAt(3, latitude: 0, longitude: 0.0034),
    ];
    final result = clusterParkingZones(zones, 14);

    expect(result.clusters, hasLength(1));
    expect(result.clusters.single.zoneIds, {1, 2, 3});
    expect(result.singletonIds, isEmpty);
  });

  test('splits a connected group recursively when it exceeds the zoom cap', () {
    final degreesPerTwentyOnePixels = 21.5 * 360 / (256 * (1 << 6));
    final zones = List.generate(
      8,
      (index) => _zoneAt(
        index + 1,
        latitude: 0,
        longitude: index * degreesPerTwentyOnePixels,
        freeCount: 400,
      ),
    );
    final result = clusterParkingZones(zones, 6);

    expect(result.clusters, hasLength(4));
    expect(result.clusters.every((cluster) => cluster.totalFree <= 1400), true);
  });

  test('inactive zones join geometrically without increasing free sum', () {
    final result = clusterParkingZones([
      _zoneAt(1, latitude: 0, longitude: 0, freeCount: 50, isActive: false),
      _zoneAt(2, latitude: 0, longitude: 0.0001, freeCount: 3),
    ], 14);

    expect(result.clusters.single.totalFree, 3);
  });

  test('merges split bubbles again when their visual circles overlap', () {
    final degreesPerTenPixels = 10 * 360 / (256 * (1 << 12));
    final zones = List.generate(
      8,
      (index) => _zoneAt(
        index + 1,
        latitude: 0,
        longitude: index * degreesPerTenPixels,
        freeCount: 50,
      ),
    );
    final result = clusterParkingZones(zones, 12);

    expect(parkingClusterFreeCap(12), 150);
    expect(result.clusters, hasLength(1));
    expect(result.clusters.single.zoneCount, 8);
    expect(result.clusters.single.totalFree, 400);
  });

  test('cluster tap expands to the first display bucket that splits it', () {
    final zones = [
      _zoneAt(1, latitude: 0, longitude: 0),
      _zoneAt(2, latitude: 0, longitude: 0.002),
    ];
    final cluster = clusterParkingZones(zones, 13.7).clusters.single;
    final zoom = parkingClusterExpansionZoom(zones, cluster.zoneIds, 13.7);

    expect(zoom, 14);
    expect(clusterParkingZones(zones, zoom).singletonIds, {1, 2});
  });

  test(
    'cluster expansion keeps zooming until singleton badges are visible',
    () {
      final zones = [
        _zoneAt(1, latitude: 0, longitude: 0),
        _zoneAt(2, latitude: 0, longitude: 0.004),
      ];
      final cluster = clusterParkingZones(zones, 12).clusters.single;

      expect(parkingClusterExpansionZoom(zones, cluster.zoneIds, 12), 14);
    },
  );

  test('coincident centroids can only expand to maximum zoom', () {
    final zones = [
      _zoneAt(1, latitude: 1, longitude: 1),
      _zoneAt(2, latitude: 1, longitude: 1),
    ];

    expect(parkingClusterExpansionZoom(zones, {1, 2}, 14), 21);
  });

  test('renders every zone geometry independently from clustering', () {
    final objects = buildZoneMapObjects(
      zones: [_zone(1), _zone(2), _zone(3)],
      onTap: (_) {},
    );

    expect(objects, hasLength(3));
    expect(objects.map((object) => object.mapId.value), [
      'zone_polygon_1',
      'zone_polygon_2',
      'zone_polygon_3',
    ]);
  });

  test('allows zone taps only for ungrouped parking zones', () {
    final tappedIds = <int>[];
    final objects = buildZoneMapObjects(
      zones: [_zone(1), _zone(2)],
      tappableIds: {2},
      onTap: (zone) => tappedIds.add(zone.zoneId),
    ).cast<PolygonMapObject>().toList();

    expect(objects[0].onTap, isNull);
    expect(objects[1].onTap, isNotNull);
    objects[1].onTap!(objects[1], const Point(latitude: 1, longitude: 1));
    expect(tappedIds, [2]);
  });

  test(
    'uses 30 percent larger palette cluster sizes and native icon scale',
    () {
      expect(parkingClusterSize(2), 28 * parkingMarkerScaleFactor);
      expect(parkingClusterSize(4), 32 * parkingMarkerScaleFactor);
      expect(parkingClusterSize(8), 36 * parkingMarkerScaleFactor);
      expect(parkingClusterSize(12), 40 * parkingMarkerScaleFactor);
      expect(parkingClusterSize(16), 44 * parkingMarkerScaleFactor);
      expect(parkingClusterSize(100), 44 * parkingMarkerScaleFactor);
      expect(parkingClusterIconScale, 1);

      final zones = [
        _zoneAt(1, latitude: 0, longitude: 0),
        _zoneAt(2, latitude: 0, longitude: 0.0001),
      ];
      final clustering = clusterParkingZones(zones, 14);
      final cluster = clustering.clusters.single;
      final key = parkingClusterBitmapKey(cluster);
      final labels = buildZoneLabels(
        zones: zones,
        clustering: clustering,
        zoom: 14,
        bitmapCache: const {},
        clusterBitmapCache: {
          key: Uint8List.fromList([0]),
        },
        zonesById: {for (final zone in zones) zone.zoneId: zone},
      );
      final placemark = labels.single as PlacemarkMapObject;
      final style = placemark.icon!.toJson()['style'] as Map<String, dynamic>;

      expect(style['scale'], 1);
      expect(style['anchor'], {'dx': 0.5, 'dy': 0.5});
    },
  );

  test('shows a singleton badge only from zoom 14', () {
    final zone = _zone(1);
    const clustering = ParkingClusteringResult(
      zoom: 13.5,
      clusters: [],
      singletonIds: {1},
    );
    final cache = {
      1: Uint8List.fromList([0]),
    };

    expect(
      buildZoneLabels(
        zones: [zone],
        clustering: clustering,
        zoom: 13.5,
        bitmapCache: cache,
        clusterBitmapCache: const {},
        zonesById: {1: zone},
      ),
      isEmpty,
    );
    expect(
      buildZoneLabels(
        zones: [zone],
        clustering: clustering,
        zoom: 14,
        bitmapCache: cache,
        clusterBitmapCache: const {},
        zonesById: {1: zone},
      ),
      hasLength(1),
    );
  });

  test(
    'selected-zone isolation respects current zoom without extra buffer',
    () {
      final zoom = parkingIsolationZoom(
        const Point(latitude: 0, longitude: 0),
        const [Point(latitude: 1, longitude: 1)],
        currentZoom: 17.25,
      );

      expect(zoom, 17.25);
    },
  );

  test('uses the documented clustering constants and zoom caps', () {
    expect(parkingClusterMergePx, 22);
    expect(parkingClusterZoomStep, 0.5);
    expect(parkingZoneBadgeMinZoom, 14);
    expect(parkingClusterFreeCap(6.5), 1400);
    expect(parkingClusterFreeCap(9.5), 350);
    expect(parkingClusterFreeCap(12.5), 150);
    expect(parkingClusterFreeCap(13), double.infinity);
  });
}
