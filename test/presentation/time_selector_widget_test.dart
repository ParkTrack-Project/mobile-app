import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_localizations.dart';
import 'package:mobile/presentation/screens/map/widgets/time_selector_widget.dart';

void main() {
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
