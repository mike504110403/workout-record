// SettingsPage 登出按鈕 seam:按下後彈確認對話框,取消不登出、確定才登出
// (清 session 三個 key)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/settings_page.dart';

Future<ProviderContainer> _pumpSettingsPage(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    kAppleUserIdKey: 'test-user',
    kAppleUserNameKey: 'Test User',
    kAppleUserEmailKey: 'test@example.com',
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('顯示登出按鈕', (tester) async {
    await _pumpSettingsPage(tester);
    expect(find.byKey(const Key('signOutButton')), findsOneWidget);
  });

  testWidgets('按登出 → 彈確認對話框 → 按取消不登出', (tester) async {
    final container = await _pumpSettingsPage(tester);

    await tester.tap(find.byKey(const Key('signOutButton')));
    await tester.pumpAndSettle();
    expect(find.text('確定要登出嗎?'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(container.read(sessionControllerProvider).isLoggedIn, isTrue);
  });

  testWidgets('按登出 → 彈確認對話框 → 按登出才真的清 session', (tester) async {
    final container = await _pumpSettingsPage(tester);

    await tester.tap(find.byKey(const Key('signOutButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('登出').last);
    await tester.pumpAndSettle();

    expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
  });
}
