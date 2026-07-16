import 'dart:convert';
import 'dart:js_interop';

import 'place_search_models.dart';

@JS('parkTrackYandexMaps.suggest')
external JSPromise<JSString> _suggestPlaces(
  JSString text,
  JSNumber south,
  JSNumber west,
  JSNumber north,
  JSNumber east,
);

@JS('parkTrackYandexMaps.geocode')
external JSPromise<JSString> _geocodePlace(
  JSString text,
  JSNumber south,
  JSNumber west,
  JSNumber north,
  JSNumber east,
);

class PlaceSearchService {
  Future<List<PlaceSuggestion>> suggestions(
    String text,
    PlaceSearchBounds bounds,
  ) async {
    final response = await _suggestPlaces(
      text.toJS,
      bounds.south.toJS,
      bounds.west.toJS,
      bounds.north.toJS,
      bounds.east.toJS,
    ).toDart;
    final items = jsonDecode(response.toDart) as List<dynamic>;
    return items
        .map((value) {
          final item = value as Map<String, dynamic>;
          return PlaceSuggestion(
            title: item['title'] as String,
            subtitle: item['subtitle'] as String?,
            searchText: item['searchText'] as String,
            latitude: (item['latitude'] as num?)?.toDouble(),
            longitude: (item['longitude'] as num?)?.toDouble(),
          );
        })
        .toList(growable: false);
  }

  Future<PlaceSearchPoint?> pointByText(
    String text,
    PlaceSearchBounds bounds,
  ) async {
    final response = await _geocodePlace(
      text.toJS,
      bounds.south.toJS,
      bounds.west.toJS,
      bounds.north.toJS,
      bounds.east.toJS,
    ).toDart;
    final value = jsonDecode(response.toDart);
    if (value == null) return null;
    final point = value as Map<String, dynamic>;
    return PlaceSearchPoint(
      latitude: (point['latitude'] as num).toDouble(),
      longitude: (point['longitude'] as num).toDouble(),
    );
  }

  void dispose() {}
}
