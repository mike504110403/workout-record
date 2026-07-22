// Smoke test for the 5-tab navigation shell: verifies all five tabs are
// present in the bottom NavigationBar and that switching tabs shows the
// corresponding placeholder page.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/app.dart';

void main() {
  testWidgets('5-tab shell shows all tabs and switches pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: WorkItOutApp()));
    await tester.pumpAndSettle();

    const tabLabels = ['首頁', '訓練', '數據', '歷史', '設定'];
    for (final label in tabLabels) {
      expect(find.text(label), findsWidgets);
    }

    // Starts on the dashboard tab.
    expect(find.widgetWithText(AppBar, '首頁'), findsOneWidget);

    // Switch to each remaining tab and verify its page becomes visible.
    for (final label in tabLabels.skip(1)) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, label), findsOneWidget);
    }
  });
}
