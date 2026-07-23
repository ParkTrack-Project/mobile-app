class DeepLinkCoordinator {
  Uri? _pendingDestination;

  void remember(Uri destination) {
    _pendingDestination = Uri.parse(safeLocation(destination));
  }

  String takePendingOr(String? fallback) {
    final pending = _pendingDestination;
    _pendingDestination = null;
    if (pending != null) return safeLocation(pending);
    return safeLocation(Uri.tryParse(fallback ?? ''));
  }

  String safeLocation(Uri? uri) {
    if (uri == null || uri.hasScheme || uri.hasAuthority) return '/map';
    final segments = uri.pathSegments;

    if (uri.path == '/map') {
      return Uri(path: '/map', queryParameters: _mapParameters(uri)).toString();
    }
    if (segments.length == 2 && segments.first == 'parking') {
      final zoneId = int.tryParse(segments[1]);
      return zoneId != null && zoneId > 0 ? '/parking/$zoneId' : '/map';
    }
    if (uri.path == '/destination') {
      final latitude = double.tryParse(uri.queryParameters['lat'] ?? '');
      final longitude = double.tryParse(uri.queryParameters['lon'] ?? '');
      if (!_validCoordinates(latitude, longitude)) return '/map';
      final queryParameters = <String, String>{
        'lat': latitude.toString(),
        'lon': longitude.toString(),
      };
      final name = uri.queryParameters['name'];
      if (name != null && name.isNotEmpty) queryParameters['name'] = name;
      return Uri(
        path: '/destination',
        queryParameters: queryParameters,
      ).toString();
    }
    if (uri.path == '/search') {
      final query = uri.queryParameters['q'];
      return Uri(
        path: '/search',
        queryParameters: query == null || query.isEmpty ? null : {'q': query},
      ).toString();
    }
    if (uri.path == '/profile' || uri.path == '/profile/edit') {
      return uri.path;
    }
    return '/map';
  }

  Map<String, String>? _mapParameters(Uri uri) {
    final result = <String, String>{};
    final zoneId = int.tryParse(uri.queryParameters['zoneId'] ?? '');
    if (zoneId != null && zoneId > 0) result['zoneId'] = zoneId.toString();
    final latitude = double.tryParse(uri.queryParameters['lat'] ?? '');
    final longitude = double.tryParse(uri.queryParameters['lon'] ?? '');
    if (_validCoordinates(latitude, longitude)) {
      result['lat'] = latitude.toString();
      result['lon'] = longitude.toString();
      final name = uri.queryParameters['name'];
      if (name != null && name.isNotEmpty) result['name'] = name;
    }
    return result.isEmpty ? null : result;
  }

  bool _validCoordinates(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}
