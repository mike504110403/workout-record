// r2 review 打回記錄(major 2 的 probe 劇本):Dashboard「查看進度」快速
// 操作走 `context.go('/stats')` 直接改變路由,不經過 `NavigationBar.
// onDestinationSelected`——這條路徑先前完全沒有掛 invalidate,reviewer
// 實測發現切到數據分頁後畫面停在舊資料。router.dart 改成
// `_AppShellState.didUpdateWidget` 觀察 `navigationShell.currentIndex`
// 本身的變化後,不管走哪條路徑都會經過同一個失效點,這裡驗證的正是這條
// 先前壞掉的路徑。
//
// 對照 test/features/stats/stats_shell_revisit_test.dart(既有的 bottom
// nav 路徑,先前就是好的,這裡確認同一份改動沒有讓它回歸)。
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
  testWidgets(
    '從 Dashboard「查看進度」快速操作(context.go)第二次進入數據分頁時,也會反映期間新增的資料'
    '(不只 bottom nav 點擊路徑)',
    (tester) async {
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

      // 第一次:用「查看進度」快速操作(非 bottom nav)進入數據分頁——
      // 首次造訪,provider 第一次 build(),理所當然是空狀態,不能單獨當
      // 作這條路徑有效的證據。
      await tester.tap(find.byKey(const Key('quickActionViewProgress')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('volumeChartEmptyState')), findsOneWidget);

      // 切回首頁分頁(bottom nav)。
      await tester.tap(find.widgetWithText(NavigationDestination, '首頁'));
      await tester.pumpAndSettle();

      // 在使用者切走的期間,資料庫多了一筆今日訓練。
      final now = DateTime.now();
      await WorkoutRepository(db, ExerciseRepository(db)).create(
        Workout(
          id: 'landed-via-quick-action',
          userId: testUserId,
          startedAt: now,
          endedAt: now.add(const Duration(minutes: 15)),
          duration: 15,
          totalVolume: 456,
          totalSets: 4,
          totalExercises: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 第二次:再次用「查看進度」快速操作(不是點 bottom nav 的「數據」
      // 圖示)回到數據分頁——這是先前壞掉的路徑,修好後這裡應該反映新資料。
      await tester.tap(find.byKey(const Key('quickActionViewProgress')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('volumeChartEmptyState')), findsNothing);
      expect(find.byKey(const Key('statsRecentWorkoutRow-landed-via-quick-action')), findsOneWidget);
    },
  );
}
