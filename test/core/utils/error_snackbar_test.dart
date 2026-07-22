import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/error_snackbar.dart';

void main() {
  test('suppresses only repeated messages inside the interval', () {
    final deduplicator = ErrorMessageDeduplicator(
      interval: const Duration(seconds: 5),
    );
    final now = DateTime(2026);

    expect(deduplicator.shouldShow('offline', now), isTrue);
    expect(
      deduplicator.shouldShow('offline', now.add(const Duration(seconds: 2))),
      isFalse,
    );
    expect(
      deduplicator.shouldShow('timeout', now.add(const Duration(seconds: 2))),
      isTrue,
    );
    expect(
      deduplicator.shouldShow('offline', now.add(const Duration(seconds: 6))),
      isTrue,
    );
  });
}
