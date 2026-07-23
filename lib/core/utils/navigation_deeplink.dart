import 'package:url_launcher/url_launcher.dart';

typedef CanLaunchExternalUri = Future<bool> Function(Uri uri);
typedef LaunchExternalUri =
    Future<bool> Function(Uri uri, LaunchMode launchMode);

Uri buildYandexMapsRouteUri(double latitude, double longitude) {
  _validateCoordinates(latitude, longitude);
  return Uri(
    scheme: 'yandexmaps',
    host: 'maps.yandex.ru',
    path: '/',
    queryParameters: {'rtext': '~$latitude,$longitude', 'rtt': 'auto'},
  );
}

Uri buildYandexMapsWebRouteUri(double latitude, double longitude) {
  _validateCoordinates(latitude, longitude);
  return Uri.https('yandex.ru', '/maps/', {
    'rtext': '~$latitude,$longitude',
    'rtt': 'auto',
  });
}

Future<void> openYandexMapsRoute(
  double latitude,
  double longitude, {
  CanLaunchExternalUri canLaunch = canLaunchUrl,
  LaunchExternalUri launch = _launchUrl,
}) async {
  final appUri = buildYandexMapsRouteUri(latitude, longitude);
  if (await canLaunch(appUri) &&
      await launch(appUri, LaunchMode.externalApplication)) {
    return;
  }

  final webUri = buildYandexMapsWebRouteUri(latitude, longitude);
  if (await launch(webUri, LaunchMode.externalApplication)) return;
  throw StateError('Could not open Yandex Maps');
}

Future<void> openYandexMapsUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null &&
      await canLaunchUrl(uri) &&
      await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    return;
  }
  final fallback = Uri.https('yandex.ru', '/maps/');
  if (await launchUrl(fallback, mode: LaunchMode.externalApplication)) return;
  throw StateError('Could not open Yandex Maps');
}

Future<bool> _launchUrl(Uri uri, LaunchMode launchMode) =>
    launchUrl(uri, mode: launchMode);

void _validateCoordinates(double latitude, double longitude) {
  if (!latitude.isFinite ||
      !longitude.isFinite ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180) {
    throw ArgumentError('Invalid destination coordinates');
  }
}
