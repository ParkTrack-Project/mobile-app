import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:yandex_mapkit/yandex_mapkit.dart';

@visibleForTesting
String? formatAndroidParkingAddress({
  required Map<SearchComponentKind, String> components,
  required String formattedAddress,
}) {
  String? component(SearchComponentKind kind) {
    final value = components[kind]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  final street = component(SearchComponentKind.street);
  final house = component(SearchComponentKind.house);
  final locality = component(SearchComponentKind.locality);
  final parts = <String>[
    ?street,
    ?house,
    if (locality != null && locality != street && locality != house) locality,
  ];

  if (parts.isNotEmpty) return parts.join(', ');

  final normalizedFallback = formattedAddress.trim();
  return normalizedFallback.isEmpty ? null : normalizedFallback;
}

Future<String?> reverseGeocodeParkingAddress({
  required double latitude,
  required double longitude,
}) async {
  final request = YandexSearch.searchByPoint(
    point: Point(latitude: latitude, longitude: longitude),
    searchOptions: const SearchOptions(
      searchType: SearchType.geo,
      resultPageSize: 1,
    ),
  );
  try {
    final result = await request.result.timeout(const Duration(seconds: 5));
    final item = result.items?.firstOrNull;
    final address =
        item?.toponymMetadata?.address ?? item?.businessMetadata?.address;

    if (address == null) return null;

    if (defaultTargetPlatform == TargetPlatform.android) {
      return formatAndroidParkingAddress(
        components: address.addressComponents,
        formattedAddress: address.formattedAddress,
      );
    }

    final normalized = address.formattedAddress.trim();
    return normalized.isEmpty ? null : normalized;
  } finally {
    await request.session.close();
  }
}
