// WorkoutStatsTab widget seam:pump 真實頁面(repositories/provider 一律用
// 真的,只換 appDatabaseProvider 為 in-memory DB),斷言畫面呈現的數字/
// 文案。比照 dashboard_page_test.dart 的慣例(不測 controller 內部欄位)。
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/data/db/app_database.dart' hide Workout, WorkoutExercise, WorkoutSet, Exercise;
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';
import 'package:workout_record/core/widgets/section_header.dart';
import 'package:workout_record/features/stats/pr/pr_list_page.dart';
import 'package:workout_record/features/stats/workout_stats/volume_chart_section.dart';
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
class _ThrowingWorkoutRepository extends DriftWorkoutRepository {
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
    : exerciseRepo = DriftExerciseRepository(db),
      workoutRepo = DriftWorkoutRepository(db, DriftExerciseRepository(db));

  final AppDatabase db;
  final ProviderContainer container;
  final ExerciseRepository exerciseRepo;
  final WorkoutRepository workoutRepo;
}

Future<_Harness> _setUpHarness({bool useThrowingWorkoutRepo = false, WeightUnit? weightUnit}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);

  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (weightUnit != null) weightUnitProvider.overrideWithValue(weightUnit),
      if (useThrowingWorkoutRepo)
        workoutRepositoryProvider.overrideWithValue(
          _ThrowingWorkoutRepository(db, DriftExerciseRepository(db)),
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

/// 肌群篩選是標題列右側的下拉選單(MenuAnchor):先點按鈕展開,再點選項。
Future<void> _selectMuscleGroup(WidgetTester tester, String filterName) async {
  await tester.tap(find.byKey(const Key('muscleGroupFilterButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('muscleGroupMenuItem-$filterName')));
  await tester.pumpAndSettle();
}

Future<void> _seedChestWorkouts(_Harness harness, int count) async {
  final chest = _chestExercise();
  await harness.exerciseRepo.create(chest);
  for (var i = 0; i < count; i++) {
    await harness.workoutRepo.create(
      _buildWorkout(
        id: 'trend-$i',
        startedAt: DateTime.now().subtract(Duration(days: i)),
        totalVolume: 100,
        exercises: [
          _workoutExercise(
            id: 'we-trend-$i',
            workoutId: 'trend-$i',
            exercise: chest,
            sets: const [(weight: 50, reps: 2, isWarmup: false)],
          ),
        ],
      ),
    );
  }
}

void main() {
  group('空狀態', () {
    testWidgets('沒有任何訓練時,圖表顯示空狀態文案', (tester) async {
      final harness = await _setUpHarness();

      await _pump(tester, harness);

      expect(find.byKey(const Key('volumeChartEmptyState')), findsOneWidget);
      expect(find.text('尚無訓練數據'), findsOneWidget);
      expect(find.text('完成訓練後這裡會顯示容量趨勢'), findsOneWidget);
    });
  });

  group('趨勢圖資料不足', () {
    testWidgets('只有 1 個資料點:不畫折線圖,顯示「再記錄一筆就能看到趨勢」;統計摘要照常', (tester) async {
      final harness = await _setUpHarness();
      await _seedChestWorkouts(harness, 1);

      await _pump(tester, harness);

      expect(find.byType(LineChart), findsNothing);
      expect(find.byKey(const Key('volumeChartNeedMoreData')), findsOneWidget);
      expect(find.text('再記錄一筆就能看到趨勢'), findsOneWidget);
      expect(find.byKey(const Key('volumeChartEmptyState')), findsNothing);
      expect(
        find.descendant(of: find.byKey(const Key('volumeStatCount')), matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('2 個資料點:開始畫折線圖', (tester) async {
      final harness = await _setUpHarness();
      await _seedChestWorkouts(harness, 2);

      await _pump(tester, harness);

      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byKey(const Key('volumeChartNeedMoreData')), findsNothing);
    });

    testWidgets('肌群篩選後可畫的點 < 2:改顯示空狀態(以篩選後點數為準);沒練到該肌群顯示專屬文案', (tester) async {
      final harness = await _setUpHarness();
      await _seedChestWorkouts(harness, 3); // 3 天都只練胸

      await _pump(tester, harness);
      expect(find.byType(LineChart), findsOneWidget);

      // 切到腿部:3 天都沒練腿 → 篩選後 0 點。
      await _selectMuscleGroup(tester, 'legs');
      expect(find.byType(LineChart), findsNothing);
      expect(find.byKey(const Key('volumeChartNoMuscleData')), findsOneWidget);
      expect(find.text('這段期間沒有腿部的紀錄'), findsOneWidget);

      // 切回胸部:3 點,恢復畫圖。
      await _selectMuscleGroup(tester, 'chest');
      expect(find.byType(LineChart), findsOneWidget);
    });
  });

  group('肌群下拉', () {
    testWidgets('肌群以下拉選單呈現(不再是 chip 列),按鈕顯示目前選取;選項包含全部七種', (tester) async {
      final harness = await _setUpHarness();
      await _pump(tester, harness);

      expect(find.byType(FilterChip), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('muscleGroupFilterLabel'))).data, '總容量');

      await tester.tap(find.byKey(const Key('muscleGroupFilterButton')));
      await tester.pumpAndSettle();
      for (final filter in ['all', 'chest', 'back', 'legs', 'shoulders', 'arms', 'core']) {
        expect(find.byKey(Key('muscleGroupMenuItem-$filter')), findsOneWidget, reason: filter);
      }

      await tester.tap(find.byKey(const Key('muscleGroupMenuItem-shoulders')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('muscleGroupFilterLabel'))).data, '肩部');
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

      await _selectMuscleGroup(tester, 'chest');

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

  // 介面改版:本週統計/最近訓練與首頁、歷史重複,從訓練子頁拿掉,只留趨勢圖與 PR 入口。
  group('精簡版面', () {
    testWidgets('有資料時也沒有「本週統計」「最近訓練」兩段', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await harness.workoutRepo.create(
          _buildWorkout(id: 'recent-$i', startedAt: now.subtract(Duration(days: i)), totalVolume: 100),
        );
      }

      await _pump(tester, harness);

      expect(find.text('本週統計'), findsNothing);
      expect(find.text('最近訓練'), findsNothing);
      expect(find.byKey(const Key('statsWeekWorkoutCountCard')), findsNothing);
      expect(find.byKey(const Key('statsWeekTotalVolumeCard')), findsNothing);
      expect(find.byKey(Key('statsRecentWorkoutRow-recent-0')), findsNothing);
      expect(find.byKey(const Key('statsRecentWorkoutsEmpty')), findsNothing);
      // 獨立的 PR 入口卡也改成標題列的一顆鈕。
      expect(find.byKey(const Key('prEntryCard')), findsNothing);
    });

    testWidgets('PR 入口是趨勢區標題列的一顆鈕,點擊推到 PrListPage', (tester) async {
      final harness = await _setUpHarness();
      await _pump(tester, harness);

      final prButton = find.byKey(const Key('prEntryButton'));
      expect(prButton, findsOneWidget);
      // 在趨勢區(同一張卡)標題列裡,與肌群下拉並排。
      expect(
        find.ancestor(of: prButton, matching: find.byType(VolumeChartSection)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(SectionHeader), matching: find.byKey(const Key('prEntryButton'))),
        findsOneWidget,
      );

      await tester.tap(prButton);
      await tester.pumpAndSettle();

      expect(find.byType(PrListPage), findsOneWidget);
    });

    testWidgets('第三格統計標籤是「訓練日」(dataPointCount 以日期聚合),不叫「次數」或「數據點」', (tester) async {
      final harness = await _setUpHarness();
      await _pump(tester, harness);

      expect(
        find.descendant(of: find.byKey(const Key('volumeStatCount')), matching: find.text('訓練日')),
        findsOneWidget,
      );
      expect(find.text('次數'), findsNothing);
      expect(find.text('數據點'), findsNothing);
    });

    testWidgets('趨勢折線圖外包 RepaintBoundary', (tester) async {
      final harness = await _setUpHarness();
      await _seedChestWorkouts(harness, 3);

      await _pump(tester, harness);

      // 該 key 必須掛在真正的 RepaintBoundary 上(不是任意 widget),且圖表在它底下。
      expect(tester.widget(find.byKey(const Key('volumeChartRepaintBoundary'))), isA<RepaintBoundary>());
      expect(
        find.descendant(
          of: find.byKey(const Key('volumeChartRepaintBoundary')),
          matching: find.byType(LineChart),
        ),
        findsOneWidget,
      );
    });
  });

  // 波 6:重量單位(lb 模式)。變異:任一消費點(平均/最高容量)漏接
  // weightUnitProvider、恆用 kg 必紅。期望值一律 `kgToDisplay` 現算。
  group('重量單位(lb 模式)', () {
    testWidgets('平均/最高容量換算成 lb 顯示', (tester) async {
      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
      final chest = _chestExercise();
      await harness.exerciseRepo.create(chest);
      // 容量圖的平均/最高由各組 weight×reps 現算(不看 totalVolume 欄位),所以
      // 要有真實的組:100kg × 10 = 1000,與 totalVolume 一致。
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'lb-1',
          startedAt: DateTime.now(),
          totalVolume: 1000,
          exercises: [
            _workoutExercise(
              id: 'we-lb',
              workoutId: 'lb-1',
              exercise: chest,
              sets: const [(weight: 100, reps: 10, isWarmup: false)],
            ),
          ],
        ),
      );

      await _pump(tester, harness);

      final lbBare = kgToDisplay(1000, WeightUnit.lb).toStringAsFixed(0);
      for (final key in const ['volumeStatAverage', 'volumeStatHighest']) {
        expect(
          find.descendant(of: find.byKey(Key(key)), matching: find.text('$lbBare lb')),
          findsOneWidget,
          reason: key,
        );
      }
      // kg 版字串不該殘留。
      expect(find.text('1000 kg'), findsNothing);
      expect(find.text('1000'), findsNothing);
    });
  });

  // 圖表 spots 以 (points, filter, unit) 為快取鍵:掛載後才切單位時 spots 必須重算。
  // 變異:拿掉 _spotsFor 的 `_spotsUnit != unit` 條件 → 切 lb 後 y 仍是 kg 值而紅。
  group('重量單位(掛載後切換)', () {
    testWidgets('掛載後 kg→lb:趨勢圖 spots y 值即時換算(100 kg → 220.462 lb)', (tester) async {
      final harness = await _setUpHarness();
      await _seedChestWorkouts(harness, 3);
      await _pump(tester, harness);

      LineChart chart() => tester.widget<LineChart>(
        find.descendant(
          of: find.byKey(const Key('volumeChartRepaintBoundary')),
          matching: find.byType(LineChart),
        ),
      );
      // 每天 50kg × 2 = 100kg(寫死字面值,不用 kgToDisplay 現算,避免測試與實作同錯)。
      expect(chart().data.lineBarsData.single.spots.map((s) => s.y), everyElement(closeTo(100.0, 0.001)));

      await harness.container.read(weightUnitControllerProvider.notifier).setUnit(WeightUnit.lb);
      await tester.pumpAndSettle();

      final ys = chart().data.lineBarsData.single.spots.map((s) => s.y).toList();
      expect(ys.length, 3);
      expect(ys, everyElement(closeTo(220.462, 0.001)));
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
