// 首頁「記錄體重」bottom sheet 要用 root navigator 開(蓋住底部導覽列)。
// 作法同 test/features/workout/sheets_root_navigator_test.dart:把 DashboardPage
// 放進「巢狀 Navigator」(模擬 StatefulShellRoute 的分支 navigator),點記錄體重後
// 檢查 sheet route 推在 root navigator 而不是巢狀 navigator。變異:把
// dashboard_page.dart 的 `useRootNavigator: true` 拿掉,本測試必紅。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/dashboard/dashboard_page.dart';

import '../../data/test_helpers.dart';

void main() {
  testWidgets('記錄體重 sheet 推在 root navigator,不在巢狀 navigator', (tester) async {
    final rootKey = GlobalKey<NavigatorState>();
    final nestedKey = GlobalKey<NavigatorState>();
    SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
    final prefs = await SharedPreferences.getInstance();
    final db = openTestDatabase();
    await seedTestUser(db);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: rootKey,
          home: Scaffold(
            body: Navigator(
              key: nestedKey,
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => const DashboardPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quickActionRecordWeight')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bodyWeightInputField')), findsOneWidget);
    expect(nestedKey.currentState!.canPop(), isFalse, reason: 'sheet 不該推在巢狀 navigator');
    expect(rootKey.currentState!.canPop(), isTrue, reason: 'sheet 應推在 root navigator');
  });
}
