// 進行中訓練畫面的 widget 關鍵互動測試(對照 brief seam 規格:「widget 關鍵
// 互動(記組帶入、統計更新、放棄確認兩分支)」)。workout_flow_e2e_test.dart
// 已經覆蓋「選動作→記組→完成→summary」這條主線,但沒有直接斷言畫面上的
// 即時統計列(workoutTotalVolumeValue 等 key)是否隨著記組更新,也沒有碰過
// 放棄按鈕——這份測試補上這兩塊,真 in-memory DB + 真 repositories,只
// override DB/prefs(同 workout_controller_test.dart 的 seam 規格)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, Exercise;
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/workout/workout_in_progress_view.dart';

import '../../data/test_helpers.dart';

typedef _Harness = ({AppDatabase db, ProviderContainer container});

Future<_Harness> _setUpHarness() async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (db: db, container: container);
}

Future<Exercise> _firstSystemExercise(AppDatabase db) async {
  final exercises = await ExerciseRepository(db).fetchSystemExercises();
  return exercises.first;
}

Future<void> _pumpView(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: Scaffold(body: WorkoutInProgressView())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('即時統計列', () {
    testWidgets('新增正式組後,總容量/總組數即時反映;暖身組不計入(對照 completeWorkout 的排除語意)',
        (tester) async {
      final harness = await _setUpHarness();
      final exercise = await _firstSystemExercise(harness.db);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await harness.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercise);
      final workoutExerciseId =
          harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;

      await _pumpView(tester, harness);

      // 初始:尚未記組,總容量/總組數為 0。
      expect(
        find.descendant(of: find.byKey(const Key('workoutTotalVolumeValue')), matching: find.text('0 kg')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('workoutTotalSetsValue')), matching: find.text('0')),
        findsOneWidget,
      );

      // 暖身組(20 x 10 = 200)——畫面統計不應計入。
      await notifier.addSet(workoutExerciseId: workoutExerciseId, weight: 20, reps: 10, isWarmup: true);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const Key('workoutTotalVolumeValue')), matching: find.text('0 kg')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('workoutTotalSetsValue')), matching: find.text('0')),
        findsOneWidget,
      );

      // 正式組(100 x 5 = 500)——這組才計入。
      await notifier.addSet(workoutExerciseId: workoutExerciseId, weight: 100, reps: 5);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
            of: find.byKey(const Key('workoutTotalVolumeValue')), matching: find.text('500 kg')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('workoutTotalSetsValue')), matching: find.text('1')),
        findsOneWidget,
      );

      // 動作數量固定反映目前草稿的動作數。
      expect(
        find.descendant(of: find.byKey(const Key('workoutExerciseCountValue')), matching: find.text('1')),
        findsOneWidget,
      );
    });
  });

  group('放棄確認(兩分支)', () {
    Future<_Harness> harnessWithDraft(WidgetTester tester) async {
      final harness = await _setUpHarness();
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await harness.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await _pumpView(tester, harness);
      return harness;
    }

    testWidgets('點放棄 → 彈確認框 → 取消 → 草稿不受影響(對話框關閉,畫面仍是進行中訓練)',
        (tester) async {
      final harness = await harnessWithDraft(tester);
      final workoutId = harness.container.read(workoutControllerProvider).value!.draft!.id;
      final repo = WorkoutRepository(harness.db, ExerciseRepository(harness.db));

      await tester.tap(find.byKey(const Key('abandonWorkoutButton')));
      await tester.pumpAndSettle();
      expect(find.text('確定要放棄這次訓練嗎？已記錄的內容都會被刪除，此動作無法復原。'), findsOneWidget);

      await tester.tap(find.byKey(const Key('abandonWorkoutCancelButton')));
      await tester.pumpAndSettle();

      // 對話框關閉、草稿仍在——independent SELECT 驗證沒被誤刪。
      expect(find.byKey(const Key('abandonWorkoutButton')), findsOneWidget);
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNotNull);
      expect(await repo.fetchById(workoutId), isNotNull);
    });

    testWidgets('點放棄 → 彈確認框 → 確定 → 草稿刪除,畫面切回開始畫面', (tester) async {
      final harness = await harnessWithDraft(tester);
      final workoutId = harness.container.read(workoutControllerProvider).value!.draft!.id;
      final repo = WorkoutRepository(harness.db, ExerciseRepository(harness.db));

      await tester.tap(find.byKey(const Key('abandonWorkoutButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('abandonWorkoutConfirmButton')));
      await tester.pumpAndSettle();

      // controller state 收回 idle;WorkoutInProgressView 在 draft == null
      // 時回傳空白(見檔案內註解),父層 workout_page.dart 才負責切回
      // StartWorkoutView——這裡直接斷言 controller state 與 DB,不依賴父層。
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);
      expect(await repo.fetchById(workoutId), isNull);
    });
  });

  group('自動開始休息計時開關(code review r2 major:編輯路徑不能是死開關)', () {
    // 雙向變異:把 _ExerciseCard._openAddSetSheet 裡的
    // `if (!result.isWarmup && result.autoStartRestTimer)` 改回
    // `if (!result.isWarmup)`(拿掉 autoStartRestTimer 條件),這則測試會紅
    // ——關掉開關存新組,restTimerBar 仍然會出現。
    testWidgets('新增組:關掉「自動開始休息計時」開關再儲存 → 計時器不啟動', (tester) async {
      final harness = await _setUpHarness();
      final exercise = await _firstSystemExercise(harness.db);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await harness.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercise);
      final workoutExerciseId =
          harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;

      await _pumpView(tester, harness);

      await tester.tap(find.byKey(Key('addSetButton_$workoutExerciseId')));
      await tester.pumpAndSettle();

      // 非暖身組(預設),開關預設開、可見。
      expect(find.byKey(const Key('addSetAutoStartRestTimerSwitch')), findsOneWidget);
      await tester.tap(find.byKey(const Key('addSetAutoStartRestTimerSwitch')));
      await tester.pump();

      await tester.enterText(find.byKey(const Key('addSetWeightField')), '100');
      await tester.enterText(find.byKey(const Key('addSetRepsField')), '5');
      await tester.pump();
      await tester.tap(find.byKey(const Key('addSetSaveButton')));
      await tester.pumpAndSettle();

      // 正式組本來存了會自動啟動休息計時器,這裡關掉開關 → 不啟動。
      expect(find.byKey(const Key('restTimerBar')), findsNothing);
    });

    // 雙向變異:把 add_set_sheet.dart 的
    // `if (!_isWarmup && widget.showAutoStartRestTimer)` 改回
    // `if (!_isWarmup)`(拿掉 showAutoStartRestTimer 條件),這則測試會紅
    // ——編輯既有組時這顆開關會冒出來,變回一顆使用者點得動、但
    // `_editSet` 完全不讀 `result.autoStartRestTimer` 的死開關(r2 major 描述
    // 的問題重現)。
    testWidgets('編輯既有組:不顯示「自動開始休息計時」開關(編輯不該觸發新的休息倒數)',
        (tester) async {
      final harness = await _setUpHarness();
      final exercise = await _firstSystemExercise(harness.db);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await harness.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercise);
      final workoutExerciseId =
          harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;
      await notifier.addSet(workoutExerciseId: workoutExerciseId, weight: 40, reps: 10);
      final setId = harness.container
          .read(workoutControllerProvider)
          .value!
          .draft!
          .exercises
          .single
          .sets
          .single
          .id;

      await _pumpView(tester, harness);

      await tester.tap(find.byKey(Key('editSetButton_$setId')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('addSetAutoStartRestTimerSwitch')), findsNothing);
    });
  });
}
