import 'package:yandex_mapkit/yandex_mapkit.dart';

import 'place_search_models.dart';

class PlaceSearchService {
  SuggestSession? _suggestSession;
  SearchSession? _searchSession;

  Future<List<PlaceSuggestion>> suggestions(
    String text,
    PlaceSearchBounds bounds,
  ) async {
    final resultWithSession = YandexSuggest.getSuggestions(
      text: text,
      boundingBox: _boundingBox(bounds),
      suggestOptions: const SuggestOptions(
        suggestType: SuggestType.unspecified,
      ),
    );
    _suggestSession?.close();
    _suggestSession = resultWithSession.session;
    final result = await resultWithSession.result.timeout(
      const Duration(seconds: 5),
    );
    return (result.items ?? const <SuggestItem>[])
        .map(
          (item) => PlaceSuggestion(
            title: item.title,
            subtitle: item.subtitle,
            searchText: item.searchText,
            latitude: item.center?.latitude,
            longitude: item.center?.longitude,
          ),
        )
        .toList(growable: false);
  }

  Future<PlaceSearchPoint?> pointByText(
    String text,
    PlaceSearchBounds bounds,
  ) async {
    final resultWithSession = YandexSearch.searchByText(
      searchText: text,
      geometry: Geometry.fromBoundingBox(_boundingBox(bounds)),
      searchOptions: const SearchOptions(searchType: SearchType.geo),
    );
    _searchSession?.close();
    _searchSession = resultWithSession.session;
    final result = await resultWithSession.result.timeout(
      const Duration(seconds: 5),
    );
    final point = result.items?.firstOrNull?.geometry.firstOrNull?.point;
    return point == null
        ? null
        : PlaceSearchPoint(
            latitude: point.latitude,
            longitude: point.longitude,
          );
  }

  BoundingBox _boundingBox(PlaceSearchBounds bounds) => BoundingBox(
    southWest: Point(latitude: bounds.south, longitude: bounds.west),
    northEast: Point(latitude: bounds.north, longitude: bounds.east),
  );

  void dispose() {
    _suggestSession?.close();
    _suggestSession = null;
    _searchSession?.close();
    _searchSession = null;
  }
}
