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
      expect(coordinator.safeLocation(Uri.parse('/parking/nope')), '/map');
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
    });

    test('rejects unknown and external redirect locations', () {
      expect(coordinator.safeLocation(Uri.parse('/unknown')), '/map');
      expect(
        coordinator.safeLocation(Uri.parse('https://example.com/map')),
        '/map',
      );
    });

    test('restores a remembered destination once after authentication', () {
      coordinator.remember(Uri.parse('/parking/42'));

      expect(coordinator.takePendingOr('/map'), '/parking/42');
      expect(coordinator.takePendingOr('/search?q=park'), '/search?q=park');
    });
  });
}
