// M3 風格的真實回歸測試(切走再切回「數據」分頁時,訓練統計子頁真的重新
// 查詢並反映新資料)。對照
// test/features/dashboard/dashboard_shell_revisit_test.dart 的手法:刻意
// pump 完整的 `WorkItOutApp`(真的 go_router `StatefulShellRoute.indexedStack`
// + 5-tab bottom nav),透過真實的 `NavigationDestination` 點擊切分頁——不是
// 繞過 router、直接 pump `StatsPage` 單一 widget。這條測試守住的是
// router.dart 裡 `shouldRefreshStatsOnBranchSwitch` 判斷之後,真的有呼叫
// `ref.invalidate(workoutStatsControllerProvider)` 這一行接線本身;純函式
// 那半(index 對應)留在 test/router/router_redirect_test.dart。
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
  testWidgets('切走再切回數據分頁時,訓練統計子頁重新查詢並反映新資料', (tester) async {
    // 登入 + 完成 Onboarding + 已同意隱私條款,三段守衛都放行,才能直接
    // 抵達 5-tab shell(見 router.dart resolveAuthRedirect 與 app.dart 的
    // 隱私同意浮層邏輯)。
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

    // 切到「數據」分頁(對應 router.dart branches 陣列的 index 2)。
    await tester.tap(find.widgetWithText(NavigationDestination, '數據'));
    await tester.pumpAndSettle();

    // 訓練統計是預設子頁,一開始沒有任何訓練,空狀態文案顯示。
    expect(find.byKey(const Key('volumeChartEmptyState')), findsOneWidget);

    // 切去「訓練」分頁——StatefulShellRoute.indexedStack 讓數據分頁不
    // dispose,StatsPage(以及裡面的 WorkoutStatsTab)還活著、只是不在畫面上。
    await tester.tap(find.widgetWithText(NavigationDestination, '訓練'));
    await tester.pumpAndSettle();

    // 在使用者切走的期間,資料庫多了一筆今日訓練(模擬波 3「記完訓練」
    // 後的場景)。
    final now = DateTime.now();
    await WorkoutRepository(db, ExerciseRepository(db)).create(
      Workout(
        id: 'landed-while-away',
        userId: testUserId,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 20)),
        duration: 20,
        totalVolume: 321,
        totalSets: 3,
        totalExercises: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // 切回數據分頁——router.dart 的 _AppShell.onDestinationSelected 應該在
    // 這裡呼叫 ref.invalidate(workoutStatsControllerProvider),讓
    // WorkoutStatsTab(雖然沒有被重建)背後的 provider 重新查詢。
    await tester.tap(find.widgetWithText(NavigationDestination, '數據'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('volumeChartEmptyState')), findsNothing);
    expect(find.byKey(const Key('statsRecentWorkoutRow-landed-while-away')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('statsWeekWorkoutCountCard')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });
}
