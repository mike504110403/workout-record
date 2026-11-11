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
import 'package:workout_record/data/models/workout.dart' show Workout;
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/workout/workout_in_progress_view.dart';
import 'package:workout_record/features/workout/workout_ui_shared.dart';

import '../../data/test_helpers.dart';

typedef _Harness = ({AppDatabase db, ProviderContainer container});

/// [weightUnit] 給定時覆寫 `weightUnitProvider`(波 6 lb 模式回歸測試用,
/// 理由同 dashboard_page_test.dart `_setUpHarness` 的同名參數)。
Future<_Harness> _setUpHarness({WeightUnit? weightUnit}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (weightUnit != null) weightUnitProvider.overrideWithValue(weightUnit),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (db: db, container: container);
}

Future<Exercise> _firstSystemExercise(AppDatabase db) async {
  final exercises = await DriftExerciseRepository(db).fetchSystemExercises();
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

/// 「放棄訓練」收進頂部 ⋯ 選單:先開選單再點項目。
Future<void> _tapAbandon(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('workoutMoreMenuButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('abandonWorkoutButton')));
  await tester.pumpAndSettle();
}

/// 展開記組 sheet 預設收合的「進階選項」。
Future<void> _expandAdvanced(WidgetTester tester) async {
  await tester.tap(find.text('進階選項'));
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
        find.descendant(of: find.byKey(const Key('workoutTotalSetsValue')), matching: find.text('0 組')),
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
        find.descendant(of: find.byKey(const Key('workoutTotalSetsValue')), matching: find.text('0 組')),
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
        find.descendant(of: find.byKey(const Key('workoutTotalSetsValue')), matching: find.text('1 組')),
        findsOneWidget,
      );

      // 頂部統計壓成一列「時長 · 容量 · 組數」(動作數已移除,動作卡本身即可數)。
      expect(find.byKey(const Key('workoutDurationValue')), findsOneWidget);
      expect(find.byKey(const Key('workoutExerciseCountValue')), findsNothing);
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
      final repo = DriftWorkoutRepository(harness.db, DriftExerciseRepository(harness.db));

      await _tapAbandon(tester);
      expect(find.text('確定要放棄這次訓練嗎？已記錄的內容都會被刪除，此動作無法復原。'), findsOneWidget);

      await tester.tap(find.byKey(const Key('abandonWorkoutCancelButton')));
      await tester.pumpAndSettle();

      // 對話框關閉、草稿仍在——independent SELECT 驗證沒被誤刪。
      expect(find.text('確定要放棄這次訓練嗎？已記錄的內容都會被刪除，此動作無法復原。'), findsNothing);
      expect(find.byKey(const Key('workoutMoreMenuButton')), findsOneWidget);
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNotNull);
      expect(await repo.fetchById(workoutId), isNotNull);
    });

    testWidgets('點放棄 → 彈確認框 → 確定 → 草稿刪除(回首頁的導航測在 workout_shell_flow_test)', (tester) async {
      final harness = await harnessWithDraft(tester);
      final workoutId = harness.container.read(workoutControllerProvider).value!.draft!.id;
      final repo = DriftWorkoutRepository(harness.db, DriftExerciseRepository(harness.db));

      await _tapAbandon(tester);
      await tester.tap(find.byKey(const Key('abandonWorkoutConfirmButton')));
      await tester.pumpAndSettle();

      // controller state 收回 idle;WorkoutInProgressView 在 draft == null
      // 時回傳空白,回首頁由全螢幕訓練頁/路由負責——這裡直接斷言 controller
      // state 與 DB,不依賴父層。
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);
      expect(await repo.fetchById(workoutId), isNull);
    });
  });

  // Mike 2026-11-11 裁示 3:拿掉「完成動作」鈕與「有 N 個動作未完成」確認框
  // ——有組就算完成;0 組的動作完成時自動丟棄;草稿 0 組時完成鈕停用。
  group('完成訓練(有組就算完成,不再有「完成動作」與未完成確認框)', () {
    /// 兩個動作;[setsOnSecond] 決定第二個動作有沒有組(第一個一律有一組)。
    Future<_Harness> harnessWithTwoExercises(WidgetTester tester, {required bool setsOnSecond}) async {
      final harness = await _setUpHarness();
      final exercises = await DriftExerciseRepository(harness.db).fetchSystemExercises();
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await harness.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercises[0]);
      await notifier.addExercise(exercises[1]);
      final draft = harness.container.read(workoutControllerProvider).value!.draft!;
      await notifier.addSet(workoutExerciseId: draft.exercises[0].id, weight: 50, reps: 5);
      if (setsOnSecond) {
        await notifier.addSet(workoutExerciseId: draft.exercises[1].id, weight: 50, reps: 5);
      }
      await _pumpView(tester, harness);
      return harness;
    }

    Future<Workout?> fetchWorkout(_Harness harness, String id) =>
        DriftWorkoutRepository(harness.db, DriftExerciseRepository(harness.db)).fetchById(id);

    testWidgets('動作卡上不再有「完成動作」鈕,刪除動作收進卡片 ⋯', (tester) async {
      final harness = await harnessWithTwoExercises(tester, setsOnSecond: true);
      final we = harness.container.read(workoutControllerProvider).value!.draft!.exercises.first.id;

      expect(find.text('完成動作'), findsNothing);
      expect(find.byKey(Key('toggleExerciseCompletedButton_$we')), findsNothing);
      expect(find.byKey(Key('deleteExerciseButton_$we')), findsNothing);

      await tester.tap(find.byKey(Key('exerciseMoreButton_$we')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('deleteExerciseButton_$we')));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('exerciseCard_$we')), findsNothing);
      expect(harness.container.read(workoutControllerProvider).value!.draft!.exercises, hasLength(1));
    });

    testWidgets('有組時按鈕可按,按下不跳任何確認框,直接結算', (tester) async {
      final harness = await harnessWithTwoExercises(tester, setsOnSecond: true);
      final workoutId = harness.container.read(workoutControllerProvider).value!.draft!.id;
      final button = tester.widget<FilledButton>(find.byKey(const Key('completeWorkoutButton')));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('summaryTitleText')), findsOneWidget);
      expect((await fetchWorkout(harness, workoutId))!.endedAt, isNotNull);
    });

    testWidgets('有一個動作 0 組 → 直接結算,該動作被丟棄(結算顯示 1 個動作)', (tester) async {
      final harness = await harnessWithTwoExercises(tester, setsOnSecond: false);
      final workoutId = harness.container.read(workoutControllerProvider).value!.draft!.id;

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.descendant(of: find.byKey(const Key('summaryExercisesValue')), matching: find.text('1')),
        findsOneWidget,
      );
      final saved = (await fetchWorkout(harness, workoutId))!;
      expect(saved.exercises, hasLength(1));
      expect(saved.totalExercises, 1);
    });

    testWidgets('有動作但 0 組時按鈕停用(不存空訓練)', (tester) async {
      final harness = await _setUpHarness();
      final exercise = await _firstSystemExercise(harness.db);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await harness.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercise);
      await _pumpView(tester, harness);

      final button = tester.widget<FilledButton>(find.byKey(const Key('completeWorkoutButton')));
      expect(button.onPressed, isNull);
    });

    testWidgets('草稿還沒有任何動作時按鈕停用', (tester) async {
      final harness = await _setUpHarness();
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await harness.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await _pumpView(tester, harness);

      final button = tester.widget<FilledButton>(find.byKey(const Key('completeWorkoutButton')));
      expect(button.onPressed, isNull);
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

      // 開關在預設收合的「進階選項」內,先展開;非暖身組(預設)開關預設開、可見。
      await _expandAdvanced(tester);
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

      await tester.tap(find.byKey(Key('setRowTap_$setId')));
      await tester.pumpAndSettle();

      // 先展開進階選項,否則「收合所以看不到」會讓這則斷言對退化無感。
      await _expandAdvanced(tester);
      expect(find.byKey(const Key('addSetWarmupSwitch')), findsOneWidget);
      expect(find.byKey(const Key('addSetAutoStartRestTimerSwitch')), findsNothing);
    });
  });

  // 波 6:override weightUnitProvider 成 lb,覆蓋「記訓練」消費群組——即時
  // 統計列總容量、動作卡單組列重量、記組 sheet 輸入換算入庫(儲存一律
  // kg)。變異:任一處漏接 provider、恆用 kg 版格式化,這些斷言必紅。
  group('重量單位(lb 模式)', () {
    testWidgets('即時統計列總容量、動作卡單組列重量換算成 lb 顯示', (tester) async {
      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
      final exercise = await _firstSystemExercise(harness.db);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await harness.container.read(workoutControllerProvider.future);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercise);
      final workoutExerciseId =
          harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;
      await notifier.addSet(workoutExerciseId: workoutExerciseId, weight: 100, reps: 5);

      await _pumpView(tester, harness);

      // 總容量:100kg × 5 = 500kg,換算成 lb 顯示。
      final expectedVolume = '${kgToDisplay(500, WeightUnit.lb).toStringAsFixed(0)} lb';
      expect(
        find.descendant(of: find.byKey(const Key('workoutTotalVolumeValue')), matching: find.text(expectedVolume)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('workoutTotalVolumeValue')), matching: find.text('500 kg')),
        findsNothing,
      );

      // 動作卡單組列:100kg 換算成 lb 顯示,字尾正確(trimZeros——不是固定
      // 小數位,對照 add_set_sheet.dart 現行為)。
      final expectedRowWeight = '${trimZeros(kgToDisplay(100, WeightUnit.lb))} lb';
      expect(find.textContaining(expectedRowWeight), findsOneWidget);
    });

    testWidgets('記組 sheet:label 顯示 lb,輸入 220.5 lb 換算存成約 100kg;編輯既有組時反向帶入', (tester) async {
      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
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

      expect(find.text('重量 (lb)'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('addSetWeightField')), '220.5');
      await tester.enterText(find.byKey(const Key('addSetRepsField')), '1');
      // 標記暖身組——不啟動休息計時器的真實 Timer.periodic,避免與這個測試
      // 無關的「widget tree disposed 後仍有 pending timer」斷言干擾(這裡不
      // 是在測休息計時器)。
      await _expandAdvanced(tester);
      await tester.tap(find.byKey(const Key('addSetWarmupSwitch')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('addSetSaveButton')));
      await tester.pumpAndSettle();

      final repo = DriftWorkoutRepository(harness.db, DriftExerciseRepository(harness.db));
      final workoutId = harness.container.read(workoutControllerProvider).value!.draft!.id;
      final saved = await repo.fetchById(workoutId);
      final setWeight = saved!.exercises.single.sets.single.weight;
      // 期望值用 displayToKg 現算,不手抄係數。
      expect(setWeight, closeTo(displayToKg(220.5, WeightUnit.lb), 0.001));

      // 編輯這一組:輸入框應反向帶入 lb 顯示值(不是原始 kg 值)。
      final setId = harness.container
          .read(workoutControllerProvider)
          .value!
          .draft!
          .exercises
          .single
          .sets
          .single
          .id;
      await tester.tap(find.byKey(Key('setRowTap_$setId')));
      await tester.pumpAndSettle();
      final weightField = tester.widget<TextField>(find.byKey(const Key('addSetWeightField')));
      expect(weightField.controller!.text, trimZeros(kgToDisplay(setWeight, WeightUnit.lb)));
    });
  });
}
