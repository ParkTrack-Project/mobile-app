import 'package:url_launcher/url_launcher.dart';

Future<void> openYandexNavigator(double lat, double lon) async {
  final yandexUri = Uri.parse(
    'yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lon&appmetrica_tracking_id=1178268795219767552',
  );
  final mapsUri = Uri.parse('https://maps.yandex.ru/?rtext=~$lat,$lon&rtt=auto');

  if (await canLaunchUrl(yandexUri)) {
    await launchUrl(yandexUri);
    return;
  }
  await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
}

Future<void> openYandexNavigatorUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
    return;
  }
  await launchUrl(
    Uri.parse('https://maps.yandex.ru/'),
    mode: LaunchMode.externalApplication,
  );
}
