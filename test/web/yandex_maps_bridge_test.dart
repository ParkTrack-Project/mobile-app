import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String bridge;

  setUpAll(() {
    bridge = File('web/yandex_maps.js').readAsStringSync();
  });

  test('keeps rendering and service contracts implemented', () {
    expect(bridge, contains('window.ymaps.route'));
    expect(bridge, contains('const responses = await api.route({'));
    expect(
      bridge,
      contains('api.getDefaultConfig().setApikeys({ router: routerApiKey })'),
    );
    expect(bridge, contains('points: [[fLon, fLat], [tLon, tLat]]'));
    expect(
      bridge,
      contains(
        '.map(coordinate => [Number(coordinate[1]), Number(coordinate[0])])',
      ),
    );
    expect(bridge, contains('duration: Number(properties.duration) || 0'));
    expect(bridge, contains('distance: Number(properties.length) || 0'));
    expect(bridge, contains('window.ymaps.geocode'));
    expect(bridge, contains('searchViaServices'));
    expect(bridge, contains('api-maps.yandex.ru/services/search/'));
    expect(bridge, isNot(contains("return JSON.stringify({ points: []")));
    expect(bridge, isNot(contains('return JSON.stringify([])')));
  });

  test('uses supported v3 interactions and real themes', () {
    expect(bridge, contains("'pinchRotate'"));
    expect(bridge, contains("'pinchZoom'"));
    expect(bridge, contains("'drag'"));
    expect(bridge, contains("state.theme === 'dark' ? 'dark' : 'light'"));
    expect(bridge, isNot(contains('filter: invert')));
    expect(bridge, isNot(contains('grayscale(')));
    expect(bridge, isNot(contains('YMapOpenMapsButton')));
    expect(bridge, contains('zone.fill'));
    expect(bridge, contains('zone.stroke'));
    expect(bridge, contains(r'opacity:${zone.markerOpacity ?? 1}'));
    expect(bridge, contains('clusterExpansionZoom'));
    expect(bridge, contains('function connectedParkingGroups(points)'));
    expect(bridge, contains('function splitParkingGroupByCap(points, cap)'));
    expect(bridge, contains('function mergeOverlappingParkingGroups('));
    expect(bridge, contains('clusterParkingZones(zones, zoomBucket)'));
    expect(bridge, contains('deltaX * deltaX + deltaY * deltaY <= 22 * 22'));
    expect(bridge, contains('zonesInsideBounds(state.zones || []'));
    expect(bridge, contains('clustering.singletonIds.has(zone.id)'));
    expect(bridge, contains('if (zoomBucket >= 14)'));
    expect(bridge, isNot(contains('clusterByGrid')));
    expect(bridge, contains('parktrack-user-location__direction'));
    expect(bridge, contains('parktrack-user-location__point'));
    expect(bridge, contains('requestHeading(id)'));
    expect(bridge, contains("'deviceorientationabsolute'"));
    expect(bridge, contains('azimuth: 0, tilt: 0'));
    expect(bridge, contains('const azimuth = Number(entry.map.azimuth || 0)'));
    expect(bridge, contains("left:-16px;top:-40px"));
    expect(bridge, contains('M16 39C13 32'));
    expect(bridge, contains('width: 64px'));
    expect(bridge, contains('width: 30px'));
    expect(bridge, contains('height: 55px'));
    expect(bridge, contains('width: 36px'));
    expect(bridge, contains('border: 3px solid'));
  });

  test('updates moving markers without rebuilding parking zones', () {
    expect(bridge, contains('function renderPositions(entry, state)'));
    expect(bridge, contains('updatePosition(id, state)'));
    expect(bridge, contains('renderPositions(entry, entry.latestState)'));
  });
}
