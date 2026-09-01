// Dashboard → 目標設定頁的導航接線 seam(波 5)。
//
// 變異清單:
//   - 目標區塊沒接 onTap 必紅:「點目標區塊」斷言 tap 後真的 push 出
//     GoalSettingsPage,不是裝飾。
//   - 拔掉 GoalSettingsController.save() 內的 dashboardControllerProvider
//     invalidate 必紅:「存檔返回」斷言回到 Dashboard 後進度卡反映新目標
//     (不是存檔前的舊 weeklyWorkoutGoal/百分比快取)——dashboardControllerProvider
//     不是 autoDispose,DashboardPage 全程掛在 GoalSettingsPage 底下沒被
//     卸載,拔掉 invalidate 的話這裡會停在存檔前的舊值。
//     (bodyWeightTabControllerProvider 那一路的失效改在
//     test/features/goals/goal_settings_page_test.dart 用 container 層級
//     單獨驗證,不在這裡重複覆蓋——那個 provider 沒有被這個測試的
//     DashboardPage 消費。)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide Workout, UserGoal;
import 'package:workout_record/data/models/user_goal.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/user_goal_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/dashboard/dashboard_page.dart';
import 'package:workout_record/features/goals/goal_settings_page.dart';

import '../../data/test_helpers.dart';

// 仿 dashboard_page_test.dart 的 `_buildWorkout`:endedAt 補 startedAt +
// duration,代表「已完成」訓練,才會被 WorkoutRepository 的查詢計入本週次數。
Workout _buildWorkout({required String id, required DateTime startedAt}) {
  final now = DateTime.now();
  return Workout(
    id: id,
    userId: testUserId,
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 60)),
    duration: 60,
    totalVolume: 1000,
    totalSets: 10,
    totalExercises: 3,
    createdAt: now,
    updatedAt: now,
  );
}

class _Harness {
  _Harness(this.db, this.container)
      : userGoalRepo = UserGoalRepository(db),
        workoutRepo = WorkoutRepository(db, ExerciseRepository(db));

  final AppDatabase db;
  final ProviderContainer container;
  final UserGoalRepository userGoalRepo;
  final WorkoutRepository workoutRepo;
}

Future<_Harness> _setUpHarness() async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
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
  return _Harness(db, container);
}

Future<void> _pumpDashboard(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: DashboardPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('點目標區塊 → 推入 GoalSettingsPage', (tester) async {
    final harness = await _setUpHarness();
    await _pumpDashboard(tester, harness);

    expect(find.byType(GoalSettingsPage), findsNothing);

    // review 打回 S3 後,goalProgressSectionEntry 多包了一層 Card + 標題列
    // trailing chevron,整塊高度變高,預設 800x600 測試視窗裝不下,tap
    // 前先捲動讓它進可視範圍(同 dashboard_page_test.dart「查看全部」測試的
    // ensureVisible 慣例)。
    await tester.ensureVisible(find.byKey(const Key('goalProgressSectionEntry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goalProgressSectionEntry')));
    await tester.pumpAndSettle();

    expect(find.byType(GoalSettingsPage), findsOneWidget);
    expect(find.text('目標設定'), findsOneWidget);
  });

  testWidgets('設定頁存新週次數 → 返回 Dashboard → 進度文字反映新目標(不是存檔前的舊值)',
      (tester) async {
    final harness = await _setUpHarness();
    final now = DateTime.now();
    await harness.userGoalRepo.createOrUpdate(
      UserGoal(
        id: 'goal-1',
        userId: testUserId,
        weeklyWorkoutGoal: 4,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: now));

    await _pumpDashboard(tester, harness);

    expect(find.text('1 / 4 次'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);

    // review 打回 S3 後,goalProgressSectionEntry 多包了一層 Card + 標題列
    // trailing chevron,整塊高度變高,預設 800x600 測試視窗裝不下,tap
    // 前先捲動讓它進可視範圍(同 dashboard_page_test.dart「查看全部」測試的
    // ensureVisible 慣例)。
    await tester.ensureVisible(find.byKey(const Key('goalProgressSectionEntry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goalProgressSectionEntry')));
    await tester.pumpAndSettle();

    expect(find.byType(GoalSettingsPage), findsOneWidget);
    await tester.enterText(find.byKey(const Key('weeklyWorkoutGoalField')), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveGoalSettingsButton')));
    await tester.pumpAndSettle();

    // 已返回 Dashboard(GoalSettingsPage 已 pop)。
    expect(find.byType(GoalSettingsPage), findsNothing);

    // 進度卡反映新目標,不是存檔前的舊值快取。
    expect(find.text('1 / 2 次'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('1 / 4 次'), findsNothing);
    expect(find.text('25%'), findsNothing);
  });
}
