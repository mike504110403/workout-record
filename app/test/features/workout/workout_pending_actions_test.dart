// 進行中訓練頁的「延遲刪除＋復原」「延遲完成＋復原」「底部主按鈕」「0 kg 防誤記」
// 「完成狀態辨識」(2026-11-15 inprogress-ux)。真 in-memory DB + 真 repositories,
// 只在 repository 外包一層 spy 記錄 deleteSet/removeExercise/completeWorkout 呼叫、
// 並可注入失敗。測試結尾都把時間推過計時長度,不留 pending Timer。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide Workout, WorkoutExercise, WorkoutSet, Exercise;
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';
import 'package:workout_record/features/workout/planned_sets_store.dart';
import 'package:workout_record/features/workout/rest_timer_controller.dart';
import 'package:workout_record/features/workout/templates/applied_template.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/workout/workout_in_progress_view.dart';
import 'package:workout_record/features/workout/workout_pending_actions.dart';

import '../../data/test_helpers.dart';

/// 記錄並可注入失敗的 repository。
class _SpyRepository extends DriftWorkoutRepository {
  _SpyRepository(super.db, super.exerciseRepository);

  final deletedSets = <String>[];
  final removedExercises = <String>[];
  var completeCalls = 0;
  var failDeleteSet = false;
  var failRemoveExercise = false;
  var failComplete = false;

  /// 非 null 時 discardDraft(放棄寫入)要等它完成,模擬寫入期間時間流逝。
  Completer<void>? discardGate;

  @override
  Future<void> discardDraft(String workoutId) async {
    await discardGate?.future;
    return super.discardDraft(workoutId);
  }

  @override
  Future<void> deleteSet(String setId, {required String workoutExerciseId}) async {
    if (failDeleteSet) throw Exception('模擬刪組失敗');
    deletedSets.add(setId);
    return super.deleteSet(setId, workoutExerciseId: workoutExerciseId);
  }

  @override
  Future<void> removeExercise(String workoutExerciseId, {required String workoutId}) async {
    if (failRemoveExercise) throw Exception('模擬刪動作失敗');
    removedExercises.add(workoutExerciseId);
    return super.removeExercise(workoutExerciseId, workoutId: workoutId);
  }

  @override
  Future<Workout> completeWorkout(String workoutId, {DateTime? endedAt}) async {
    completeCalls += 1;
    if (failComplete) throw Exception('模擬完成寫入失敗');
    return super.completeWorkout(workoutId, endedAt: endedAt);
  }
}

typedef _Harness = ({AppDatabase db, ProviderContainer container, _SpyRepository repo});

Future<_Harness> _setUp({WeightUnit? unit}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);
  final repo = _SpyRepository(db, DriftExerciseRepository(db));
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      workoutRepositoryProvider.overrideWithValue(repo),
      if (unit != null) weightUnitProvider.overrideWithValue(unit),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (db: db, container: container, repo: repo);
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
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

/// 讓時間走 [d],再把非同步寫入跑完。
Future<void> _elapse(WidgetTester tester, Duration d) async {
  await tester.pump(d);
  await tester.pumpAndSettle();
}

const _delete = Duration(seconds: 5);
const _complete = Duration(seconds: 4);

WorkoutFlowState _flow(_Harness h) => h.container.read(workoutControllerProvider).value!;
WorkoutController _ctl(_Harness h) => h.container.read(workoutControllerProvider.notifier);
void _stopRest(_Harness h) => h.container.read(restTimerControllerProvider.notifier).skip();

Future<List<Exercise>> _exercises(_Harness h) => DriftExerciseRepository(h.db).fetchSystemExercises();

/// 空白訓練 + [count] 個動作,第 i 個動作記 [setsPer] 組(重量 50+i、次數 5)。
Future<void> _freeWorkout(_Harness h, {int count = 1, int setsPer = 0}) async {
  await h.container.read(workoutControllerProvider.future);
  await _ctl(h).startFreeWorkout();
  final ex = await _exercises(h);
  for (var i = 0; i < count; i++) {
    await _ctl(h).addExercise(ex[i]);
  }
  final draft = _flow(h).draft!;
  for (final e in draft.exercises) {
    for (var j = 0; j < setsPer; j++) {
      await _ctl(h).addSet(workoutExerciseId: e.id, weight: 50, reps: 5);
    }
  }
}

/// 過去一場已完成訓練當「上次紀錄」:每個動作 [sets] = (重量, 次數)。
Future<void> _seedHistory(_Harness h, Map<Exercise, List<(double, int)>> data) async {
  final at = DateTime(2026, 11, 1, 9);
  var n = 0;
  await DriftWorkoutRepository(h.db, DriftExerciseRepository(h.db)).create(
    Workout(
      id: 'past',
      userId: testUserId,
      startedAt: at,
      endedAt: at.add(const Duration(minutes: 40)),
      createdAt: at,
      updatedAt: at,
      exercises: [
        for (final entry in data.entries)
          WorkoutExercise(
            id: 'past-we${n++}',
            workoutId: 'past',
            exerciseId: entry.key.id,
            exerciseName: entry.key.name,
            orderIndex: n,
            createdAt: at,
            updatedAt: at,
            sets: [
              for (var i = 0; i < entry.value.length; i++)
                WorkoutSet(
                  id: 'past-s$n-$i',
                  workoutExerciseId: 'past-we${n - 1}',
                  setNumber: i + 1,
                  weight: entry.value[i].$1,
                  reps: entry.value[i].$2,
                  createdAt: at,
                  updatedAt: at,
                ),
            ],
          ),
      ],
    ),
  );
}

/// 模板開始:每個動作 [plannedCount] 組(重量 0、10 下)。
Future<void> _fromTemplate(_Harness h, List<Exercise> exercises, {int plannedCount = 2}) async {
  await h.container.read(workoutControllerProvider.future);
  await _ctl(h).startFromTemplate(
    AppliedTemplate(
      templateId: 't',
      templateName: '模板',
      exercises: [
        for (final e in exercises)
          AppliedTemplateExercise(
            exerciseId: e.id,
            exerciseName: e.name,
            sets: [for (var i = 0; i < plannedCount; i++) const AppliedTemplateSet(weight: 0, reps: 10)],
          ),
      ],
    ),
  );
}

Future<void> _swipeSet(WidgetTester tester, String setId) async {
  await tester.drag(find.byKey(Key('setRowTap_$setId')), const Offset(-500, 0));
  await tester.pumpAndSettle();
}

Future<void> _tapUndo(WidgetTester tester) async {
  await tester.tap(find.text('復原'));
  await tester.pumpAndSettle();
}

/// 取得目前 SnackBar「復原」鈕的 callback(模擬無障礙模式 SnackBar 不消失、
/// 計時觸發之後仍被按到)。
VoidCallback _undoCallback(WidgetTester tester) => tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;

bool _enabled(WidgetTester tester, Finder f) {
  final w = tester.widget(f);
  if (w is ButtonStyleButton) return w.onPressed != null;
  if (w is IconButton) return w.onPressed != null;
  if (w is PopupMenuButton) return w.enabled;
  throw StateError('unsupported ${w.runtimeType}');
}

void main() {
  group('延遲刪組', () {
    testWidgets('左滑刪中間那組 → 立即隱藏+「已刪除第 2 組」+復原 → 復原後原位顯示、DB 從未被動過', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 3);
      final sets = _flow(h).draft!.exercises.single.sets;
      await _pump(tester, h);

      await _swipeSet(tester, sets[1].id);
      expect(find.byKey(Key('setRow_${sets[1].id}')), findsNothing);
      expect(find.text('已刪除第 2 組'), findsOneWidget);
      expect(find.text('復原'), findsOneWidget);
      // 後面那組的組號照「刪完重編」顯示(列上第 2 列顯示 2)。
      expect(h.repo.deletedSets, isEmpty);

      await _tapUndo(tester);
      expect(find.byKey(Key('setRow_${sets[1].id}')), findsOneWidget);
      // 原位:第 1、2、3 列依序是 sets[0..2]。
      final ys = [for (final s in sets) tester.getTopLeft(find.byKey(Key('setRow_${s.id}'))).dy];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);
      await _elapse(tester, _delete);
      expect(h.repo.deletedSets, isEmpty);
      expect(_flow(h).draft!.exercises.single.sets, hasLength(3));
      _stopRest(h);
    });

    testWidgets('不復原 → 5 秒後 repository 收到 deleteSet,組數重編為 1..2', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 3);
      final sets = _flow(h).draft!.exercises.single.sets;
      await _pump(tester, h);

      await _swipeSet(tester, sets[1].id);
      await tester.pump(const Duration(seconds: 4));
      expect(h.repo.deletedSets, isEmpty);
      await _elapse(tester, const Duration(seconds: 1));

      expect(h.repo.deletedSets, [sets[1].id]);
      final after = _flow(h).draft!.exercises.single.sets;
      expect(after.map((s) => s.id), [sets[0].id, sets[2].id]);
      expect(after.map((s) => s.setNumber), [1, 2]);
      expect(find.byKey(Key('setRow_${sets[1].id}')), findsNothing);
    });

    testWidgets('待刪期間:統計與記組 sheet 的組號都排除待刪組', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 2); // 2 × (50×5)
      final sets = _flow(h).draft!.exercises.single.sets;
      final we = _flow(h).draft!.exercises.single.id;
      await _pump(tester, h);
      expect(find.descendant(of: find.byKey(const Key('workoutTotalSetsValue')), matching: find.text('2 組')), findsOneWidget);

      await _swipeSet(tester, sets[0].id);
      expect(find.descendant(of: find.byKey(const Key('workoutTotalSetsValue')), matching: find.text('1 組')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('workoutTotalVolumeValue')), matching: find.text('250 kg')), findsOneWidget);

      await tester.tap(find.byKey(Key('addSetButton_$we')));
      await tester.pumpAndSettle();
      expect(find.text('第 2 組'), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('addSetWeightField')))).pop();
      await tester.pumpAndSettle();
      await _elapse(tester, _delete);
    });

    testWidgets('連續刪兩組:各自計時,SnackBar 只顯示最新一筆,被擠掉的照樣 5 秒後真刪', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 3);
      final sets = _flow(h).draft!.exercises.single.sets;
      await _pump(tester, h);

      await _swipeSet(tester, sets[0].id);
      await tester.pump(const Duration(seconds: 2));
      await _swipeSet(tester, sets[2].id);
      expect(find.text('復原'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3)); // 第一筆到期
      await tester.pumpAndSettle();
      expect(h.repo.deletedSets, [sets[0].id]);
      await _elapse(tester, const Duration(seconds: 2)); // 第二筆到期
      expect(h.repo.deletedSets, [sets[0].id, sets[2].id]);
      expect(_flow(h).draft!.exercises.single.sets.map((s) => s.id), [sets[1].id]);
    });

    testWidgets('計時觸發之後按「復原」(SnackBar 沒消失的無障礙情境)→ no-op,不撤回', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 2);
      final sets = _flow(h).draft!.exercises.single.sets;
      await _pump(tester, h);

      await _swipeSet(tester, sets[0].id);
      final undo = _undoCallback(tester);
      await _elapse(tester, _delete);
      undo();
      await tester.pumpAndSettle();

      expect(h.repo.deletedSets, [sets[0].id]);
      expect(find.byKey(Key('setRow_${sets[0].id}')), findsNothing);
      expect(_flow(h).draft!.exercises.single.sets, hasLength(1));
    });

    testWidgets('到期真刪失敗 → 該組恢復顯示 + 錯誤提示', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 2);
      final sets = _flow(h).draft!.exercises.single.sets;
      h.repo.failDeleteSet = true;
      await _pump(tester, h);

      await _swipeSet(tester, sets[0].id);
      expect(find.byKey(Key('setRow_${sets[0].id}')), findsNothing);
      await _elapse(tester, _delete);

      expect(tester.takeException(), isNull);
      expect(find.byKey(Key('setRow_${sets[0].id}')), findsOneWidget);
      expect(find.textContaining('刪除組數失敗'), findsOneWidget);
      expect(_flow(h).draft!.exercises.single.sets, hasLength(2));
      await _elapse(tester, const Duration(seconds: 5));
    });
  });

  group('延遲刪動作', () {
    Future<(_Harness, List<String>)> three(WidgetTester tester) async {
      final h = await _setUp();
      await _freeWorkout(h, count: 3, setsPer: 1);
      final ids = [for (final e in _flow(h).draft!.exercises) e.id];
      await _pump(tester, h);
      return (h, ids);
    }

    Future<void> deleteMiddle(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(Key('exerciseMoreButton_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('deleteExerciseButton_$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('刪中間動作 → 卡片立即隱藏+「已刪除 <名稱>」;復原後順序不變、DB 沒被動過', (tester) async {
      final (h, ids) = await three(tester);
      final name = _flow(h).draft!.exercises[1].exerciseName!;
      await deleteMiddle(tester, ids[1]);

      expect(find.byKey(Key('exerciseCard_${ids[1]}')), findsNothing);
      expect(find.text('已刪除 $name'), findsOneWidget);
      expect(h.repo.removedExercises, isEmpty);

      await _tapUndo(tester);
      final ys = [for (final id in ids) tester.getTopLeft(find.byKey(Key('exerciseCard_$id'))).dy];
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);
      await _elapse(tester, _delete);
      expect(h.repo.removedExercises, isEmpty);
      expect(_flow(h).draft!.exercises.map((e) => e.id), ids);
      _stopRest(h);
    });

    testWidgets('不復原 → 5 秒後 removeExercise,剩 2 個、順序保留', (tester) async {
      final (h, ids) = await three(tester);
      await deleteMiddle(tester, ids[1]);
      await _elapse(tester, _delete);

      expect(h.repo.removedExercises, [ids[1]]);
      expect(_flow(h).draft!.exercises.map((e) => e.id), [ids[0], ids[2]]);
    });

    testWidgets('到期刪動作失敗 → 卡片恢復顯示 + 錯誤提示', (tester) async {
      final (h, ids) = await three(tester);
      h.repo.failRemoveExercise = true;
      await deleteMiddle(tester, ids[1]);
      await _elapse(tester, _delete);

      expect(tester.takeException(), isNull);
      expect(find.byKey(Key('exerciseCard_${ids[1]}')), findsOneWidget);
      expect(find.textContaining('刪除動作失敗'), findsOneWidget);
      await _elapse(tester, const Duration(seconds: 5));
    });

    testWidgets('全部動作都待刪 → 空狀態、主鈕變「新增動作」', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, count: 1, setsPer: 1);
      final id = _flow(h).draft!.exercises.single.id;
      await _pump(tester, h);
      await deleteMiddle(tester, id);

      expect(find.byKey(Key('exerciseCard_$id')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('recordNextSetButton')), matching: find.text('新增動作')), findsOneWidget);
      await _elapse(tester, _delete);
    });
  });

  group('延遲完成', () {
    testWidgets('點完成 → 4 秒內復原 → 未完成、未出摘要、可再按', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 1);
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      expect(find.text('即將完成訓練'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _tapUndo(tester);
      await _elapse(tester, const Duration(seconds: 5));

      expect(h.repo.completeCalls, 0);
      expect(find.byKey(const Key('summaryTitleText')), findsNothing);
      expect(_flow(h).draft, isNotNull);
      expect(_enabled(tester, find.byKey(const Key('completeWorkoutButton'))), isTrue);
    });

    testWidgets('不復原 → 4 秒後完成並出摘要', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 1);
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(h.repo.completeCalls, 0);
      await _elapse(tester, const Duration(seconds: 1));

      expect(h.repo.completeCalls, 1);
      expect(find.byKey(const Key('summaryTitleText')), findsOneWidget);
      expect(_flow(h).draft, isNull);
    });

    testWidgets('倒數期間:完成鈕、主鈕、卡片操作、⋯ 選單、新增動作全部停用;收起鈕不受影響', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, count: 2, setsPer: 1);
      final e = _flow(h).draft!.exercises;
      await _pump(tester, h);
      expect(_enabled(tester, find.byKey(const Key('recordNextSetButton'))), isTrue);

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();

      expect(_enabled(tester, find.byKey(const Key('completeWorkoutButton'))), isFalse);
      expect(_enabled(tester, find.byKey(const Key('recordNextSetButton'))), isFalse);
      expect(_enabled(tester, find.byKey(const Key('workoutMoreMenuButton'))), isFalse);
      expect(_enabled(tester, find.byKey(Key('exerciseMoreButton_${e[0].id}'))), isFalse);
      expect(tester.widget<TextButton>(find.byKey(Key('addSetButton_${e[0].id}'))).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('addExerciseButton'))).onPressed, isNull);
      final setId = e[0].sets.single.id;
      expect(tester.widget<InkWell>(find.byKey(Key('setRowTap_$setId'))).onTap, isNull);
      expect(tester.widget<Dismissible>(find.byKey(ValueKey('dismissSet_$setId'))).direction, DismissDirection.none);
      expect(tester.widget<IconButton>(find.byKey(const Key('workoutMinimizeButton'))).onPressed, isNotNull);

      await _tapUndo(tester);
      expect(_enabled(tester, find.byKey(const Key('completeWorkoutButton'))), isTrue);
      await _elapse(tester, _complete);
    });

    testWidgets('計時觸發之後按「復原」→ no-op,不撤回', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 1);
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      final undo = _undoCallback(tester);
      await _elapse(tester, _complete);
      undo();
      await tester.pumpAndSettle();

      expect(h.repo.completeCalls, 1);
      expect(find.byKey(const Key('summaryTitleText')), findsOneWidget);
    });

    testWidgets('完成寫入失敗 → 「完成訓練失敗」提示、草稿保留、解除等待', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 1);
      h.repo.failComplete = true;
      await _pump(tester, h);

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      await _elapse(tester, _complete);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('完成訓練失敗'), findsOneWidget);
      expect(_flow(h).draft, isNotNull);
      expect(_enabled(tester, find.byKey(const Key('completeWorkoutButton'))), isTrue);
      expect(h.container.read(pendingActionsProvider).completePhase, CompletePhase.idle);
      await _elapse(tester, const Duration(seconds: 5));
    });

    testWidgets('待刪期間按完成:4 秒內不真刪;到時先 flush 真刪再完成', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 2);
      final sets = _flow(h).draft!.exercises.single.sets;
      await _pump(tester, h);
      await _swipeSet(tester, sets[0].id);
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      // 倒數期間待刪計時暫停:原本的 5 秒計時會在按完成後不到 3 秒到期,這裡看 3 秒時仍沒真刪。
      await tester.pump(const Duration(seconds: 3));
      expect(h.repo.deletedSets, isEmpty);
      await _elapse(tester, const Duration(seconds: 1));

      expect(h.repo.deletedSets, [sets[0].id]);
      expect(h.repo.completeCalls, 1);
      expect(find.byKey(const Key('summaryTitleText')), findsOneWidget);
    });

    testWidgets('待刪後只剩 0 組時按完成 → 顯示無法完成、不進入等待、不呼叫 completeWorkout', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 1);
      final set = _flow(h).draft!.exercises.single.sets.single;
      await _pump(tester, h);
      await _swipeSet(tester, set.id);

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();

      expect(find.text('沒有任何組，無法完成'), findsOneWidget);
      expect(h.container.read(pendingActionsProvider).completePhase, CompletePhase.idle);
      await _elapse(tester, const Duration(seconds: 6));
      expect(h.repo.completeCalls, 0);
      expect(find.byKey(const Key('summaryTitleText')), findsNothing);
    });

    testWidgets('等待中按復原(撤回完成)→ 待刪項目重新計 5 秒後真刪', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 2);
      final sets = _flow(h).draft!.exercises.single.sets;
      await _pump(tester, h);
      await _swipeSet(tester, sets[0].id);

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      await _tapUndo(tester);
      expect(h.repo.deletedSets, isEmpty);
      expect(find.byKey(Key('setRow_${sets[0].id}')), findsNothing); // 仍隱藏

      await tester.pump(const Duration(seconds: 4));
      expect(h.repo.deletedSets, isEmpty);
      await _elapse(tester, const Duration(seconds: 1));
      expect(h.repo.deletedSets, [sets[0].id]);
      expect(h.repo.completeCalls, 0);
    });

    testWidgets('完成倒數中按到舊的刪除「復原」→ no-op(項目仍待刪,完成時照 flush)', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 2);
      final sets = _flow(h).draft!.exercises.single.sets;
      await _pump(tester, h);
      await _swipeSet(tester, sets[0].id);
      final staleUndo = _undoCallback(tester);

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      staleUndo();
      await tester.pumpAndSettle();
      expect(find.byKey(Key('setRow_${sets[0].id}')), findsNothing);

      await _elapse(tester, _complete);
      expect(h.repo.deletedSets, [sets[0].id]);
      expect(h.repo.completeCalls, 1);
    });

    testWidgets('完成倒數中不接受新的待刪:scheduleDelete* 回 false、不隱藏', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 2);
      final e = _flow(h).draft!.exercises.single;
      await _pump(tester, h);
      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();

      final scheduled = h.container
          .read(pendingActionsProvider.notifier)
          .scheduleDeleteSet(
            setId: e.sets[0].id,
            workoutExerciseId: e.id,
            message: 'x',
            run: () async => fail('不該被執行'),
            messenger: ScaffoldMessenger.of(tester.element(find.byType(Scaffold))),
          );
      await tester.pumpAndSettle();

      expect(scheduled, isFalse);
      expect(h.container.read(pendingActionsProvider).deletedSetIds, isEmpty);
      expect(find.byKey(Key('setRow_${e.sets[0].id}')), findsOneWidget);
      await _tapUndo(tester);
      await _elapse(tester, _complete);
    });

    testWidgets('flush 時所屬動作也待刪的組直接丟棄(只刪動作,不刪組)', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, count: 2, setsPer: 2);
      final e = _flow(h).draft!.exercises;
      await _pump(tester, h);
      await _swipeSet(tester, e[0].sets[0].id);
      await tester.tap(find.byKey(Key('exerciseMoreButton_${e[0].id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('deleteExerciseButton_${e[0].id}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      await _elapse(tester, _complete);

      expect(h.repo.deletedSets, isEmpty);
      expect(h.repo.removedExercises, [e[0].id]);
      expect(h.repo.completeCalls, 1);
    });

    testWidgets('flush 失敗 → 中止完成、該項恢復顯示、錯誤提示、解除等待', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 2);
      final sets = _flow(h).draft!.exercises.single.sets;
      h.repo.failDeleteSet = true;
      await _pump(tester, h);
      await _swipeSet(tester, sets[0].id);

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      await _elapse(tester, _complete);

      expect(tester.takeException(), isNull);
      expect(h.repo.completeCalls, 0);
      expect(find.byKey(Key('setRow_${sets[0].id}')), findsOneWidget);
      expect(find.textContaining('刪除組數失敗'), findsOneWidget);
      expect(_enabled(tester, find.byKey(const Key('completeWorkoutButton'))), isTrue);
      await _elapse(tester, const Duration(seconds: 5));
    });

    testWidgets('放棄訓練 → 待刪狀態清空,之後不會再對已丟棄的草稿真刪', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 2);
      final sets = _flow(h).draft!.exercises.single.sets;
      await _pump(tester, h);
      await _swipeSet(tester, sets[0].id);

      await tester.tap(find.byKey(const Key('workoutMoreMenuButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('abandonWorkoutButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('abandonWorkoutConfirmButton')));
      await tester.pumpAndSettle();
      await _elapse(tester, const Duration(seconds: 6));

      expect(h.repo.deletedSets, isEmpty);
      expect(h.container.read(pendingActionsProvider).deletedSetIds, isEmpty);
      expect(h.container.read(pendingActionsProvider).draftId, isNull);
    });
  });

  group('放棄與待刪計時', () {
    Future<(_Harness, String)> withPendingDelete(WidgetTester tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 2);
      final sets = _flow(h).draft!.exercises.single.sets;
      await _pump(tester, h);
      await _swipeSet(tester, sets[0].id);
      await tester.tap(find.byKey(const Key('workoutMoreMenuButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('abandonWorkoutButton')));
      await tester.pumpAndSettle();
      return (h, sets[0].id);
    }

    testWidgets('確認框開著時待刪計時暫停;取消 → 恢復計時(重新計 5 秒)後照常真刪', (tester) async {
      final (h, setId) = await withPendingDelete(tester);
      await tester.pump(const Duration(seconds: 7));
      expect(h.repo.deletedSets, isEmpty);

      await tester.tap(find.byKey(const Key('abandonWorkoutCancelButton')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      expect(h.repo.deletedSets, isEmpty);
      await _elapse(tester, const Duration(seconds: 1));
      expect(h.repo.deletedSets, [setId]);
    });

    testWidgets('放棄寫入期間待刪計時不會到期:不跳「刪除組數失敗」、不呼叫 deleteSet;成功後清空', (tester) async {
      final (h, setId) = await withPendingDelete(tester);
      h.repo.discardGate = Completer<void>();

      await tester.tap(find.byKey(const Key('abandonWorkoutConfirmButton')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 7)); // 原本 5 秒計時早已到期
      expect(h.repo.deletedSets, isEmpty);
      expect(find.textContaining('刪除組數失敗'), findsNothing);

      h.repo.discardGate!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('刪除組數失敗'), findsNothing);
      await _elapse(tester, const Duration(seconds: 6));
      expect(h.repo.deletedSets, isEmpty);
      expect(find.textContaining('刪除組數失敗'), findsNothing);
      expect(_flow(h).draft, isNull);
      expect(h.container.read(pendingActionsProvider).deletedSetIds, isEmpty);
      expect(setId, isNotEmpty);
    });

    testWidgets('放棄失敗 → 提示並恢復待刪計時,到期照常真刪', (tester) async {
      final (h, setId) = await withPendingDelete(tester);
      h.repo.discardGate = Completer<void>();

      await tester.tap(find.byKey(const Key('abandonWorkoutConfirmButton')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      expect(h.repo.deletedSets, isEmpty);
      h.repo.discardGate!.completeError(Exception('模擬放棄寫入失敗'));
      await tester.pumpAndSettle();
      expect(find.textContaining('放棄訓練失敗'), findsOneWidget);
      expect(_flow(h).draft, isNotNull);

      await tester.pump(const Duration(seconds: 4));
      expect(h.repo.deletedSets, isEmpty);
      await _elapse(tester, const Duration(seconds: 1));
      expect(h.repo.deletedSets, [setId]);
    });
  });

  group('底部主按鈕', () {
    Finder label(String text) =>
        find.descendant(of: find.byKey(const Key('recordNextSetButton')), matching: find.text(text));

    testWidgets('草稿沒有任何動作 → 「新增動作」,按下開動作選擇器', (tester) async {
      final h = await _setUp();
      await h.container.read(workoutControllerProvider.future);
      await _ctl(h).startFreeWorkout();
      await _pump(tester, h);

      expect(label('新增動作'), findsOneWidget);
      expect(find.byKey(const Key('completeWorkoutButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('recordNextSetButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exercise_picker_search_field')), findsOneWidget);
    });

    testWidgets('沒有計畫組 → 「記下一組・<動作名>」,按下開記組 sheet(預填上一組)', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, setsPer: 1);
      final name = _flow(h).draft!.exercises.single.exerciseName!;
      await _pump(tester, h);

      expect(label('記下一組・$name'), findsOneWidget);
      await tester.tap(find.byKey(const Key('recordNextSetButton')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('addSetWeightField'))).controller!.text, '50');
      expect(find.text('第 2 組'), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('addSetWeightField')))).pop();
      await tester.pumpAndSettle();
    });

    testWidgets('有剩餘計畫組 → 「完成下一組・<動作名> <重量> × <次數>」,按下等同對第一個計畫組打勾;做完自動前進到下一個有計畫組的動作',
        (tester) async {
      final h = await _setUp();
      final ex = await _exercises(h);
      await _seedHistory(h, {
        ex[0]: [(80, 5)],
        ex[1]: [(60, 8)],
      });
      await _fromTemplate(h, [ex[0], ex[1]], plannedCount: 2);
      await _pump(tester, h);

      expect(label('完成下一組・${ex[0].name} 80 kg × 5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('recordNextSetButton')));
      await tester.pumpAndSettle();
      expect(_flow(h).draft!.exercises[0].sets, hasLength(1));
      expect(label('完成下一組・${ex[0].name} 80 kg × 5'), findsOneWidget); // 還有第 2 組計畫組

      await tester.tap(find.byKey(const Key('recordNextSetButton')));
      await tester.pumpAndSettle();
      expect(_flow(h).draft!.exercises[0].sets, hasLength(2));
      // A 的計畫組做完 → 自動前進到 B。
      expect(label('完成下一組・${ex[1].name} 60 kg × 8'), findsOneWidget);

      await tester.tap(find.byKey(const Key('recordNextSetButton')));
      await tester.pumpAndSettle();
      expect(_flow(h).draft!.exercises[1].sets, hasLength(1));
      await tester.tap(find.byKey(const Key('recordNextSetButton')));
      await tester.pumpAndSettle();
      // 全部做完:停在目前動作 B、變回「記下一組」。
      expect(label('記下一組・${ex[1].name}'), findsOneWidget);
      _stopRest(h);
    });

    testWidgets('自由動作(從沒有計畫組)記完組不前進;目前動作跟隨最新記組(同秒也正確)', (tester) async {
      final h = await _setUp();
      await _freeWorkout(h, count: 2);
      final e = _flow(h).draft!.exercises;
      await _pump(tester, h);
      expect(label('記下一組・${e[0].exerciseName}'), findsOneWidget); // 草稿無組=第一個動作

      Future<void> recordVia(String id) async {
        await tester.tap(find.byKey(Key('addSetButton_$id')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('addSetWeightField')), '40');
        await tester.enterText(find.byKey(const Key('addSetRepsField')), '5');
        await tester.pump();
        await tester.tap(find.byKey(const Key('addSetSaveButton')));
        await tester.pumpAndSettle();
      }

      await recordVia(e[1].id);
      expect(label('記下一組・${e[1].exerciseName}'), findsOneWidget);
      await recordVia(e[0].id);
      expect(label('記下一組・${e[0].exerciseName}'), findsOneWidget);
      await recordVia(e[1].id);
      expect(label('記下一組・${e[1].exerciseName}'), findsOneWidget);
      _stopRest(h);
    });

    testWidgets('無上次紀錄的 0 kg 計畫組:主鈕標籤用「—」、依單位顯示 lb,按下開 sheet 不記組', (tester) async {
      final h = await _setUp(unit: WeightUnit.lb);
      final ex = await _exercises(h);
      await _fromTemplate(h, [ex[0]], plannedCount: 1);
      await _pump(tester, h);

      expect(label('完成下一組・${ex[0].name} — lb × 10'), findsOneWidget);
      expect(find.text('— lb × 10'), findsOneWidget);
      await tester.tap(find.byKey(const Key('recordNextSetButton')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('addSetWeightField'))).controller!.text, isEmpty);
      expect(tester.widget<FilledButton>(find.byKey(const Key('addSetSaveButton'))).onPressed, isNull);
      expect(_flow(h).draft!.exercises.single.sets, isEmpty);
      Navigator.of(tester.element(find.byKey(const Key('addSetWeightField')))).pop();
      await tester.pumpAndSettle();
    });
  });

  group('完成狀態辨識', () {
    testWidgets('計畫組是空圈+外框徽章;已記組只由實心 primary 組號徽章+淡底表示(沒有獨立勾圖示)', (tester) async {
      final h = await _setUp();
      final ex = await _exercises(h);
      await _seedHistory(h, {
        ex[0]: [(80, 5)],
      });
      await _fromTemplate(h, [ex[0]], plannedCount: 2);
      await _pump(tester, h);
      final planned = _flow(h).plannedSets.values.single;
      final primary = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;

      Finder solidBadge(Finder within) => find.descendant(
        of: within,
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == primary.primary,
        ),
      );
      Finder outlinedBadge(Finder within) => find.descendant(
        of: within,
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null,
        ),
      );

      final confirm = find.byKey(Key('confirmPlannedSet_${planned.first.id}'));
      final plannedRow = find.byKey(Key('plannedSetRow_${planned.first.id}'));
      expect(find.descendant(of: confirm, matching: find.byIcon(Icons.radio_button_unchecked)), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(outlinedBadge(plannedRow), findsOneWidget);
      expect(solidBadge(plannedRow), findsNothing);

      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final setId = _flow(h).draft!.exercises.single.sets.single.id;
      final row = find.byKey(Key('setRow_$setId'));
      expect(solidBadge(row), findsOneWidget);
      expect(outlinedBadge(row), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      final bg = tester.widget<Material>(find.descendant(of: row, matching: find.byType(Material)).first).color;
      expect(bg, primary.primaryContainer.withValues(alpha: 0.35));
      // 剩下的計畫組仍是空圈。
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      _stopRest(h);
    });
  });

  group('resolveNextSetTarget(同秒 updatedAt 平手、無記憶時的退回規則)', () {
    final t = DateTime(2026, 11, 15, 10);
    WorkoutExercise ex(String id, {List<DateTime> setTimes = const []}) => WorkoutExercise(
      id: id,
      workoutId: 'w',
      exerciseId: 'x$id',
      exerciseName: id,
      createdAt: t,
      updatedAt: t,
      sets: [
        for (var i = 0; i < setTimes.length; i++)
          WorkoutSet(
            id: '$id-$i',
            workoutExerciseId: id,
            setNumber: i + 1,
            weight: 1,
            reps: 1,
            createdAt: setTimes[i],
            updatedAt: setTimes[i],
          ),
      ],
    );

    test('沒有記憶:updatedAt 最新那組所屬動作;平手取清單較後面的', () {
      final target = resolveNextSetTarget(
        visibleExercises: [
          ex('a', setTimes: [t]),
          ex('b', setTimes: [t]),
          ex('c'),
        ],
        plannedSets: const {},
        pending: const PendingActionsState(),
      );
      expect(target.exercise!.id, 'b');
    });

    test('草稿無組=第一個動作;沒有動作=null', () {
      expect(
        resolveNextSetTarget(visibleExercises: [ex('a'), ex('b')], plannedSets: const {}, pending: const PendingActionsState())
            .exercise!
            .id,
        'a',
      );
      expect(
        resolveNextSetTarget(visibleExercises: const [], plannedSets: const {}, pending: const PendingActionsState()).exercise,
        isNull,
      );
    });

    test('自動前進只對「本場曾有計畫組」的動作;含從頭繞回', () {
      final planned = {
        'a': [PlannedSet(id: 'p1', weight: 0, reps: 10)],
      };
      const touchedC = PendingActionsState(lastTouchedExerciseId: 'c', plannedExerciseIds: {'a', 'c'});
      final wrap = resolveNextSetTarget(
        visibleExercises: [ex('a'), ex('b'), ex('c')],
        plannedSets: planned,
        pending: touchedC,
      );
      expect(wrap.exercise!.id, 'a');
      expect(wrap.planned!.id, 'p1');

      const freeC = PendingActionsState(lastTouchedExerciseId: 'c', plannedExerciseIds: {'a'});
      final stay = resolveNextSetTarget(
        visibleExercises: [ex('a'), ex('b'), ex('c')],
        plannedSets: planned,
        pending: freeC,
      );
      expect(stay.exercise!.id, 'c');
      expect(stay.planned, isNull);
    });
  });
}
