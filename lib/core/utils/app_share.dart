import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

const parkTrackMobileHost = 'm.parktrack.live';

Uri parkingShareUri(int zoneId) =>
    Uri.https(parkTrackMobileHost, '/parking/$zoneId');

Uri routeShareUri(int routeId) =>
    Uri.https(parkTrackMobileHost, '/route/$routeId');

Uri destinationShareUri({
  required double latitude,
  required double longitude,
  String? name,
}) => Uri.https(parkTrackMobileHost, '/destination', {
  'lat': latitude.toString(),
  'lon': longitude.toString(),
  if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
});

Future<void> shareParkTrackLink(
  BuildContext context, {
  required Uri uri,
  required String title,
}) async {
  final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
  final origin = overlay is RenderBox
      ? overlay.localToGlobal(Offset.zero) & overlay.size
      : null;
  await SharePlus.instance.share(
    ShareParams(
      title: title,
      subject: title,
      text: uri.toString(),
      sharePositionOrigin: origin,
    ),
  );
}
