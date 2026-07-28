class DeepLinkCoordinator {
  static const mobileHost = 'm.parktrack.live';

  String safeLocation(Uri? uri) {
    final internal = _toInternalUri(uri);
    if (internal == null) return '/map';
    final segments = internal.pathSegments;

    if (internal.path == '/map') {
      return Uri(
        path: '/map',
        queryParameters: _mapParameters(internal),
      ).toString();
    }
    if (segments.length == 2 && segments.first == 'parking') {
      final zoneId = int.tryParse(segments[1]);
      return zoneId != null && zoneId > 0 ? '/parking/$zoneId' : '/map';
    }
    if (segments.length == 3 &&
        segments.first == 'map' &&
        segments[1] == 'parking') {
      final zoneId = int.tryParse(segments[2]);
      return zoneId != null && zoneId > 0 ? '/parking/$zoneId' : '/map';
    }
    if (internal.path == '/destination') {
      final latitude = double.tryParse(internal.queryParameters['lat'] ?? '');
      final longitude = double.tryParse(internal.queryParameters['lon'] ?? '');
      if (!_validCoordinates(latitude, longitude)) return '/map';
      final queryParameters = <String, String>{
        'lat': latitude.toString(),
        'lon': longitude.toString(),
      };
      final name = internal.queryParameters['name'];
      if (name != null && name.isNotEmpty) queryParameters['name'] = name;
      return Uri(
        path: '/destination',
        queryParameters: queryParameters,
      ).toString();
    }
    if (internal.path == '/search') {
      final query = internal.queryParameters['q'];
      return Uri(
        path: '/search',
        queryParameters: query == null || query.isEmpty ? null : {'q': query},
      ).toString();
    }
    if (internal.path == '/profile' || internal.path == '/profile/edit') {
      return internal.path;
    }
    if (internal.path == '/login' ||
        internal.path == '/register' ||
        internal.path == '/password-reset') {
      return internal.path;
    }
    return '/map';
  }

  Uri? _toInternalUri(Uri? uri) {
    if (uri == null) return null;
    if (!uri.hasScheme && !uri.hasAuthority) return uri;

    if (uri.scheme == 'https' && uri.host == mobileHost) {
      return Uri(path: uri.path, query: uri.hasQuery ? uri.query : null);
    }
    if (uri.scheme != 'parktrack') return null;

    final path = uri.hasAuthority
        ? '/${[uri.host, ...uri.pathSegments].join('/')}'
        : uri.path;
    return Uri(path: path, query: uri.hasQuery ? uri.query : null);
  }

  Map<String, String>? _mapParameters(Uri uri) {
    final result = <String, String>{};
    final zoneId = int.tryParse(
      uri.queryParameters['id'] ?? uri.queryParameters['zoneId'] ?? '',
    );
    if (zoneId != null && zoneId > 0) result['zoneId'] = zoneId.toString();
    final query = uri.queryParameters['q'];
    if (query != null && query.isNotEmpty) result['q'] = query;
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
