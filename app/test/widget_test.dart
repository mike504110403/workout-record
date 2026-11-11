// Smoke test for the 4-tab navigation shell(ui-polish 2026-11-11 拿掉「訓練」
// 分頁,訓練改成從首頁進入的全螢幕路由): verifies the four tabs are present in
// the bottom NavigationBar and that switching tabs shows the corresponding page.
// 切分頁只驗頁面型別;起始首頁另驗無頁名標題與主 CTA(首頁版面斷言)。
//
// Since wave 1 (login/onboarding/privacy gate) landed, reaching the tab
// shell requires a logged-in + onboarded + privacy-agreed SharedPreferences
// state — see app/lib/router.dart's `resolveAuthRedirect` and
// app/lib/app.dart's privacy-consent builder gate.
//
// 波 2(Dashboard 實作)起,首頁分頁不再是靜態 placeholder,會真的透過
// repositories 查 Drift DB——沒有 override `appDatabaseProvider` 的話會
// 卡在開啟真實平台資料庫(需要 platform channel,單元測試環境沒有),造成
// pumpAndSettle 逾時。比照 app_flow_test.dart 的作法補上 in-memory 測試庫。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/dashboard/dashboard_page.dart';
import 'package:workout_record/features/history/history_page.dart';
import 'package:workout_record/features/settings/settings_page.dart';
import 'package:workout_record/features/stats/stats_page.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';

import 'data/test_helpers.dart';

void main() {
  testWidgets('4-tab shell shows all tabs and switches pages', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kAppleUserIdKey: 'test-user',
      kAppleUserNameKey: 'Test User',
      kAppleUserEmailKey: 'test@example.com',
      kHasCompletedOnboardingKey: true,
      kHasAgreedToAnalyticsKey: true,
      kHasAgreedToPrivacyKey: true,
      kPrivacyConsentDateKey: DateTime.now().millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    final db = openTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const WorkItOutApp(),
      ),
    );
    await tester.pumpAndSettle();

    final navBar = find.byType(NavigationBar);
    expect(find.descendant(of: navBar, matching: find.byType(NavigationDestination)), findsNWidgets(4));
    // 「訓練」不再是分頁。
    expect(find.widgetWithText(NavigationDestination, '訓練'), findsNothing);

    // Starts on the dashboard tab. 首頁不放頁名標題(底部導覽已標示所在分頁),
    // 以主 CTA 確認停在首頁。
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.widgetWithText(AppBar, '首頁'), findsNothing);
    expect(find.byKey(const Key('quickActionStartWorkout')), findsOneWidget);

    const tabs = <String, Type>{
      '數據': StatsPage,
      '歷史': HistoryPage,
      '設定': SettingsPage,
      '首頁': DashboardPage,
    };
    for (final entry in tabs.entries) {
      await tester.tap(find.widgetWithText(NavigationDestination, entry.key));
      await tester.pumpAndSettle();
      // IndexedStack 讓其他分頁保持掛載,用 hitTestable 只認畫面上可見那一頁。
      expect(find.byType(entry.value).hitTestable(), findsOneWidget, reason: '切到「${entry.key}」');
    }
  });
}
