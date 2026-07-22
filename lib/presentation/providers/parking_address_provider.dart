import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/parking_address.dart';

typedef ParkingCoordinate = ({double latitude, double longitude});

final parkingAddressProvider =
    FutureProvider.family<String?, ParkingCoordinate>((_, coordinate) async {
      try {
        return await reverseGeocodeParkingAddress(
          latitude: coordinate.latitude,
          longitude: coordinate.longitude,
        );
      } catch (_) {
        return null;
      }
    });
