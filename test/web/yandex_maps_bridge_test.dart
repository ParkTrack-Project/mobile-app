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
    expect(bridge, contains(r'opacity:${zone.opacity ?? 1}'));
    expect(bridge, contains('opacity: zone.opacity ?? 1'));
  });
}
