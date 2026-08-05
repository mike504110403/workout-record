// M3(major)的真實回歸測試:切走再切回首頁分頁時,首頁真的重新查詢並反映
// 新資料。
//
// 刻意 pump 完整的 `WorkItOutApp`(真的 go_router
// `StatefulShellRoute.indexedStack` + 5-tab bottom nav),透過真實的
// `NavigationDestination` 點擊切分頁——不是像 dashboard_page_test.dart 其他
// 測試那樣繞過 router、直接 pump `DashboardPage` 單一 widget。
//
// 這是複審 r2 打回原本 M3 widget 測試後採用的版本:原本那條測試直接呼叫
// `container.invalidate(dashboardControllerProvider)`,測的是 Riverpod 自身
// 的 invalidate 行為,不是 `router.dart` 的
// `_AppShell.onDestinationSelected` 有沒有真的接上這個呼叫——複審把
// router.dart 裡呼叫 invalidate 的那三行刪掉,舊測試照樣全綠,是假防護。
// 這裡改成真的走 shell + bottom nav 這條接縫,少了那三行就會紅。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';

import '../../data/test_helpers.dart';

void main() {
  testWidgets('切走再切回首頁分頁時,首頁重新查詢並反映新資料', (tester) async {
    // 登入 + 完成 Onboarding + 已同意隱私條款,三段守衛都放行,才能直接停在
    // /dashboard(見 router.dart resolveAuthRedirect 與 app.dart 的隱私同意
    // 浮層邏輯),不然畫面會卡在 /login 或 /onboarding 或隱私同意頁。
    SharedPreferences.setMockInitialValues({
      kAppleUserIdKey: testUserId,
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
    await seedTestUser(db);

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

    expect(find.byKey(const Key('noWorkoutTodayCard')), findsOneWidget);

    // 切去「訓練」分頁——StatefulShellRoute.indexedStack 讓首頁分頁不
    // dispose,DashboardPage 還活著、只是不在畫面上。
    await tester.tap(find.widgetWithText(NavigationDestination, '訓練'));
    await tester.pumpAndSettle();

    // 在使用者切走的期間,資料庫多了一筆今日訓練(模擬波 3「記完訓練切回
    // 首頁」或「跨午夜後今日概覽該換一批資料」的場景)。
    final now = DateTime.now();
    await WorkoutRepository(db, ExerciseRepository(db)).create(
      Workout(
        id: 'landed-while-away',
        userId: testUserId,
        startedAt: now,
        // 已完成訓練(endedAt 非 null)——波 3 起 fetchByDateRange 排除草稿
        // (endedAt IS NULL),這裡驗證的是「切回首頁後看到新增的已完成訓練」,
        // 不是草稿情境。
        endedAt: now.add(const Duration(minutes: 42)),
        duration: 42,
        totalVolume: 500,
        totalSets: 8,
        totalExercises: 2,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 切回首頁分頁——router.dart 的 _AppShell.onDestinationSelected 應該在
    // 這裡呼叫 ref.invalidate(dashboardControllerProvider),讓 DashboardPage
    // (雖然沒有被重建)背後的 provider 重新查詢。
    await tester.tap(find.widgetWithText(NavigationDestination, '首頁'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('todayWorkoutCard')), findsOneWidget);
    expect(find.byKey(const Key('noWorkoutTodayCard')), findsNothing);
  });
}
