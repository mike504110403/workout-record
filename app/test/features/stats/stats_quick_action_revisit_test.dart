// r2 review 打回記錄(major 2 的 probe 劇本):首頁快速操作走 `context.go(...)`
// 直接改變路由,不經過 `NavigationBar.onDestinationSelected`——這條路徑先前
// 完全沒有掛 invalidate,reviewer 實測發現切過去的分頁畫面停在舊資料。
// router.dart 改成 `_AppShellState.didUpdateWidget` 觀察
// `navigationShell.currentIndex` 本身的變化後,不管走哪條路徑都會經過同一個
// 失效點,這裡守的正是「程式化導航也會失效重查」。
//
// ui-polish(2026-11-11):首頁的「查看進度」快速操作由首頁切片拿掉,改用首頁
// 「最近訓練 → 查看全部」(`context.go('/history')`)這條仍存在的程式化導航
// 重寫;斷言改讀歷史 controller 的 state(只驗重新查詢,不驗歷史頁版面)。
// 檔名沿用(測試檔歸屬固定),內容已不限數據分頁。
//
// 第二條測試保留首頁切片的版本:首頁已無直達數據分頁的鈕,但「不經
// NavigationBar、直接 go('/stats')」這條觸發條件仍要守(數據分頁的失效點),
// 改由測試直接對 router 下 go 重現,並斷言數據頁新版面。
//
// 對照 test/features/history/history_shell_revisit_test.dart(bottom nav 路徑)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/history/history_list_controller.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';

import '../../data/test_helpers.dart';

Future<void> _tapViewAll(WidgetTester tester) async {
  final button = find.byKey(const Key('viewAllWorkoutsButton'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '從首頁「查看全部」(context.go)第二次進入歷史分頁時,也會反映期間新增的資料'
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

      // 第一次:用「查看全部」(非 bottom nav)進入歷史分頁——首次造訪,
      // provider 第一次 build(),理所當然是空的,不能單獨當作這條路徑有效的證據。
      await _tapViewAll(tester);
      expect(container.read(historyListControllerProvider).value!.workouts, isEmpty);

      // 切回首頁分頁(bottom nav)。
      await tester.tap(find.widgetWithText(NavigationDestination, '首頁'));
      await tester.pumpAndSettle();

      // 在使用者切走的期間,資料庫多了一筆已完成訓練。
      final now = DateTime.now();
      await DriftWorkoutRepository(db, DriftExerciseRepository(db)).create(
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

      // 第二次:再次用「查看全部」(不是點 bottom nav 的「歷史」圖示)回到
      // 歷史分頁——程式化導航這條路徑也要失效重查。
      await _tapViewAll(tester);

      expect(
        container.read(historyListControllerProvider).value!.workouts.map((w) => w.id),
        contains('landed-via-quick-action'),
      );
    },
  );

  testWidgets(
    '以 context.go 直接切到數據分頁(非 bottom nav 點擊)第二次進入數據分頁時,也會反映期間新增的資料'
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

      // 首頁已移除「查看進度」鈕;這條 bug 的觸發條件是「不經 NavigationBar
      // 點擊、直接 context.go('/stats')」,改由測試直接對 router 下 go 重現。
      void goStats() => GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/stats');

      // 第一次:用 context.go(非 bottom nav)進入數據分頁——
      // 首次造訪,provider 第一次 build(),理所當然是空狀態,不能單獨當
      // 作這條路徑有效的證據。
      goStats();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('volumeChartEmptyState')), findsOneWidget);

      // 切回首頁分頁(bottom nav)。
      await tester.tap(find.widgetWithText(NavigationDestination, '首頁'));
      await tester.pumpAndSettle();

      // 在使用者切走的期間,資料庫多了一筆今日訓練。
      final now = DateTime.now();
      await DriftWorkoutRepository(db, DriftExerciseRepository(db)).create(
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

      // 第二次:再次用 context.go(不是點 bottom nav 的「數據」圖示)回到
      // 數據分頁——這是先前壞掉的路徑,修好後這裡應該反映新資料。
      goStats();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('volumeChartEmptyState')), findsNothing);
      // 重新查詢後有 1 個資料點 → 「再記錄一筆就能看到趨勢」。
      expect(find.byKey(const Key('volumeChartNeedMoreData')), findsOneWidget);
    },
  );
}
