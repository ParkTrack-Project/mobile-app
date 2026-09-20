import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

void main() {
  const mapId = MapObjectId('moving-marker');
  final icon = PlacemarkIcon.single(
    PlacemarkIconStyle(
      image: BitmapDescriptor.fromBytes(Uint8List.fromList(<int>[1, 2, 3])),
    ),
  );

  test('placemark movement sends only changed native properties', () {
    final previous = PlacemarkMapObject(
      mapId: mapId,
      point: const Point(latitude: 61, longitude: 34),
      direction: 10,
      icon: icon,
    );
    final current = previous.copyWith(
      point: const Point(latitude: 61.1, longitude: 34.1),
      direction: 20,
    );

    final update = MapObjectUpdates<PlacemarkMapObject>.from(
      <PlacemarkMapObject>{previous},
      <PlacemarkMapObject>{current},
    ).toJson();
    final changed =
        (update['toChange'] as List<Object?>).single as Map<String, dynamic>;

    expect(changed.keys, <String>{'id', 'type', 'point', 'direction'});
    expect(changed, isNot(contains('icon')));
  });

  test('placemark icon is sent when the icon actually changes', () {
    final previous = PlacemarkMapObject(
      mapId: mapId,
      point: const Point(latitude: 61, longitude: 34),
      icon: icon,
    );
    final current = previous.copyWith(
      icon: PlacemarkIcon.single(
        PlacemarkIconStyle(
          image: BitmapDescriptor.fromBytes(Uint8List.fromList(<int>[4, 5, 6])),
        ),
      ),
    );

    final update = MapObjectUpdates<PlacemarkMapObject>.from(
      <PlacemarkMapObject>{previous},
      <PlacemarkMapObject>{current},
    ).toJson();
    final changed =
        (update['toChange'] as List<Object?>).single as Map<String, dynamic>;

    expect(changed.keys, <String>{'id', 'type', 'icon'});
  });
}
