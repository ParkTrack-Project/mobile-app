import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String bridge;

  setUpAll(() {
    bridge = File('web/yandex_maps.js').readAsStringSync();
  });

  test('keeps rendering and service contracts implemented', () {
    expect(bridge, contains('window.ymaps.route'));
    expect(bridge, contains('window.ymaps.geocode'));
    expect(bridge, contains('searchViaServices'));
    expect(bridge, contains('api-maps.yandex.ru/services/search/'));
    expect(bridge, isNot(contains("return JSON.stringify({ points: []")));
    expect(bridge, isNot(contains('return JSON.stringify([])')));
  });

  test('uses supported v3 interactions and real themes', () {
    expect(
      bridge,
      contains("behaviors: ['drag', 'scrollZoom', 'pinchZoom', 'dblClick']"),
    );
    expect(bridge, contains("state.theme === 'dark' ? 'dark' : 'light'"));
    expect(bridge, isNot(contains('filter: invert')));
    expect(bridge, isNot(contains('grayscale(')));
    expect(bridge, isNot(contains('YMapOpenMapsButton')));
    expect(bridge, contains('zone.fill'));
    expect(bridge, contains('zone.stroke'));
    expect(bridge, contains(r'opacity:${zone.markerOpacity ?? 1}'));
    expect(bridge, contains('clusterExpansionZoom'));
    expect(bridge, contains('gridSize: 22'));
    expect(bridge, contains('azimuth: 0, tilt: 0'));
    expect(bridge, contains('const azimuth = Number(entry.map.azimuth || 0)'));
    expect(bridge, contains("left:-16px;top:-40px"));
    expect(bridge, contains('M16 39C13 32'));
    expect(bridge, contains('viewBox="0 0 48 48" width="24" height="24"'));
  });
}
