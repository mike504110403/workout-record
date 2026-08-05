// WorkoutStatsTab widget seam:pump 真實頁面(repositories/provider 一律用
// 真的,只換 appDatabaseProvider 為 in-memory DB),斷言畫面呈現的數字/
// 文案。比照 dashboard_page_test.dart 的慣例(不測 controller 內部欄位)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, Exercise;
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/stats/placeholders/pr_list_page.dart';
import 'package:workout_record/features/stats/workout_stats/workout_stats_tab.dart';

import '../../../data/test_helpers.dart';

Exercise _chestExercise({String id = 'ex-chest'}) => Exercise(
      id: id,
      name: '槓鈴臥推',
      categoryId: 'cat-chest',
      type: ExerciseType.freeWeight,
      primaryMuscleGroup: PrimaryMuscleGroup.chest,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

Exercise _legsExercise({String id = 'ex-legs'}) => Exercise(
      id: id,
      name: '槓鈴深蹲',
      categoryId: 'cat-legs',
      type: ExerciseType.freeWeight,
      primaryMuscleGroup: PrimaryMuscleGroup.legs,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

WorkoutSet _set({
  required String id,
  required String workoutExerciseId,
  required double weight,
  required int reps,
  bool isWarmup = false,
}) {
  final now = DateTime.now();
  return WorkoutSet(
    id: id,
    workoutExerciseId: workoutExerciseId,
    setNumber: 1,
    weight: weight,
    reps: reps,
    isWarmup: isWarmup,
    createdAt: now,
    updatedAt: now,
  );
}

/// 建一筆「已完成」訓練,[exercises] 帶完整 sets;[totalVolume] 對照
/// `completeWorkout()` 的規則手動算好(排除暖身)再傳入,模擬真實完成訓練
/// 後 DB 欄位會有的值(這裡不透過 completeWorkout,直接用 create() 整包
/// 寫入,行為與 dashboard 測試的 `_buildWorkout` 慣例一致)。
Workout _buildWorkout({
  required String id,
  required DateTime startedAt,
  DateTime? endedAt,
  double totalVolume = 0,
  int totalSets = 0,
  int totalExercises = 0,
  List<WorkoutExercise> exercises = const [],
}) {
  final now = DateTime.now();
  return Workout(
    id: id,
    userId: testUserId,
    startedAt: startedAt,
    endedAt: endedAt ?? startedAt.add(const Duration(minutes: 30)),
    totalVolume: totalVolume,
    totalSets: totalSets,
    totalExercises: totalExercises,
    exercises: exercises,
    createdAt: now,
    updatedAt: now,
  );
}

/// [id] 同時當作這個 WorkoutExercise 的 id,也是底下每組 [WorkoutSet] 的
/// `workoutExerciseId`(FK 參照)——呼叫端只需要給重量/次數清單,不需要另外
/// 對齊 id。
WorkoutExercise _workoutExercise({
  required String id,
  required String workoutId,
  required Exercise exercise,
  required List<({double weight, int reps, bool isWarmup})> sets,
}) {
  final now = DateTime.now();
  return WorkoutExercise(
    id: id,
    workoutId: workoutId,
    exerciseId: exercise.id,
    exerciseName: exercise.name,
    sets: [
      for (var i = 0; i < sets.length; i++)
        _set(
          id: '$id-set-$i',
          workoutExerciseId: id,
          weight: sets[i].weight,
          reps: sets[i].reps,
          isWarmup: sets[i].isWarmup,
        ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

/// 修復 M1/m3 風格的失敗路徑測試專用:模擬 `fetchByDateRange` 查詢拋錯,
/// 讓 workoutStatsControllerProvider 落入 AsyncError,驗證 error 分支真的
/// 會渲染、重試按鈕真的有效。只覆寫這一個方法,其餘沿用真實實作。
class _ThrowingWorkoutRepository extends WorkoutRepository {
  _ThrowingWorkoutRepository(super.db, super.exerciseRepository);

  var callCount = 0;

  @override
  Future<List<Workout>> fetchByDateRange(DateTime from, DateTime to) async {
    callCount += 1;
    if (callCount == 1) {
      throw Exception('模擬容量趨勢查詢失敗(workout stats error 分支測試用)');
    }
    return super.fetchByDateRange(from, to);
  }
}

class _Harness {
  _Harness(this.db, this.container)
      : exerciseRepo = ExerciseRepository(db),
        workoutRepo = WorkoutRepository(db, ExerciseRepository(db));

  final AppDatabase db;
  final ProviderContainer container;
  final ExerciseRepository exerciseRepo;
  final WorkoutRepository workoutRepo;
}

Future<_Harness> _setUpHarness({bool useThrowingWorkoutRepo = false}) async {
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);

  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (useThrowingWorkoutRepo)
        workoutRepositoryProvider.overrideWithValue(
          _ThrowingWorkoutRepository(db, ExerciseRepository(db)),
        ),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(db, container);
}

Future<void> _pump(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: Scaffold(body: WorkoutStatsTab())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('空狀態', () {
    testWidgets('沒有任何訓練時,圖表顯示空狀態文案、本週統計為 0、最近訓練顯示空狀態', (tester) async {
      final harness = await _setUpHarness();

      await _pump(tester, harness);

      expect(find.byKey(const Key('volumeChartEmptyState')), findsOneWidget);
      expect(find.text('尚無訓練數據'), findsOneWidget);
      expect(find.text('完成訓練後這裡會顯示容量趨勢'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('statsWeekWorkoutCountCard')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('statsRecentWorkoutsEmpty')), findsOneWidget);
    });
  });

  group('時間範圍切換', () {
    testWidgets('切到「週」只計 7 天內的訓練,圖表資料點數變少', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      final chest = _chestExercise();
      await harness.exerciseRepo.create(chest);

      // 3 筆落在最近 7 天內,2 筆落在 7~30 天之間(月範圍內、週範圍外)。
      for (var i = 0; i < 3; i++) {
        await harness.workoutRepo.create(
          _buildWorkout(
            id: 'in-week-$i',
            startedAt: now.subtract(Duration(days: i)),
            totalVolume: 100,
            exercises: [
              _workoutExercise(
                id: 'we-in-$i',
                workoutId: 'in-week-$i',
                exercise: chest,
                sets: const [(weight: 50, reps: 2, isWarmup: false)],
              ),
            ],
          ),
        );
      }
      for (var i = 10; i < 12; i++) {
        await harness.workoutRepo.create(
          _buildWorkout(
            id: 'in-month-$i',
            startedAt: now.subtract(Duration(days: i)),
            totalVolume: 200,
            exercises: [
              _workoutExercise(
                id: 'we-month-$i',
                workoutId: 'in-month-$i',
                exercise: chest,
                sets: const [(weight: 50, reps: 4, isWarmup: false)],
              ),
            ],
          ),
        );
      }

      await _pump(tester, harness);

      // 預設「月」範圍:5 筆全部落在 30 天內。
      expect(
        find.descendant(of: find.byKey(const Key('volumeStatCount')), matching: find.text('5')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('chartTimeRange-week')));
      await tester.pumpAndSettle();

      // 切到「週」:只剩最近 7 天內的 3 筆。
      expect(
        find.descendant(of: find.byKey(const Key('volumeStatCount')), matching: find.text('3')),
        findsOneWidget,
      );
    });
  });

  group('肌群篩選', () {
    testWidgets('切到特定肌群後,平均/最高容量只計該肌群的容量,「數據點」不受篩選影響', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      final chest = _chestExercise();
      final legs = _legsExercise();
      await harness.exerciseRepo.create(chest);
      await harness.exerciseRepo.create(legs);

      // 同一天練胸(500)+ 練腿(300),總容量 800。
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'w-mixed',
          startedAt: now,
          totalVolume: 800,
          exercises: [
            _workoutExercise(
              id: 'we-chest',
              workoutId: 'w-mixed',
              exercise: chest,
              sets: const [(weight: 100, reps: 5, isWarmup: false)],
            ),
            _workoutExercise(
              id: 'we-legs',
              workoutId: 'w-mixed',
              exercise: legs,
              sets: const [(weight: 60, reps: 5, isWarmup: false)],
            ),
          ],
        ),
      );

      await _pump(tester, harness);

      // all 模式:平均/最高 = 800,數據點 = 1。
      expect(
        find.descendant(of: find.byKey(const Key('volumeStatAverage')), matching: find.text('800 kg')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('volumeStatCount')), matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('muscleGroupChip-chest')));
      await tester.pumpAndSettle();

      // 篩選胸部後:平均/最高改成只算胸部的 500,不是總容量 800。
      expect(
        find.descendant(of: find.byKey(const Key('volumeStatAverage')), matching: find.text('500 kg')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('volumeStatHighest')), matching: find.text('500 kg')),
        findsOneWidget,
      );
      // 數據點數不受篩選影響,維持 1(對齊 iOS:固定顯示總天數)。
      expect(
        find.descendant(of: find.byKey(const Key('volumeStatCount')), matching: find.text('1')),
        findsOneWidget,
      );
    });
  });

  group('本週統計', () {
    testWidgets('計入本週內訓練,排除本週外(10 天前)、草稿(未完成)的訓練', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();

      await harness.workoutRepo.create(
        _buildWorkout(id: 'in-week', startedAt: now, totalVolume: 100),
      );
      // 週外:10 天前,任何合理的一週定義都會落在上週之外。
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'out-of-week',
          startedAt: now.subtract(const Duration(days: 10)),
          totalVolume: 999,
        ),
      );
      // 草稿:endedAt 為 null(進行中,未完成)——變異:草稿混入必紅。
      await harness.workoutRepo.create(
        Workout(
          id: 'draft',
          userId: testUserId,
          startedAt: now,
          totalVolume: 777,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _pump(tester, harness);

      final countCard = find.byKey(const Key('statsWeekWorkoutCountCard'));
      final volumeCard = find.byKey(const Key('statsWeekTotalVolumeCard'));
      expect(find.descendant(of: countCard, matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: volumeCard, matching: find.text('100')), findsOneWidget);
      // 反向斷言:週外/草稿的數字不該出現在本週統計卡片裡。
      expect(find.descendant(of: volumeCard, matching: find.text('999')), findsNothing);
      expect(find.descendant(of: volumeCard, matching: find.text('777')), findsNothing);
      expect(find.descendant(of: countCard, matching: find.text('3')), findsNothing);
    });
  });

  group('最近訓練', () {
    testWidgets('最多顯示 5 筆,PR 入口卡點擊會推到 PrListPage', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      for (var i = 0; i < 6; i++) {
        await harness.workoutRepo.create(
          _buildWorkout(
            id: 'recent-$i',
            startedAt: now.subtract(Duration(days: i)),
            totalVolume: (i + 1) * 100,
          ),
        );
      }

      await _pump(tester, harness);

      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('statsRecentWorkoutRow-recent-$i')), findsOneWidget, reason: 'i=$i 應該出現');
      }
      expect(find.byKey(const Key('statsRecentWorkoutRow-recent-5')), findsNothing, reason: '第 6 筆(最舊)應被排除');

      await tester.tap(find.byKey(const Key('prEntryCard')));
      await tester.pumpAndSettle();

      expect(find.byType(PrListPage), findsOneWidget);
    });
  });

  group('載入失敗', () {
    testWidgets('查詢拋錯時顯示 error 分支文案,重試後恢復', (tester) async {
      final harness = await _setUpHarness(useThrowingWorkoutRepo: true);

      await _pump(tester, harness);

      expect(find.text('載入失敗，請稍後再試'), findsOneWidget);
      final retryButton = find.byKey(const Key('workoutStatsErrorRetryButton'));
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(find.text('載入失敗，請稍後再試'), findsNothing);
      expect(find.byKey(const Key('volumeChartEmptyState')), findsOneWidget);
    });
  });
}
