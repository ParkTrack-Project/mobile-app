import 'package:yandex_mapkit/yandex_mapkit.dart';

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
        item?.toponymMetadata?.address.formattedAddress ??
        item?.businessMetadata?.address.formattedAddress;
    final normalized = address?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  } finally {
    await request.session.close();
  }
}
