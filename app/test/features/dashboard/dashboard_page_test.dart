// DashboardPage widget seam:pump 真實頁面(repositories/provider 一律用真的,
// 只換 appDatabaseProvider 為 in-memory DB、sharedPreferencesProvider 為 mock
// prefs),斷言畫面呈現的數字/文案——不測 controller 內部欄位。
//
// 週界測試刻意用「10 天前」這種粗粒度區間(任何合理的一週定義都會落在上週)
// 做主要的本週內/外區分,額外再用一組獨立算法(逐日往回找星期一,不是複製
// dashboard_controller.dart 裡的算式)算出的精確週一邊界,驗證邊界前後各一
// 筆種子被正確排除/計入——週界算錯或範圍寫反時,這兩組測試都必須紅。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, BodyWeight, UserGoal;
import 'package:workout_record/data/models/body_weight.dart';
import 'package:workout_record/data/models/user_goal.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/body_weight_repository.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/user_goal_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/dashboard/dashboard_controller.dart';
import 'package:workout_record/features/dashboard/dashboard_page.dart';

import '../../data/test_helpers.dart';

Workout _buildWorkout({
  required String id,
  required DateTime startedAt,
  int duration = 60,
  double totalVolume = 1000,
  int totalSets = 10,
  int totalExercises = 3,
}) {
  final now = DateTime.now();
  return Workout(
    id: id,
    userId: testUserId,
    startedAt: startedAt,
    duration: duration,
    totalVolume: totalVolume,
    totalSets: totalSets,
    totalExercises: totalExercises,
    createdAt: now,
    updatedAt: now,
  );
}

/// 獨立於 dashboard_controller.dart 算法的週一邊界計算——逐日往回找,不是
/// 複製被測程式的「今天減去 (weekday - 1) 天」算式,避免測試跟被測程式抄
/// 同一個(可能錯誤的)公式互相掩護。
DateTime _referenceWeekStart(DateTime now) {
  var day = DateTime(now.year, now.month, now.day);
  while (day.weekday != DateTime.monday) {
    day = day.subtract(const Duration(days: 1));
  }
  return day;
}

class _DashboardHarness {
  _DashboardHarness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;

  WorkoutRepository get workoutRepo => WorkoutRepository(db, ExerciseRepository(db));
  BodyWeightRepository get bodyWeightRepo => BodyWeightRepository(db);
  UserGoalRepository get userGoalRepo => UserGoalRepository(db);
}

Future<_DashboardHarness> _setUpHarness(WidgetTester tester) async {
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
  return _DashboardHarness(db, container);
}

Future<void> _pumpDashboard(WidgetTester tester, _DashboardHarness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: DashboardPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<GoRouter> _pumpDashboardWithRouter(WidgetTester tester, _DashboardHarness harness) async {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardPage()),
      GoRoute(
        path: '/workout',
        builder: (context, state) => const Scaffold(body: Text('workout-route-marker')),
      ),
      GoRoute(
        path: '/stats',
        builder: (context, state) => const Scaffold(body: Text('stats-route-marker')),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const Scaffold(body: Text('history-route-marker')),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('今日概覽', () {
    testWidgets('今日有訓練時顯示今日訓練卡,時長/總容量/組數/動作數正確', (tester) async {
      final harness = await _setUpHarness(tester);
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'today-1',
          startedAt: DateTime.now(),
          duration: 75,
          totalVolume: 5230,
          totalSets: 24,
          totalExercises: 6,
        ),
      );

      await _pumpDashboard(tester, harness);

      final todayCard = find.byKey(const Key('todayWorkoutCard'));
      expect(todayCard, findsOneWidget);
      expect(find.byKey(const Key('noWorkoutTodayCard')), findsNothing);
      // 這筆今日訓練同時也會出現在「最近訓練」列表,時長/組數等文字可能重複
      // 出現在畫面兩處,所以這裡的斷言一律限定在 todayWorkoutCard 子樹內。
      expect(find.descendant(of: todayCard, matching: find.text('今日已完成訓練')), findsOneWidget);
      expect(find.descendant(of: todayCard, matching: find.text('75 分鐘')), findsOneWidget);
      expect(find.descendant(of: todayCard, matching: find.text('5230 kg')), findsOneWidget);
      expect(find.descendant(of: todayCard, matching: find.text('24')), findsOneWidget);
      expect(find.descendant(of: todayCard, matching: find.text('6')), findsOneWidget);
    });

    testWidgets('今日無訓練時顯示 NoWorkoutTodayCard', (tester) async {
      final harness = await _setUpHarness(tester);

      await _pumpDashboard(tester, harness);

      expect(find.byKey(const Key('noWorkoutTodayCard')), findsOneWidget);
      expect(find.byKey(const Key('todayWorkoutCard')), findsNothing);
      expect(find.text('今日尚未訓練'), findsOneWidget);
    });
  });

  group('最新體重', () {
    testWidgets('顯示最新一筆體重;記錄體重存檔後畫面刷新為新值(走真實 repository 寫入)', (tester) async {
      final harness = await _setUpHarness(tester);
      final now = DateTime.now();
      await harness.bodyWeightRepo.create(
        BodyWeight(
          id: 'bw-old',
          userId: testUserId,
          weight: 70.0,
          measuredAt: now.subtract(const Duration(days: 3)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.bodyWeightRepo.create(
        BodyWeight(
          id: 'bw-new',
          userId: testUserId,
          // 刻意跟「等一下 UI 觸發的真實寫入」錯開至少 30 秒:Drift 的
          // dateTime() 欄位預設用「整數秒」精度存欄位(不是毫秒),用
          // `now` 會跟緊接著發生的真實寫入落在同一秒、變成兩筆
          // measuredAt 完全相同的並列——getLatestWeight() 排序在這種並列
          // 情況下由 SQLite 決定順序,不保證挑到後寫入的那筆,測試會間歇
          // 性 flaky(這裡吃過虧,見除錯記錄)。這是資料層既有的秒級精度
          // 限制,不在本波「不碰 data/」的範圍內修,測試端刻意拉開時間差
          // 避開它。
          weight: 71.2,
          measuredAt: now.subtract(const Duration(seconds: 30)),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _pumpDashboard(tester, harness);

      expect(find.text('71.2 kg'), findsOneWidget);
      expect(find.text('70.0 kg'), findsNothing);

      await tester.tap(find.byKey(const Key('quickActionRecordWeight')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bodyWeightInputField')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('bodyWeightInputField')), '82.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
      await tester.pumpAndSettle();

      // 畫面刷新為新值。
      expect(find.text('82.5 kg'), findsOneWidget);
      expect(find.text('71.2 kg'), findsNothing);

      // 直接查 repository,證明是真的寫進 DB,不是單純的本地畫面狀態。
      final latest = await harness.bodyWeightRepo.getLatestWeight();
      expect(latest?.weight, 82.5);
    });
  });

  group('目標進度', () {
    testWidgets('weeklyGoal=4、本週已練 1 次 → 25%,「不錯的開始」', (tester) async {
      final harness = await _setUpHarness(tester);
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

      expect(find.byKey(const Key('goalProgressCard')), findsOneWidget);
      expect(find.text('1 / 4 次'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('不錯的開始！繼續加油💪'), findsOneWidget);
    });

    testWidgets('weeklyGoal=4、本週已練 3 次 → 75%,「快達成目標了」', (tester) async {
      final harness = await _setUpHarness(tester);
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
      await harness.workoutRepo.create(_buildWorkout(id: 'w-2', startedAt: now));
      await harness.workoutRepo.create(_buildWorkout(id: 'w-3', startedAt: now));

      await _pumpDashboard(tester, harness);

      expect(find.text('3 / 4 次'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('快達成目標了！再加把勁🔥'), findsOneWidget);
    });

    testWidgets('未設定目標時顯示空狀態提示(不顯示進度卡)', (tester) async {
      final harness = await _setUpHarness(tester);

      await _pumpDashboard(tester, harness);

      expect(find.byKey(const Key('goalEmptyState')), findsOneWidget);
      expect(find.byKey(const Key('goalProgressCard')), findsNothing);
      expect(find.text(kNoGoalMessage), findsOneWidget);
    });
  });

  group('本週統計', () {
    testWidgets('計入本週內種子訓練,排除本週外(10 天前)的種子訓練', (tester) async {
      final harness = await _setUpHarness(tester);
      final now = DateTime.now();
      await harness.workoutRepo.create(
        _buildWorkout(id: 'in-week', startedAt: now, totalVolume: 100, totalSets: 5),
      );
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'out-of-week',
          startedAt: now.subtract(const Duration(days: 10)),
          totalVolume: 999,
          totalSets: 50,
        ),
      );

      await _pumpDashboard(tester, harness);

      expect(
        find.descendant(
          of: find.byKey(const Key('weekWorkoutCountCard')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('weekTotalVolumeCard')),
          matching: find.text('100'),
        ),
        findsOneWidget,
      );
      // 若週界算錯把上週的種子也算進來,總容量會變成 1099,次數變成 2。
      expect(find.text('1099'), findsNothing);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('精確週一邊界:邊界前一小時排除,邊界後一小時計入', (tester) async {
      final harness = await _setUpHarness(tester);
      final now = DateTime.now();
      final weekStart = _referenceWeekStart(now);

      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'just-inside',
          startedAt: weekStart.add(const Duration(hours: 1)),
          totalVolume: 50,
          totalSets: 1,
        ),
      );
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'just-outside',
          startedAt: weekStart.subtract(const Duration(hours: 1)),
          totalVolume: 77,
          totalSets: 1,
        ),
      );

      await _pumpDashboard(tester, harness);

      expect(
        find.descendant(
          of: find.byKey(const Key('weekWorkoutCountCard')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('weekTotalVolumeCard')),
          matching: find.text('50'),
        ),
        findsOneWidget,
      );
    });
  });

  group('最近訓練', () {
    testWidgets('最多顯示 5 筆,排序新到舊', (tester) async {
      final harness = await _setUpHarness(tester);
      final now = DateTime.now();
      // i=0 最新(今天),i=5 最舊(6 天前)——刻意讓 6 筆散在不同天,避免落在
      // 同一個「今日」桶內互相干擾今日概覽卡片的斷言。
      for (var i = 0; i < 6; i++) {
        await harness.workoutRepo.create(
          _buildWorkout(
            id: 'recent-$i',
            startedAt: now.subtract(Duration(days: i)),
            totalVolume: (i + 1) * 100,
          ),
        );
      }

      await _pumpDashboard(tester, harness);

      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('recentWorkoutRow-recent-$i')), findsOneWidget, reason: 'i=$i 應該出現');
      }
      expect(find.byKey(const Key('recentWorkoutRow-recent-5')), findsNothing, reason: '第 6 筆(最舊)應被排除');

      // 新到舊排序:recent-0(最新)應該畫在 recent-4(最舊留下的那筆)上方。
      final topY = tester.getCenter(find.byKey(const Key('recentWorkoutRow-recent-0'))).dy;
      final bottomY = tester.getCenter(find.byKey(const Key('recentWorkoutRow-recent-4'))).dy;
      expect(topY, lessThan(bottomY));
    });
  });

  group('快速操作與導航', () {
    testWidgets('「開始訓練」導到 /workout', (tester) async {
      final harness = await _setUpHarness(tester);
      await _pumpDashboardWithRouter(tester, harness);

      await tester.tap(find.byKey(const Key('quickActionStartWorkout')));
      await tester.pumpAndSettle();

      expect(find.text('workout-route-marker'), findsOneWidget);
    });

    testWidgets('「查看進度」導到 /stats', (tester) async {
      final harness = await _setUpHarness(tester);
      await _pumpDashboardWithRouter(tester, harness);

      await tester.tap(find.byKey(const Key('quickActionViewProgress')));
      await tester.pumpAndSettle();

      expect(find.text('stats-route-marker'), findsOneWidget);
    });

    testWidgets('「查看全部」導到 /history', (tester) async {
      final harness = await _setUpHarness(tester);
      await _pumpDashboardWithRouter(tester, harness);

      // 「查看全部」在頁面下半部,測試視窗高度有限,先捲動讓它進入可視範圍
      // 才能被 tap() 命中。
      await tester.ensureVisible(find.byKey(const Key('viewAllWorkoutsButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('viewAllWorkoutsButton')));
      await tester.pumpAndSettle();

      expect(find.text('history-route-marker'), findsOneWidget);
    });

    testWidgets('「記錄體重」開啟 bottom sheet(不導航離開首頁)', (tester) async {
      final harness = await _setUpHarness(tester);
      await _pumpDashboardWithRouter(tester, harness);

      await tester.tap(find.byKey(const Key('quickActionRecordWeight')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bodyWeightInputField')), findsOneWidget);
      expect(find.text('workout-route-marker'), findsNothing);
    });
  });

  group('跨表組裝', () {
    testWidgets('五區塊同時正確組裝(Users/Workouts/BodyWeights/UserGoals 跨表)', (tester) async {
      final harness = await _setUpHarness(tester);
      final now = DateTime.now();

      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 2,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.bodyWeightRepo.create(
        BodyWeight(
          id: 'bw-1',
          userId: testUserId,
          weight: 68.4,
          measuredAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      // 今日訓練,同時計入本週統計。
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'today',
          startedAt: now,
          duration: 50,
          totalVolume: 300,
          totalSets: 12,
          totalExercises: 4,
        ),
      );
      // 上週訓練,不該計入本週統計、也不是最近訓練列表的干擾(仍會出現在
      // fetchRecent,只是本測試不特別斷言它)。
      await harness.workoutRepo.create(
        _buildWorkout(id: 'last-week', startedAt: now.subtract(const Duration(days: 9))),
      );

      await _pumpDashboard(tester, harness);

      // 今日概覽。
      final todayCard = find.byKey(const Key('todayWorkoutCard'));
      expect(todayCard, findsOneWidget);
      // 這筆今日訓練同時也是「最近訓練」列表的一員,「50 分鐘」文字會重複
      // 出現兩處,斷言限定在 todayWorkoutCard 子樹內。
      expect(find.descendant(of: todayCard, matching: find.text('50 分鐘')), findsOneWidget);
      // 最新體重。
      expect(find.text('68.4 kg'), findsOneWidget);
      // 目標進度:1/2 次 = 50%。
      expect(find.text('1 / 2 次'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      // 本週統計:只計今天那筆,不計上週那筆。
      expect(
        find.descendant(
          of: find.byKey(const Key('weekWorkoutCountCard')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      // 最近訓練:兩筆都會列出(fetchRecent 不分本週/上週)。
      expect(find.byKey(const Key('recentWorkoutRow-today')), findsOneWidget);
      expect(find.byKey(const Key('recentWorkoutRow-last-week')), findsOneWidget);
    });
  });
}
