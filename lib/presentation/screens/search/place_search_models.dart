class PlaceSearchBounds {
  const PlaceSearchBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;
}

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.title,
    required this.searchText,
    this.subtitle,
    this.latitude,
    this.longitude,
  });

  final String title;
  final String searchText;
  final String? subtitle;
  final double? latitude;
  final double? longitude;
}

class PlaceSearchPoint {
  const PlaceSearchPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}
