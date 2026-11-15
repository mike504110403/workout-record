// 進行中訓練頁 ux2 改版的 widget 測試(真 in-memory DB + 真 repositories +
// 真 WorkoutInProgressView / ExercisePickerSheet,只 override DB/prefs):
// 1. 休息計時列/結束提示在底部,緊貼「記下一組」主鈕上方;
// 2. 動作卡標題下「上次成績」一行(重量最大組 + 組數,自重改次數,依單位換算);
// 3. 加動作多選:依勾選順序加入、單選才自動開記組、失敗即停。
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
import 'package:workout_record/features/workout/rest_timer_bar.dart';
import 'package:workout_record/features/workout/rest_timer_controller.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/workout/workout_in_progress_view.dart';

import '../../data/test_helpers.dart';

typedef _Harness = ({AppDatabase db, ProviderContainer container});

/// 第 [failAt] 次(1 起算)呼叫 addExercise 時丟錯,其餘走真實作。
class _FailingAddController extends WorkoutController {
  static int failAt = 0;
  var _calls = 0;

  @override
  Future<void> addExercise(Exercise exercise) async {
    _calls += 1;
    if (_calls == failAt) throw Exception('模擬寫入失敗');
    return super.addExercise(exercise);
  }
}

Future<_Harness> _setUp({WeightUnit? unit, bool failingAdd = false}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      restTimerFinishedFeedbackProvider.overrideWithValue(() {}),
      if (unit != null) weightUnitProvider.overrideWithValue(unit),
      if (failingAdd) workoutControllerProvider.overrideWith(_FailingAddController.new),
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

Future<List<Exercise>> _exercises(AppDatabase db) => DriftExerciseRepository(db).fetchSystemExercises();

WorkoutFlowState _flow(_Harness h) => h.container.read(workoutControllerProvider).value!;

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

/// 開始空白訓練並加入 [exercise],回傳該動作的 workoutExerciseId。
Future<String> _startWith(_Harness h, Exercise exercise) async {
  final notifier = h.container.read(workoutControllerProvider.notifier);
  await h.container.read(workoutControllerProvider.future);
  await notifier.startFreeWorkout();
  await notifier.addExercise(exercise);
  return _flow(h).draft!.exercises.single.id;
}

Future<void> _checkExercise(WidgetTester tester, Exercise e) async {
  await tester.enterText(find.byKey(const Key('exercise_picker_search_field')), e.name);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('exercise_checkbox_${e.id}')));
  await tester.pumpAndSettle();
}

void main() {
  group('休息計時列在底部主鈕上方', () {
    testWidgets('倒數列:在列表下方、主鈕上方;不顯示時不佔高度', (tester) async {
      final h = await _setUp();
      final exercises = await _exercises(h.db);
      final we = await _startWith(h, exercises.first);
      await _pumpView(tester, h);

      expect(tester.getSize(find.byType(RestTimerBar)).height, 0, reason: '不顯示不佔高度');

      h.container.read(restTimerControllerProvider.notifier).start(seconds: 60, exerciseName: '深蹲');
      await tester.pump();

      final bar = find.byKey(const Key('restTimerBar'));
      expect(bar, findsOneWidget);
      final cardTop = tester.getTopLeft(find.byKey(Key('exerciseCard_$we'))).dy;
      final mainButton = find.byKey(const Key('recordNextSetButton'));
      expect(tester.getBottomLeft(bar).dy, lessThanOrEqualTo(tester.getTopLeft(mainButton).dy));
      expect(tester.getTopLeft(bar).dy, greaterThan(cardTop), reason: '在底部而非列表上方');
      // 緊貼主鈕:中間只隔主鈕區自己的內距(<= 24),不是掛在畫面中段。
      expect(tester.getTopLeft(mainButton).dy - tester.getBottomLeft(bar).dy, lessThan(24));

      h.container.read(restTimerControllerProvider.notifier).skip();
      await tester.pump();
    });

    testWidgets('結束提示同樣在主鈕上方、列表下方', (tester) async {
      final h = await _setUp();
      final we = await _startWith(h, (await _exercises(h.db)).first);
      await _pumpView(tester, h);

      h.container.read(restTimerControllerProvider.notifier).start(seconds: 1, exerciseName: '深蹲');
      await tester.pump(const Duration(seconds: 1));

      final banner = find.byKey(const Key('restFinishedBanner'));
      expect(banner, findsOneWidget);
      expect(
        tester.getBottomLeft(banner).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byKey(const Key('recordNextSetButton'))).dy),
      );
      expect(tester.getTopLeft(banner).dy, greaterThan(tester.getTopLeft(find.byKey(Key('exerciseCard_$we'))).dy));

      await tester.pump(const Duration(seconds: 5)); // 提示 4 秒後自動消失,不留 pending timer
    });
  });

  group('動作卡上次成績', () {
    testWidgets('有歷史:重量最大組(同重量取次數多者)+ 組數;不論有無計畫組', (tester) async {
      final h = await _setUp();
      final ex = (await _exercises(h.db)).first;
      await _seedHistory(h.db, ex, [(50, 10), (60, 6), (60, 8)]);
      final we = await _startWith(h, ex);
      await _pumpView(tester, h);

      final text = find.byKey(Key('lastPerformance_$we'));
      expect(text, findsOneWidget);
      expect(tester.widget<Text>(text).data, '上次 60 kg × 8・3 組');
      // 在動作名下方、組列之前。
      expect(tester.getTopLeft(text).dy, greaterThan(tester.getTopLeft(find.text(ex.name)).dy));
    });

    testWidgets('lb 單位:重量換算顯示(格式同組列)', (tester) async {
      final h = await _setUp(unit: WeightUnit.lb);
      final ex = (await _exercises(h.db)).first;
      await _seedHistory(h.db, ex, [(20, 5), (20, 5), (10, 8)]);
      final we = await _startWith(h, ex);
      await _pumpView(tester, h);

      expect(tester.widget<Text>(find.byKey(Key('lastPerformance_$we'))).data, '上次 44.09 lb × 5・3 組');
    });

    testWidgets('自重(最大重量 0):改顯示最大次數', (tester) async {
      final h = await _setUp();
      final ex = (await _exercises(h.db)).first;
      await _seedHistory(h.db, ex, [(0, 10), (0, 12), (0, 8)]);
      final we = await _startWith(h, ex);
      await _pumpView(tester, h);

      expect(tester.widget<Text>(find.byKey(Key('lastPerformance_$we'))).data, '上次 12 下・3 組');
    });

    testWidgets('沒有歷史:不顯示該行', (tester) async {
      final h = await _setUp();
      final we = await _startWith(h, (await _exercises(h.db)).first);
      await _pumpView(tester, h);

      expect(find.byKey(Key('lastPerformance_$we')), findsNothing);
    });
  });

  group('加動作多選', () {
    testWidgets('多選 2 個:依勾選順序加入草稿,不自動開記組視窗', (tester) async {
      final h = await _setUp();
      final all = await _exercises(h.db);
      final first = all[7], second = all[2];
      await _startWith(h, all.first);
      await _pumpView(tester, h);

      await tester.tap(find.byKey(const Key('addExerciseButton')));
      await tester.pumpAndSettle();
      await _checkExercise(tester, first);
      await _checkExercise(tester, second);
      await tester.tap(find.byKey(const Key('exercise_picker_confirm_button')));
      await tester.pumpAndSettle();

      expect([for (final e in _flow(h).draft!.exercises) e.exerciseId], [all.first.id, first.id, second.id]);
      expect(find.byKey(const Key('addSetSetNumberText')), findsNothing, reason: '多個不自動開記組');
    });

    testWidgets('多選 1 個:維持加完自動開記組視窗', (tester) async {
      final h = await _setUp();
      final all = await _exercises(h.db);
      await _startWith(h, all.first);
      await _pumpView(tester, h);

      await tester.tap(find.byKey(const Key('addExerciseButton')));
      await tester.pumpAndSettle();
      await _checkExercise(tester, all[3]);
      await tester.tap(find.byKey(const Key('exercise_picker_confirm_button')));
      await tester.pumpAndSettle();

      expect(_flow(h).draft!.exercises.last.exerciseId, all[3].id);
      expect(find.byKey(const Key('addSetSetNumberText')), findsWidgets);
    });

    testWidgets('第二個 addExercise 失敗:SnackBar 提示,只加了第一個', (tester) async {
      _FailingAddController.failAt = 0;
      final h = await _setUp(failingAdd: true);
      final all = await _exercises(h.db);
      await _startWith(h, all.first); // 第 1 次呼叫(起始動作)
      _FailingAddController.failAt = 3; // 之後選的兩個:第 2 個(總第 3 次)失敗
      addTearDown(() => _FailingAddController.failAt = 0);
      await _pumpView(tester, h);

      await tester.tap(find.byKey(const Key('addExerciseButton')));
      await tester.pumpAndSettle();
      await _checkExercise(tester, all[7]);
      await _checkExercise(tester, all[2]);
      await tester.tap(find.byKey(const Key('exercise_picker_confirm_button')));
      await tester.pumpAndSettle();

      expect([for (final e in _flow(h).draft!.exercises) e.exerciseId], [all.first.id, all[7].id]);
      expect(find.textContaining('新增動作失敗:'), findsOneWidget);
      expect(find.byKey(const Key('addSetSetNumberText')), findsNothing);
    });
  });
}
