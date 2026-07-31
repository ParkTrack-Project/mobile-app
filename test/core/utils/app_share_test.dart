import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/app_share.dart';
import 'package:mobile/core/utils/app_share_platform_shared.dart';

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

  test('omits share title and subject on Web', () {
    final params = buildParkTrackShareParams(
      uri: routeShareUri(7),
      title: 'Route Ready',
      text: 'Route to parking #42',
      isWeb: true,
    );

    expect(params.title, isNull);
    expect(params.subject, isNull);
    expect(
      params.text,
      'Route to parking #42\nhttps://m.parktrack.live/route/7',
    );
  });

  test('keeps share title and subject outside Web', () {
    final params = buildParkTrackShareParams(
      uri: parkingShareUri(42),
      title: 'Parking #42',
      text: 'Parking #42\n42 Test Street',
      isWeb: false,
    );

    expect(params.title, 'Parking #42');
    expect(params.subject, 'Parking #42');
    expect(
      params.text,
      'Parking #42\n42 Test Street\nhttps://m.parktrack.live/parking/42',
    );
  });

  test('builds an email fallback from the Web share payload', () {
    final params = buildParkTrackShareParams(
      uri: routeShareUri(7),
      title: 'Route Ready',
      text: 'Route to parking #42',
      isWeb: true,
    );

    final fallback = buildShareMailtoUri(params);

    expect(fallback.scheme, 'mailto');
    expect(fallback.queryParameters['subject'], isNull);
    expect(
      fallback.queryParameters['body'],
      'Route to parking #42\nhttps://m.parktrack.live/route/7',
    );
  });
}
