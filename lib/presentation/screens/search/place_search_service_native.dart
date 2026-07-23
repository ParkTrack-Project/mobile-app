import 'dart:async';

import 'package:yandex_mapkit/yandex_mapkit.dart';

import 'place_search_models.dart';

class PlaceSearchService {
  static const _suggestTimeout = Duration(seconds: 8);
  static const _searchTimeout = Duration(seconds: 8);
  static const _sessionCloseTimeout = Duration(seconds: 1);

  SuggestSession? _suggestSession;
  SearchSession? _searchSession;
  int _suggestGeneration = 0;

  Future<List<PlaceSuggestion>> suggestions(
    String text,
    PlaceSearchBounds bounds,
  ) async {
    final generation = ++_suggestGeneration;
    final previousSession = _suggestSession;
    final resultWithSession = YandexSuggest.getSuggestions(
      text: text,
      boundingBox: _boundingBox(bounds),
      suggestOptions: SuggestOptions(
        suggestType: SuggestType.unspecified,
        suggestWords: true,
        userPosition: _center(bounds),
      ),
    );
    _suggestSession = resultWithSession.session;
    if (previousSession != null && !previousSession.isClosed) {
      unawaited(_closeSuggestSession(previousSession));
    }

    try {
      final result = await resultWithSession.result.timeout(_suggestTimeout);
      if (generation != _suggestGeneration) return const [];
      if (result.error != null) {
        return _searchSuggestions(text, bounds);
      }
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
    } on TimeoutException {
      if (generation != _suggestGeneration) return const [];
      return _searchSuggestions(text, bounds);
    } finally {
      unawaited(_closeSuggestSession(resultWithSession.session));
      if (identical(_suggestSession, resultWithSession.session)) {
        _suggestSession = null;
      }
    }
  }

  Future<PlaceSearchPoint?> pointByText(
    String text,
    PlaceSearchBounds bounds,
  ) async {
    final previousSession = _searchSession;
    final resultWithSession = YandexSearch.searchByText(
      searchText: text,
      geometry: Geometry.fromBoundingBox(_boundingBox(bounds)),
      searchOptions: SearchOptions(
        searchType: SearchType.geo,
        geometry: true,
        resultPageSize: 1,
        userPosition: _center(bounds),
      ),
    );
    _searchSession = resultWithSession.session;
    if (previousSession != null && !previousSession.isClosed) {
      unawaited(_closeSearchSession(previousSession));
    }

    try {
      final result = await resultWithSession.result.timeout(_searchTimeout);
      if (result.error != null) throw StateError(result.error!);
      final point = _firstPoint(result.items?.firstOrNull);
      return point == null
          ? null
          : PlaceSearchPoint(
              latitude: point.latitude,
              longitude: point.longitude,
            );
    } finally {
      unawaited(_closeSearchSession(resultWithSession.session));
      if (identical(_searchSession, resultWithSession.session)) {
        _searchSession = null;
      }
    }
  }

  Future<List<PlaceSuggestion>> _searchSuggestions(
    String text,
    PlaceSearchBounds bounds,
  ) async {
    final previousSession = _searchSession;
    final resultWithSession = YandexSearch.searchByText(
      searchText: text,
      geometry: Geometry.fromBoundingBox(_boundingBox(bounds)),
      searchOptions: SearchOptions(
        geometry: true,
        resultPageSize: 10,
        userPosition: _center(bounds),
      ),
    );
    _searchSession = resultWithSession.session;
    if (previousSession != null && !previousSession.isClosed) {
      unawaited(_closeSearchSession(previousSession));
    }

    try {
      final result = await resultWithSession.result.timeout(_searchTimeout);
      if (result.error != null) throw StateError(result.error!);
      return (result.items ?? const <SearchItem>[])
          .map((item) {
            final point = _firstPoint(item);
            final subtitle =
                item.businessMetadata?.address.formattedAddress ??
                item.toponymMetadata?.address.formattedAddress;
            return PlaceSuggestion(
              title: item.name,
              subtitle: subtitle == item.name ? null : subtitle,
              searchText: [item.name, ?subtitle].join(', '),
              latitude: point?.latitude,
              longitude: point?.longitude,
            );
          })
          .toList(growable: false);
    } finally {
      unawaited(_closeSearchSession(resultWithSession.session));
      if (identical(_searchSession, resultWithSession.session)) {
        _searchSession = null;
      }
    }
  }

  Point? _firstPoint(SearchItem? item) =>
      item?.geometry.map((geometry) => geometry.point).nonNulls.firstOrNull;

  Point _center(PlaceSearchBounds bounds) => Point(
    latitude: (bounds.south + bounds.north) / 2,
    longitude: (bounds.west + bounds.east) / 2,
  );

  BoundingBox _boundingBox(PlaceSearchBounds bounds) => BoundingBox(
    southWest: Point(latitude: bounds.south, longitude: bounds.west),
    northEast: Point(latitude: bounds.north, longitude: bounds.east),
  );

  Future<void> _closeSuggestSession(SuggestSession session) async {
    if (session.isClosed) return;
    try {
      await session.close().timeout(_sessionCloseTimeout);
    } catch (_) {
      // The native session may already have been released after completion.
    }
  }

  Future<void> _closeSearchSession(SearchSession session) async {
    if (session.isClosed) return;
    try {
      await session.close().timeout(_sessionCloseTimeout);
    } catch (_) {
      // The native session may already have been released after completion.
    }
  }

  void dispose() {
    _suggestGeneration++;
    final suggestSession = _suggestSession;
    _suggestSession = null;
    if (suggestSession != null) {
      unawaited(_closeSuggestSession(suggestSession));
    }
    final searchSession = _searchSession;
    _searchSession = null;
    if (searchSession != null) {
      unawaited(_closeSearchSession(searchSession));
    }
  }
}
