// 切走再切回「歷史」分頁時,列表真的重新查詢並反映新資料。對照
// test/features/stats/stats_shell_revisit_test.dart 的手法:pump 完整
// `WorkItOutApp`(真 go_router `StatefulShellRoute.indexedStack` + 5-tab
// bottom nav),透過真實 `NavigationDestination` 點擊切分頁。這條守住的是
// router.dart 裡 `shouldRefreshHistoryOnBranchSwitch` 判斷之後,真的有呼叫
// `ref.invalidate(historyListControllerProvider)` 這一行接線本身
// (WAVE5 merge 接線,review MAJOR-2);純函式那半(index 對應)在
// test/router/router_redirect_test.dart。
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

    // 切到「歷史」分頁(router.dart branches 陣列的 index 3),空狀態顯示。
    await tester.tap(find.widgetWithText(NavigationDestination, '歷史'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('historyEmptyState')), findsOneWidget);

    // 切去「訓練」分頁——IndexedStack 讓歷史分頁不 dispose。
    await tester.tap(find.widgetWithText(NavigationDestination, '訓練'));
    await tester.pumpAndSettle();

    // 切走期間資料庫多了一筆已完成訓練(模擬「記完訓練」場景)。
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

    // 切回歷史分頁——_refreshForBranch 應 invalidate 歷史兩個 provider,
    // 列表重新查詢後新訓練出現、空狀態消失。
    await tester.tap(find.widgetWithText(NavigationDestination, '歷史'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('historyEmptyState')), findsNothing);
    expect(find.byKey(const Key('historyWorkoutCard-landed-while-away')), findsOneWidget);
  });
}
