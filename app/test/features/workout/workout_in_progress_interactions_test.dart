// 進行中訓練頁的 ui-polish 新互動(只在這一頁開啟,歷史編輯頁維持舊行為):
// - 組列「點列=編輯、左滑=刪除」,列內沒有鉛筆與 X。
// - 計畫組:灰色顯示、數字預填「上次同一組」(沒有才用模板值)、打勾記成
//   真實組、點開改數字再存、左滑不做。
// - 記組 sheet 第一組預填該動作歷史最後一組;「存並再記一組」。
// - 選完動作自動開記組 sheet。
// 真 in-memory DB + 真 repositories,只 override DB/prefs。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, Exercise;
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/rest_timer_controller.dart';
import 'package:workout_record/features/workout/templates/applied_template.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/workout/workout_in_progress_view.dart';

import '../../data/test_helpers.dart';

typedef _Harness = ({AppDatabase db, ProviderContainer container});

/// fetchRecent 前 [failuresLeft] 次拋錯(模擬離線),之後照常查 DB。
class _FlakyFetchRecentRepository extends DriftWorkoutRepository {
  _FlakyFetchRecentRepository(super.db, super.exerciseRepository, {required this.failuresLeft});

  int failuresLeft;
  var calls = 0;

  @override
  Future<List<Workout>> fetchRecent(int limit) async {
    calls += 1;
    if (failuresLeft > 0) {
      failuresLeft -= 1;
      throw Exception('模擬離線');
    }
    return super.fetchRecent(limit);
  }
}

/// 測試用 controller:計畫組移除一律失敗;可直接把 state 切成「結算寫入中」。
class _TestController extends WorkoutController {
  @override
  Future<void> removePlannedSet({required String workoutExerciseId, required String plannedSetId}) async {
    throw Exception('模擬移除失敗');
  }

  void forceCompleting() {
    final flow = state.value!;
    state = AsyncData(WorkoutFlowState(draft: flow.draft, plannedSets: flow.plannedSets, isCompleting: true));
  }
}

Future<_Harness> _setUp({
  bool testController = false,
  WorkoutRepository Function(AppDatabase db)? repo,
}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (testController) workoutControllerProvider.overrideWith(_TestController.new),
      if (repo != null) workoutRepositoryProvider.overrideWithValue(repo(db)),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (db: db, container: container);
}

Future<void> _pumpView(WidgetTester tester, _Harness h) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: const MaterialApp(home: Scaffold(body: WorkoutInProgressView())),
    ),
  );
  await tester.pumpAndSettle();
}

/// 寫一場已完成訓練當「上一次」:[exercise] 做了 [sets](重量, 次數)。
Future<void> _seedHistory(AppDatabase db, Exercise exercise, List<(double, int)> sets) async {
  final at = DateTime(2026, 11, 1, 9);
  await DriftWorkoutRepository(db, DriftExerciseRepository(db)).create(
    Workout(
      id: 'past',
      userId: testUserId,
      startedAt: at,
      endedAt: at.add(const Duration(minutes: 40)),
      createdAt: at,
      updatedAt: at,
      exercises: [
        WorkoutExercise(
          id: 'past-we',
          workoutId: 'past',
          exerciseId: exercise.id,
          exerciseName: exercise.name,
          createdAt: at,
          updatedAt: at,
          sets: [
            for (var i = 0; i < sets.length; i++)
              WorkoutSet(
                id: 'past-s$i',
                workoutExerciseId: 'past-we',
                setNumber: i + 1,
                weight: sets[i].$1,
                reps: sets[i].$2,
                createdAt: at,
                updatedAt: at,
              ),
          ],
        ),
      ],
    ),
  );
}

/// 記完組會自動啟動休息倒數(Timer.periodic 掛在 provider 上);測試結束前
/// 停掉,否則 widget 樹拆掉時還有 pending timer。
void _stopRest(_Harness h) => h.container.read(restTimerControllerProvider.notifier).skip();

WorkoutFlowState _flow(_Harness h) => h.container.read(workoutControllerProvider).value!;

String _field(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

Future<Exercise> _exercise(AppDatabase db, [int index = 0]) async =>
    (await DriftExerciseRepository(db).fetchSystemExercises())[index];

void main() {
  group('組列:點列編輯、左滑刪除', () {
    Future<(_Harness, String, String)> withOneSet(WidgetTester tester) async {
      final h = await _setUp();
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await h.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(await _exercise(h.db));
      final we = _flow(h).draft!.exercises.single.id;
      await notifier.addSet(workoutExerciseId: we, weight: 60, reps: 8);
      final setId = _flow(h).draft!.exercises.single.sets.single.id;
      await _pumpView(tester, h);
      return (h, we, setId);
    }

    testWidgets('列內只有數字,沒有鉛筆與 X', (tester) async {
      await withOneSet(tester);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text('60 kg × 8'), findsOneWidget);
    });

    testWidgets('點列 → 開編輯 sheet(帶入該組)→ 改次數存檔 → DB 更新', (tester) async {
      final (h, _, setId) = await withOneSet(tester);

      await tester.tap(find.byKey(Key('setRowTap_$setId')));
      await tester.pumpAndSettle();
      expect(_field(tester, 'addSetWeightField'), '60');
      expect(_field(tester, 'addSetRepsField'), '8');
      // 編輯不提供「存並再記一組」。
      expect(find.byKey(const Key('addSetSaveAndContinueButton')), findsNothing);

      await tester.enterText(find.byKey(const Key('addSetRepsField')), '10');
      await tester.tap(find.byKey(const Key('addSetSaveButton')));
      await tester.pumpAndSettle();

      expect(_flow(h).draft!.exercises.single.sets.single.reps, 10);
    });

    testWidgets('左滑 → 刪除該組', (tester) async {
      final (h, _, setId) = await withOneSet(tester);

      await tester.drag(find.byKey(Key('setRowTap_$setId')), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(_flow(h).draft!.exercises.single.sets, isEmpty);
      expect(find.byKey(Key('setRow_$setId')), findsNothing);
    });
  });

  group('計畫組(模板開始)', () {
    Future<_Harness> fromTemplate(
      WidgetTester tester, {
      List<(double, int)>? history,
      bool testController = false,
    }) async {
      final h = await _setUp(testController: testController);
      final exercise = await _exercise(h.db);
      if (history != null) await _seedHistory(h.db, exercise, history);
      await h.container.read(workoutControllerProvider.future);
      await h.container
          .read(workoutControllerProvider.notifier)
          .startFromTemplate(
            AppliedTemplate(
              templateId: 't',
              templateName: '模板',
              exercises: [
                AppliedTemplateExercise(
                  exerciseId: exercise.id,
                  exerciseName: exercise.name,
                  sets: const [
                    AppliedTemplateSet(weight: 0, reps: 10),
                    AppliedTemplateSet(weight: 0, reps: 10),
                    AppliedTemplateSet(weight: 0, reps: 10),
                  ],
                ),
              ],
            ),
          );
      await _pumpView(tester, h);
      return h;
    }

    testWidgets('沒有歷史 → 顯示模板值(0 kg × 10);打勾 → 真實組 +1、該計畫組消失', (tester) async {
      final h = await fromTemplate(tester);
      final we = _flow(h).draft!.exercises.single.id;
      final planned = _flow(h).plannedSets[we]!;
      expect(find.text('0 kg × 10'), findsNWidgets(3));

      await tester.tap(find.byKey(Key('confirmPlannedSet_${planned.first.id}')));
      await tester.pumpAndSettle();

      final sets = _flow(h).draft!.exercises.single.sets;
      expect(sets, hasLength(1));
      expect((sets.single.weight, sets.single.reps), (0.0, 10));
      expect(find.byKey(Key('plannedSetRow_${planned.first.id}')), findsNothing);
      expect(find.byKey(Key('setRow_${sets.single.id}')), findsOneWidget);
      _stopRest(h);
    });

    testWidgets('有歷史 → 計畫組預填上次同一組的數字,打勾照顯示的數字記', (tester) async {
      final h = await fromTemplate(tester, history: [(80, 5), (85, 4)]);
      final we = _flow(h).draft!.exercises.single.id;
      final planned = _flow(h).plannedSets[we]!;

      expect(find.text('80 kg × 5'), findsOneWidget);
      // 上次只有 2 組:第 3 組沿用上次最後一組。
      expect(find.text('85 kg × 4'), findsNWidgets(2));

      await tester.tap(find.byKey(Key('confirmPlannedSet_${planned.first.id}')));
      await tester.pumpAndSettle();
      final set = _flow(h).draft!.exercises.single.sets.single;
      expect((set.weight, set.reps), (80.0, 5));
      _stopRest(h);
    });

    testWidgets('點計畫組 → 開 sheet 改數字 → 存成真實組', (tester) async {
      final h = await fromTemplate(tester);
      final we = _flow(h).draft!.exercises.single.id;
      final planned = _flow(h).plannedSets[we]!;

      await tester.tap(find.byKey(Key('plannedSetRow_${planned[1].id}')));
      await tester.pumpAndSettle();
      expect(find.text('第 2 組'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('addSetWeightField')), '40');
      await tester.tap(find.byKey(const Key('addSetSaveButton')));
      await tester.pumpAndSettle();

      final set = _flow(h).draft!.exercises.single.sets.single;
      expect((set.weight, set.reps), (40.0, 10));
      expect(_flow(h).plannedSets[we]!.map((p) => p.id), isNot(contains(planned[1].id)));
      _stopRest(h);
    });

    testWidgets('左滑計畫組 → 不做這組(不寫 DB)', (tester) async {
      final h = await fromTemplate(tester);
      final we = _flow(h).draft!.exercises.single.id;
      final planned = _flow(h).plannedSets[we]!;

      await tester.drag(find.byKey(Key('plannedSetRow_${planned.last.id}')), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(_flow(h).plannedSets[we], hasLength(2));
      expect(_flow(h).draft!.exercises.single.sets, isEmpty);
    });

    testWidgets('左滑計畫組但移除失敗 → 列滑回原位、提示錯誤(flow-fix 4)', (tester) async {
      final h = await fromTemplate(tester, testController: true);
      final we = _flow(h).draft!.exercises.single.id;
      final planned = _flow(h).plannedSets[we]!;

      await tester.drag(find.byKey(Key('plannedSetRow_${planned.last.id}')), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(Key('plannedSetRow_${planned.last.id}')), findsOneWidget);
      expect(_flow(h).plannedSets[we], hasLength(3));
      expect(find.textContaining('移除計畫組失敗'), findsOneWidget);
    });

    testWidgets('結算寫入中 → 計畫組打勾/點擊/左滑、組列點擊/左滑、新增組數全部停用(flow-fix 5)', (tester) async {
      final h = await fromTemplate(tester, testController: true);
      final notifier = h.container.read(workoutControllerProvider.notifier) as _TestController;
      final we = _flow(h).draft!.exercises.single.id;
      final planned = _flow(h).plannedSets[we]!;
      await tester.tap(find.byKey(Key('confirmPlannedSet_${planned.first.id}')));
      await tester.pumpAndSettle();
      _stopRest(h);
      final setId = _flow(h).draft!.exercises.single.sets.single.id;

      // 結算前:都可操作。
      expect(tester.widget<IconButton>(find.byKey(Key('confirmPlannedSet_${planned[1].id}'))).onPressed, isNotNull);

      notifier.forceCompleting();
      await tester.pump();

      expect(tester.widget<IconButton>(find.byKey(Key('confirmPlannedSet_${planned[1].id}'))).onPressed, isNull);
      expect(tester.widget<InkWell>(find.byKey(Key('plannedSetRow_${planned[1].id}'))).onTap, isNull);
      expect(
        tester.widget<Dismissible>(find.byKey(ValueKey('dismissPlanned_${planned[1].id}'))).direction,
        DismissDirection.none,
      );
      expect(tester.widget<InkWell>(find.byKey(Key('setRowTap_$setId'))).onTap, isNull);
      expect(
        tester.widget<Dismissible>(find.byKey(ValueKey('dismissSet_$setId'))).direction,
        DismissDirection.none,
      );
      expect(tester.widget<TextButton>(find.byKey(Key('addSetButton_$we'))).onPressed, isNull);

      // 實際點下去也不會開 sheet、不會多記組。
      await tester.tap(find.byKey(Key('confirmPlannedSet_${planned[1].id}')), warnIfMissed: false);
      await tester.tap(find.byKey(Key('addSetButton_$we')), warnIfMissed: false);
      // 完成鈕的轉圈動畫不會停,不能 pumpAndSettle;過一段 sheet 動畫時間即可。
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('addSetWeightField')), findsNothing);
      expect(_flow(h).draft!.exercises.single.sets, hasLength(1));
    });
  });

  group('記組 sheet(進行中頁)', () {
    testWidgets('第一組預填該動作歷史最後一組(正式組)', (tester) async {
      final h = await _setUp();
      final exercise = await _exercise(h.db);
      await _seedHistory(h.db, exercise, [(70, 6), (72.5, 5)]);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await h.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercise);
      final we = _flow(h).draft!.exercises.single.id;
      await _pumpView(tester, h);

      await tester.tap(find.byKey(Key('addSetButton_$we')));
      await tester.pumpAndSettle();

      expect(_field(tester, 'addSetWeightField'), '72.5');
      expect(_field(tester, 'addSetRepsField'), '5');
    });

    testWidgets('歷史查詢失敗 → 這次空白;開記組時重查,下一次就預填上次數字(失敗不快取)', (tester) async {
      late _FlakyFetchRecentRepository repo;
      final h = await _setUp(
        repo: (db) => repo = _FlakyFetchRecentRepository(db, DriftExerciseRepository(db), failuresLeft: 1),
      );
      final exercise = await _exercise(h.db);
      await _seedHistory(h.db, exercise, [(70, 6), (72.5, 5)]);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await h.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercise);
      final we = _flow(h).draft!.exercises.single.id;
      await _pumpView(tester, h);
      expect(repo.calls, 1);

      await tester.tap(find.byKey(Key('addSetButton_$we')));
      await tester.pumpAndSettle();
      expect(_field(tester, 'addSetWeightField'), '');
      expect(repo.calls, 2);
      Navigator.of(tester.element(find.byKey(const Key('addSetWeightField')))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('addSetButton_$we')));
      await tester.pumpAndSettle();
      expect(_field(tester, 'addSetWeightField'), '72.5');
      expect(_field(tester, 'addSetRepsField'), '5');
      // 查成功之後不再重查。
      expect(repo.calls, 2);
    });

    testWidgets('沒有歷史 → 第一組空白', (tester) async {
      final h = await _setUp();
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await h.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(await _exercise(h.db));
      final we = _flow(h).draft!.exercises.single.id;
      await _pumpView(tester, h);

      await tester.tap(find.byKey(Key('addSetButton_$we')));
      await tester.pumpAndSettle();

      expect(_field(tester, 'addSetWeightField'), '');
      expect(_field(tester, 'addSetRepsField'), '');
    });

    testWidgets('存並再記一組 → 寫入兩組、sheet 還開著、組號遞增', (tester) async {
      final h = await _setUp();
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await h.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(await _exercise(h.db));
      final we = _flow(h).draft!.exercises.single.id;
      await _pumpView(tester, h);

      await tester.tap(find.byKey(Key('addSetButton_$we')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('addSetWeightField')), '50');
      await tester.enterText(find.byKey(const Key('addSetRepsField')), '10');
      await tester.pump();
      await tester.tap(find.byKey(const Key('addSetSaveAndContinueButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addSetSaveAndContinueButton')));
      await tester.pumpAndSettle();

      expect(find.text('第 3 組'), findsOneWidget);
      final sets = _flow(h).draft!.exercises.single.sets;
      expect(sets.map((s) => (s.setNumber, s.weight, s.reps)), [(1, 50.0, 10), (2, 50.0, 10)]);

      await tester.tap(find.byKey(const Key('addSetSaveButton')));
      await tester.pumpAndSettle();
      expect(_flow(h).draft!.exercises.single.sets, hasLength(3));
      expect(find.byKey(const Key('addSetSaveButton')), findsNothing);
      _stopRest(h);
    });
  });

  testWidgets('新增動作:選完動作自動開記組 sheet,存完該動作有 1 組', (tester) async {
    final h = await _setUp();
    final exercise = await _exercise(h.db);
    await h.container.read(workoutControllerProvider.future);
    await h.container.read(workoutControllerProvider.notifier).startFreeWorkout();
    await _pumpView(tester, h);

    await tester.tap(find.byKey(const Key('addExerciseButtonEmptyState')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exercise_picker_search_field')), exercise.name);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('exercise_row_${exercise.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('addSetWeightField')), findsOneWidget);
    expect(find.text(exercise.name), findsWidgets);
    await tester.enterText(find.byKey(const Key('addSetWeightField')), '30');
    await tester.enterText(find.byKey(const Key('addSetRepsField')), '12');
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSetSaveButton')));
    await tester.pumpAndSettle();

    expect(_flow(h).draft!.exercises.single.sets, hasLength(1));
    _stopRest(h);
  });
}
