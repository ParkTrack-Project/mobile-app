import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/app_share.dart';

void main() {
  test('builds canonical ParkTrack share links', () {
    expect(
      parkingShareUri(42).toString(),
      'https://m.parktrack.live/parking/42',
    );
    expect(routeShareUri(7).toString(), 'https://m.parktrack.live/route/7');
    expect(
      destinationShareUri(
        latitude: 61.789114,
        longitude: 34.359757,
        name: 'Railway station',
      ).toString(),
      'https://m.parktrack.live/destination'
      '?lat=61.789114&lon=34.359757&name=Railway+station',
    );
  });
}
