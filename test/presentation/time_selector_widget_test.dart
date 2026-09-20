import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/presentation/providers/time_selector_provider.dart';
import 'package:mobile/presentation/screens/map/widgets/time_selector_widget.dart';

void main() {
  testWidgets(
    'neutral time controls use a shadow and only selected time is outlined',
    (tester) async {
      final providerContainer = ProviderContainer(
        overrides: [l10nProvider.overrideWithValue(AppStrings.ru)],
      );
      addTearDown(providerContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: providerContainer,
          child: const MaterialApp(home: Scaffold(body: TimeSelectorWidget())),
        ),
      );

      final neutralTime = _chipDecoration(
        tester,
        const Key('time_selector_time_chip'),
      );
      expect(neutralTime.border, isNull);
      expect(neutralTime.boxShadow, isNotEmpty);

      providerContainer
          .read(timeSelectorProvider.notifier)
          .setFuture(DateTime(2026, 9, 21, 12));
      await tester.pump();

      final neutralNow = _chipDecoration(
        tester,
        const Key('time_selector_now_chip'),
      );
      final selectedTime = _chipDecoration(
        tester,
        const Key('time_selector_time_chip'),
      );
      expect(neutralNow.border, isNull);
      expect(neutralNow.boxShadow, neutralTime.boxShadow);
      expect(selectedTime.boxShadow, neutralTime.boxShadow);

      final selectedBorder = selectedTime.border! as Border;
      expect(selectedBorder.top.color, AppColors.primary);
      expect(selectedBorder.top.width, 1.5);
    },
  );

  testWidgets('time picker accepts mouse dragging', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [l10nProvider.overrideWithValue(AppStrings.ru)],
        child: const MaterialApp(home: Scaffold(body: TimeSelectorWidget())),
      ),
    );

    await tester.tap(find.text(AppStrings.ru.time));
    await tester.pumpAndSettle();

    final pickerContext = tester.element(find.byType(CupertinoDatePicker));
    expect(
      ScrollConfiguration.of(pickerContext).dragDevices,
      contains(PointerDeviceKind.mouse),
    );
  });
}

BoxDecoration _chipDecoration(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byKey(key), matching: find.byType(Container))
        .first,
  );
  return container.decoration! as BoxDecoration;
}
