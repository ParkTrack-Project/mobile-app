import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'time selection invalidates the viewport cache before reloading zones',
    () {
      final source = File(
        'lib/presentation/screens/map/map_screen.dart',
      ).readAsStringSync();
      final listenerStart = source.indexOf('ref.listen(timeSelectorProvider');
      final listenerEnd = source.indexOf(
        'ref.listen(\n      filteredZonesProvider',
        listenerStart,
      );

      expect(listenerStart, greaterThanOrEqualTo(0));
      expect(listenerEnd, greaterThan(listenerStart));
      final listener = source.substring(listenerStart, listenerEnd);
      expect(listener, contains('_fetchZones(clearCache: true)'));

      final fetchStart = source.indexOf(
        'Future<void> _fetchZones({bool clearCache = false})',
      );
      final fetchEnd = source.indexOf(
        'Future<void> _fetchZonesForBbox',
        fetchStart,
      );
      expect(fetchStart, greaterThanOrEqualTo(0));
      expect(fetchEnd, greaterThan(fetchStart));
      final fetch = source.substring(fetchStart, fetchEnd);
      expect(fetch, contains('_lastZoneFetchBbox = null'));
      expect(fetch, contains('_zoneFetchInFlightBbox = null'));
    },
  );
}
