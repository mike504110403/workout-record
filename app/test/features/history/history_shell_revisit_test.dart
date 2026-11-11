// 切走再切回「歷史」分頁時,列表真的重新查詢並反映新資料。對照
// test/features/stats/stats_shell_revisit_test.dart 的手法:pump 完整
// `WorkItOutApp`(真 go_router `StatefulShellRoute.indexedStack` + 4-tab
// bottom nav),透過真實 `NavigationDestination` 點擊切分頁。這條守住的是
// router.dart 裡 `shouldRefreshHistoryOnBranchSwitch` 判斷之後,真的有呼叫
// `ref.invalidate(historyListControllerProvider)` 這一行接線本身
// (WAVE5 merge 接線,review MAJOR-2);純函式那半(index 對應)在
// test/router/router_redirect_test.dart。
//
// ui-polish(2026-11-11):訓練分頁拿掉,「切走」改切去「設定」;斷言改讀歷史
// controller 的 state(只驗重新查詢),不驗歷史頁版面元件。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/history/history_list_controller.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';

import '../../data/test_helpers.dart';

void main() {
  testWidgets('切走再切回歷史分頁時,列表重新查詢並反映新資料', (tester) async {
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

    // 切到「歷史」分頁(router.dart branches 陣列的 index 2),還沒有紀錄。
    await tester.tap(find.widgetWithText(NavigationDestination, '歷史'));
    await tester.pumpAndSettle();
    expect(container.read(historyListControllerProvider).value!.workouts, isEmpty);

    // 切去「設定」分頁——IndexedStack 讓歷史分頁不 dispose。
    await tester.tap(find.widgetWithText(NavigationDestination, '設定'));
    await tester.pumpAndSettle();

    // 切走期間資料庫多了一筆已完成訓練(模擬「記完訓練」場景)。
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

    // 切回歷史分頁——_refreshForBranch 應 invalidate 歷史兩個 provider,
    // 列表重新查詢後新訓練出現、空狀態消失。
    await tester.tap(find.widgetWithText(NavigationDestination, '歷史'));
    await tester.pumpAndSettle();

    expect(
      container.read(historyListControllerProvider).value!.workouts.map((w) => w.id),
      contains('landed-while-away'),
    );
  });
}
