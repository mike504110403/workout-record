// M3 風格的真實回歸測試(切走再切回「數據」分頁時,訓練統計子頁真的重新
// 查詢並反映新資料)。對照
// test/features/dashboard/dashboard_shell_revisit_test.dart 的手法:刻意
// pump 完整的 `WorkItOutApp`(真的 go_router `StatefulShellRoute.indexedStack`
// + 4-tab bottom nav),透過真實的 `NavigationDestination` 點擊切分頁——不是
// 繞過 router、直接 pump `StatsPage` 單一 widget。這條測試守住的是
// router.dart 裡 `shouldRefreshStatsOnBranchSwitch` 判斷之後,真的有呼叫
// `ref.invalidate(workoutStatsControllerProvider)` 這一行接線本身;純函式
// 那半(index 對應)留在 test/router/router_redirect_test.dart。
//
// ui-polish(2026-11-11):訓練分頁拿掉,「切走」改切去「設定」。斷言兩層並存:
// controller state(驗真的重新查詢)+ 數據頁新版面(空狀態/「再一筆看趨勢」/
// 摘要次數)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/stats/body_weight/body_weight_controller.dart';
import 'package:workout_record/features/stats/powerlifting/powerlifting_controller.dart';
import 'package:workout_record/features/stats/workout_stats/workout_stats_controller.dart';
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
    // 抵達 4-tab shell(見 router.dart resolveAuthRedirect 與 app.dart 的
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

    // 切到「數據」分頁(對應 router.dart branches 陣列的 index 1)。
    await tester.tap(find.widgetWithText(NavigationDestination, '數據'));
    await tester.pumpAndSettle();

    // 訓練統計是預設子頁,一開始沒有任何訓練,空狀態文案顯示。
    expect(container.read(workoutStatsControllerProvider).value!.dataPoints, isEmpty);
    expect(find.byKey(const Key('volumeChartEmptyState')), findsOneWidget);

    // 切去「設定」分頁——StatefulShellRoute.indexedStack 讓數據分頁不
    // dispose,StatsPage(以及裡面的 WorkoutStatsTab)還活著、只是不在畫面上。
    await tester.tap(find.widgetWithText(NavigationDestination, '設定'));
    await tester.pumpAndSettle();

    // 在使用者切走的期間,資料庫多了一筆今日訓練(模擬波 3「記完訓練」
    // 後的場景)。
    final now = DateTime.now();
    await DriftWorkoutRepository(db, DriftExerciseRepository(db)).create(
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

    // 重新查詢後多了 1 筆 → 1 個資料點:不再是空狀態,而是「再記錄一筆就能看到
    // 趨勢」,且統計摘要的「次數」變成 1。
    final state = container.read(workoutStatsControllerProvider).value!;
    expect(state.dataPoints, hasLength(1));
    expect(state.stats.dataPointCount, 1);
    expect(find.byKey(const Key('volumeChartEmptyState')), findsNothing);
    expect(find.byKey(const Key('volumeChartNeedMoreData')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('volumeStatCount')), matching: find.text('1')),
      findsOneWidget,
    );
  });

  // 數據分頁子頁懶建置(只建目前選到的子頁)× router 切分頁失效點的交互:
  // router.dart 切回「數據」時對三個子頁 provider 都下 invalidate——invalidate
  // 對還沒建立的 provider 是 no-op,不會把它建出來;若改成 read/watch 之類
  // 會建立 provider 的寫法,未選過的「體重」「力量」子頁就會在背景查詢。
  testWidgets('切走再切回數據分頁:未選過的體重/力量子頁 provider 不被建立(不觸發查詢)', (tester) async {
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

    await tester.tap(find.widgetWithText(NavigationDestination, '數據'));
    await tester.pumpAndSettle();
    // 前提:預設子頁(訓練統計)已建立,另兩個子頁還沒選過。
    expect(container.exists(workoutStatsControllerProvider), isTrue);
    expect(container.exists(bodyWeightTabControllerProvider), isFalse);
    expect(container.exists(powerliftingControllerProvider), isFalse);

    await tester.tap(find.widgetWithText(NavigationDestination, '設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '數據'));
    await tester.pumpAndSettle();

    expect(container.exists(workoutStatsControllerProvider), isTrue);
    expect(container.exists(bodyWeightTabControllerProvider), isFalse);
    expect(container.exists(powerliftingControllerProvider), isFalse);
  });
}
