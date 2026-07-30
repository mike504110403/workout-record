// WorkItOutApp 根 widget 的端到端流程測試,走真實接線(router + app.dart
// 的隱私同意 gate + Onboarding + 5-tab 殼),不是個別 controller 的隔離
// 測試。涵蓋三條路徑:
// a. 冷啟 → 登入 → 隱私同意 → 完成 Onboarding → 進入 5-tab 殼。
// b. 隱私同意 gate:勾滿兩框不按按鈕不放行、按下才放行且落地、同一份
//    prefs 重新啟動不再重問。
// c. 設定頁登出 → 回 /login,且 user_* 個資 prefs 與 Onboarding 完成旗標
//    已被清掉。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_controller.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';

import 'data/test_helpers.dart';

void main() {
  testWidgets(
    '冷啟整個流程:登入 → 隱私同意 → 完成 Onboarding → 進入 5-tab 殼',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = openTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const WorkItOutApp()),
      );
      await tester.pumpAndSettle();

      // 冷啟:未登入,停在 /login。
      expect(find.byKey(const Key('testLoginButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('testLoginButton')));
      await tester.pumpAndSettle();

      // 登入後、Onboarding 前,先擋在隱私同意頁。
      expect(find.text('隱私權同意'), findsOneWidget);

      await tester.tap(find.byKey(const Key('analyticsConsentCheckbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacyConsentCheckbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agreeAndContinueButton')));
      await tester.pumpAndSettle();

      // 同意之後進 Onboarding。
      expect(find.text('歡迎使用健身記錄'), findsOneWidget);

      await tester.tap(find.byKey(const Key('skipOnboardingButton')));
      await tester.pumpAndSettle();

      // 最終進到 5-tab 殼。
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.widgetWithText(AppBar, '首頁'), findsOneWidget);
    },
  );

  testWidgets(
    '隱私同意 gate:勾滿不按不放行,按下才放行且落地,同一份 prefs 重新啟動不再重問',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kAppleUserIdKey: 'gate-test-user',
        kAppleUserNameKey: 'Gate Tester',
        kAppleUserEmailKey: 'gate-tester@example.com',
      });
      final prefs = await SharedPreferences.getInstance();
      final db = openTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const WorkItOutApp()),
      );
      await tester.pumpAndSettle();

      expect(find.text('隱私權同意'), findsOneWidget);

      await tester.tap(find.byKey(const Key('analyticsConsentCheckbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacyConsentCheckbox')));
      await tester.pumpAndSettle();

      // 勾滿兩框但還沒按「同意並繼續」→ 仍停在同意頁,prefs 沒有任何同意 key。
      expect(find.text('隱私權同意'), findsOneWidget);
      expect(prefs.containsKey(kPrivacyConsentDateKey), isFalse);
      expect(prefs.containsKey(kHasAgreedToAnalyticsKey), isFalse);
      expect(prefs.containsKey(kHasAgreedToPrivacyKey), isFalse);

      await tester.tap(find.byKey(const Key('agreeAndContinueButton')));
      await tester.pumpAndSettle();

      // 按下之後放行,三個 key 都已落地。
      expect(find.text('隱私權同意'), findsNothing);
      expect(prefs.getBool(kHasAgreedToAnalyticsKey), isTrue);
      expect(prefs.getBool(kHasAgreedToPrivacyKey), isTrue);
      expect(prefs.containsKey(kPrivacyConsentDateKey), isTrue);

      // 同一份 prefs 重新啟動(新 container 模擬冷啟),不再重問。
      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container2.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container2, child: const WorkItOutApp()),
      );
      await tester.pumpAndSettle();

      expect(find.text('隱私權同意'), findsNothing);
    },
  );

  testWidgets(
    '設定頁登出 → 回 /login,user_* 個資 prefs 與 Onboarding 完成旗標已清',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        kAppleUserIdKey: 'signout-test-user',
        kAppleUserNameKey: 'Sign Out Tester',
        kAppleUserEmailKey: 'signout-tester@example.com',
        kHasCompletedOnboardingKey: true,
        kHasAgreedToAnalyticsKey: true,
        kHasAgreedToPrivacyKey: true,
        kPrivacyConsentDateKey: DateTime.now().millisecondsSinceEpoch,
        kUserGenderKey: '男性',
        kUserCurrentWeightKey: 70.0,
      });
      final prefs = await SharedPreferences.getInstance();
      final db = openTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const WorkItOutApp()),
      );
      await tester.pumpAndSettle();

      // 三個 gate 都已滿足,直接落在 5-tab 殼。
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.tap(find.widgetWithText(NavigationDestination, '設定'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('signOutButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登出').last);
      await tester.pumpAndSettle();

      // 登出後被導回 /login。
      expect(find.byKey(const Key('testLoginButton')), findsOneWidget);

      expect(prefs.containsKey(kAppleUserIdKey), isFalse);
      expect(prefs.containsKey(kUserGenderKey), isFalse);
      expect(prefs.containsKey(kUserCurrentWeightKey), isFalse);
      expect(prefs.containsKey(kHasCompletedOnboardingKey), isFalse);

      // 隱私同意三個 key 是裝置層級,登出不清。
      expect(prefs.getBool(kHasAgreedToAnalyticsKey), isTrue);
      expect(prefs.getBool(kHasAgreedToPrivacyKey), isTrue);
      expect(prefs.containsKey(kPrivacyConsentDateKey), isTrue);
    },
  );
}
