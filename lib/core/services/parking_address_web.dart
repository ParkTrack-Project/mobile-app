import 'dart:convert';
import 'dart:js_interop';

@JS('parkTrackYandexMaps.reverseGeocode')
external JSPromise<JSString> _reverseGeocode(
  JSNumber latitude,
  JSNumber longitude,
);

Future<String?> reverseGeocodeParkingAddress({
  required double latitude,
  required double longitude,
}) async {
  final response = await _reverseGeocode(
    latitude.toJS,
    longitude.toJS,
  ).toDart.timeout(const Duration(seconds: 5));
  final address = jsonDecode(response.toDart) as String?;
  final normalized = address?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
