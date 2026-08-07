import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/router/deep_link_coordinator.dart';

void main() {
  group('DeepLinkCoordinator', () {
    late DeepLinkCoordinator coordinator;

    setUp(() => coordinator = DeepLinkCoordinator());

    test('accepts the supported map URL', () {
      expect(coordinator.safeLocation(Uri.parse('/map')), '/map');
    });

    test('accepts a parking URL with a positive zone id', () {
      expect(coordinator.safeLocation(Uri.parse('/parking/42')), '/parking/42');
      expect(
        coordinator.safeLocation(
          Uri.parse('https://m.parktrack.live/parking/42'),
        ),
        '/parking/42',
      );
      expect(
        coordinator.safeLocation(Uri.parse('parktrack://parking/42')),
        '/parking/42',
      );
      expect(
        coordinator.safeLocation(Uri.parse('parktrack:/parking/42')),
        '/parking/42',
      );
      expect(coordinator.safeLocation(Uri.parse('/parking/nope')), '/map');
    });

    test('accepts route URLs with a positive route id', () {
      expect(coordinator.safeLocation(Uri.parse('/route/7')), '/route/7');
      expect(
        coordinator.safeLocation(Uri.parse('https://m.parktrack.live/route/7')),
        '/route/7',
      );
      expect(
        coordinator.safeLocation(Uri.parse('parktrack://route/7')),
        '/route/7',
      );
      expect(coordinator.safeLocation(Uri.parse('/route/nope')), '/map');
      expect(coordinator.safeLocation(Uri.parse('/route/0')), '/map');
    });

    test('preserves a search query', () {
      expect(
        coordinator.safeLocation(
          Uri.parse('/search?q=Lenina%20Street&ignored=value'),
        ),
        '/search?q=Lenina+Street',
      );
    });

    test('validates destination coordinates and query parameters', () {
      expect(
        coordinator.safeLocation(
          Uri.parse('/destination?lat=61.789114&lon=34.359757&name=Station'),
        ),
        '/destination?lat=61.789114&lon=34.359757&name=Station',
      );
      expect(
        coordinator.safeLocation(Uri.parse('/destination?lat=100&lon=0')),
        '/map',
      );
    });

    test('keeps supported map query parameters only', () {
      expect(
        coordinator.safeLocation(
          Uri.parse('/map?zoneId=7&lat=10&lon=20&name=Office&token=secret'),
        ),
        '/map?zoneId=7&lat=10.0&lon=20.0&name=Office',
      );
      expect(
        coordinator.safeLocation(Uri.parse('parktrack://map?id=8&q=station')),
        '/map?zoneId=8&q=station',
      );
    });

    test('supports every public app section for both link schemes', () {
      const paths = [
        '/map',
        '/search?q=park',
        '/route/7',
        '/profile',
        '/profile/edit',
        '/login',
        '/register',
        '/password-reset',
      ];

      for (final path in paths) {
        expect(
          coordinator.safeLocation(Uri.parse('https://m.parktrack.live$path')),
          coordinator.safeLocation(Uri.parse(path)),
        );
        final uri = Uri.parse(path);
        final custom = Uri(
          scheme: 'parktrack',
          host: uri.pathSegments.first,
          pathSegments: uri.pathSegments.skip(1),
          queryParameters: uri.queryParameters.isEmpty
              ? null
              : uri.queryParameters,
        );
        expect(coordinator.safeLocation(custom), coordinator.safeLocation(uri));
      }
    });

    test('normalizes destination links and validates coordinates', () {
      expect(
        coordinator.safeLocation(
          Uri.parse(
            'parktrack://destination?lat=61.789114&lon=34.359757&name=Station',
          ),
        ),
        '/destination?lat=61.789114&lon=34.359757&name=Station',
      );
    });

    test('rejects unknown and external redirect locations', () {
      expect(coordinator.safeLocation(Uri.parse('/unknown')), '/map');
      expect(
        coordinator.safeLocation(Uri.parse('https://example.com/map')),
        '/map',
      );
      expect(
        coordinator.safeLocation(Uri.parse('parktrack-other://map')),
        '/map',
      );
    });

    group('authentication redirects', () {
      test('preserves an incoming link while the session is loading', () {
        expect(
          coordinator.redirectLocation(
            uri: Uri.parse('/parking/42'),
            authStatus: DeepLinkAuthStatus.loading,
          ),
          '/?from=%2Fparking%2F42',
        );
        expect(
          coordinator.redirectLocation(
            uri: Uri.parse('/?from=%2Fparking%2F42'),
            authStatus: DeepLinkAuthStatus.loading,
          ),
          isNull,
        );
      });

      test('restores a preserved link for an authenticated user', () {
        expect(
          coordinator.redirectLocation(
            uri: Uri.parse('/?from=%2Froute%2F7'),
            authStatus: DeepLinkAuthStatus.authenticated,
          ),
          '/route/7',
        );
        expect(
          coordinator.redirectLocation(
            uri: Uri.parse('/login?from=%2Fprofile%2Fedit'),
            authStatus: DeepLinkAuthStatus.authenticated,
          ),
          '/profile/edit',
        );
      });

      test('carries a preserved link through sign in', () {
        expect(
          coordinator.redirectLocation(
            uri: Uri.parse('/?from=%2Fsearch%3Fq%3Dstation'),
            authStatus: DeepLinkAuthStatus.unauthenticated,
          ),
          '/login?from=%2Fsearch%3Fq%3Dstation',
        );
        expect(
          coordinator.redirectLocation(
            uri: Uri.parse('/login?from=%2Fsearch%3Fq%3Dstation'),
            authStatus: DeepLinkAuthStatus.unauthenticated,
          ),
          isNull,
        );
      });

      test('keeps public authentication links available while loading', () {
        for (final path in const ['/login', '/register', '/password-reset']) {
          expect(
            coordinator.redirectLocation(
              uri: Uri.parse(path),
              authStatus: DeepLinkAuthStatus.loading,
            ),
            isNull,
          );
        }
      });

      test('normalizes platform URLs before applying authentication', () {
        expect(
          coordinator.redirectLocation(
            uri: Uri.parse('parktrack://destination?lat=61&lon=34'),
            authStatus: DeepLinkAuthStatus.loading,
          ),
          '/destination?lat=61.0&lon=34.0',
        );
        expect(
          coordinator.redirectLocation(
            uri: Uri.parse('https://m.parktrack.live/parking/42'),
            authStatus: DeepLinkAuthStatus.unauthenticated,
          ),
          '/parking/42',
        );
      });

      test('sanitizes from parameters before restoring them', () {
        expect(
          coordinator.redirectLocation(
            uri: Uri.parse(
              '/login?from=${Uri.encodeComponent('https://example.com/profile')}',
            ),
            authStatus: DeepLinkAuthStatus.authenticated,
          ),
          '/map',
        );
      });
    });
  });
}
