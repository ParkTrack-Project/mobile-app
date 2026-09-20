enum DeepLinkAuthStatus { loading, authenticated, unauthenticated }

class DeepLinkCoordinator {
  static const mobileHost = 'm.parktrack.live';

  static const _authPaths = {'/login', '/register', '/password-reset'};

  String? redirectLocation({
    required Uri uri,
    required DeepLinkAuthStatus authStatus,
  }) {
    if (uri.hasScheme || uri.hasAuthority) return safeLocation(uri);

    final path = uri.path;
    final isSplash = path == '/';
    final isAuthRoute = _authPaths.contains(path);

    if (authStatus == DeepLinkAuthStatus.loading) {
      if (isSplash || isAuthRoute) return null;
      return _locationWithFrom('/', safeLocation(uri));
    }

    if (authStatus == DeepLinkAuthStatus.unauthenticated) {
      if (isAuthRoute) return null;
      final from = isSplash ? _safeFrom(uri) : safeLocation(uri);
      return from == null ? '/login' : _locationWithFrom('/login', from);
    }

    if (isSplash || path == '/login' || path == '/register') {
      return _safeFrom(uri) ?? '/map';
    }

    return null;
  }

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
    if (segments.length == 2 && segments.first == 'route') {
      final routeId = int.tryParse(segments[1]);
      return routeId != null && routeId > 0 ? '/route/$routeId' : '/map';
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

  String? _safeFrom(Uri uri) {
    final from = uri.queryParameters['from'];
    if (from == null || from.isEmpty) return null;
    return safeLocation(Uri.tryParse(from));
  }

  String _locationWithFrom(String path, String from) =>
      Uri(path: path, queryParameters: {'from': from}).toString();

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
