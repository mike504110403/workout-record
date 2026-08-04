// 波 3 訓練核心流端到端測試:pump 真 `WorkItOutApp`(對照
// test/features/dashboard/dashboard_shell_revisit_test.dart 的手法)——
// repositories/provider 一律用真的,只換 appDatabaseProvider(in-memory)與
// sharedPreferencesProvider(mock prefs)。
//
// 覆蓋 seam 規格要求的兩條端到端:
// 1. 開始自由訓練 → picker 選動作 → 記兩組(一暖身一正式)→ 完成 → summary
//    顯示 → 切首頁 Dashboard 今日卡反映(數字排除暖身)。
// 2. 從模板開始 → showTemplatePicker 選系統模板 → 初始組 3×10 展開 → 記錄
//    → 完成。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/db/app_database.dart' hide Workout, WorkoutExercise, WorkoutSet;
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';

import '../../data/test_helpers.dart';

typedef _Harness = ({AppDatabase db, ProviderContainer container});

Future<_Harness> _setUpLoggedInHarness() async {
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

Future<void> _pumpApp(WidgetTester tester, _Harness harness) async {
  // 選動作器/模板選擇器都是撐到螢幕 90% 高的 bottom sheet,列表項目多
  // (66 筆系統動作)——放大視窗,理由同 templates_crud_test.dart/
  // template_picker_sheet_test.dart 開頭說明:ListView 只 mount 進視窗
  // (含 cacheExtent)內的子項。
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const WorkItOutApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// 在真 exercise picker 裡捲到 [exerciseId] 對應的項目並點下去(單選,對照
/// templates_crud_test.dart `_pickExercisesInForm` 的手法)。
Future<void> _pickExerciseSingle(WidgetTester tester, String exerciseId) async {
  final row = find.byKey(Key('exercise_row_$exerciseId'));
  await tester.scrollUntilVisible(
    row,
    120,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('exercise_picker_list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _fillAddSetSheet(
  WidgetTester tester, {
  required String weight,
  required String reps,
  bool isWarmup = false,
}) async {
  await tester.enterText(find.byKey(const Key('addSetWeightField')), weight);
  await tester.enterText(find.byKey(const Key('addSetRepsField')), reps);
  if (isWarmup) {
    await tester.tap(find.byKey(const Key('addSetWarmupSwitch')));
  }
  await tester.pump();
  await tester.tap(find.byKey(const Key('addSetSaveButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '自由訓練:選動作→記一暖身一正式組→完成→summary 顯示排除暖身的統計→首頁今日卡反映',
    (tester) async {
      final harness = await _setUpLoggedInHarness();
      final exercises = await ExerciseRepository(harness.db).fetchAll();
      final targetExercise = exercises.first;

      await _pumpApp(tester, harness);

      await tester.tap(find.widgetWithText(NavigationDestination, '訓練'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('startFreeWorkoutButton')));
      await tester.pumpAndSettle();

      // 空狀態的「新增動作」入口。
      await tester.tap(find.byKey(const Key('addExerciseButtonEmptyState')));
      await tester.pumpAndSettle();
      await _pickExerciseSingle(tester, targetExercise.id);

      // 動作已加入草稿——獨立 SELECT 取得這個 WorkoutExercise 的 id,才能
      // 點對應的「新增組數」按鈕(key 帶 workoutExercise id,不是 exercise id)。
      final workoutRepo = WorkoutRepository(harness.db, ExerciseRepository(harness.db));
      final draftAfterAddExercise = await workoutRepo.fetchDraft(testUserId);
      expect(draftAfterAddExercise, isNotNull);
      final workoutExerciseId = draftAfterAddExercise!.exercises.single.id;

      // 第一組:暖身組。
      await tester.tap(find.byKey(Key('addSetButton_$workoutExerciseId')));
      await tester.pumpAndSettle();
      await _fillAddSetSheet(tester, weight: '20', reps: '10', isWarmup: true);

      // 暖身組不啟動休息計時器。
      expect(find.byKey(const Key('restTimerBar')), findsNothing);

      // 第二組:正式組,上一組的重量/次數應該預填(對照 iOS `lastSet`)。
      await tester.tap(find.byKey(Key('addSetButton_$workoutExerciseId')));
      await tester.pumpAndSettle();
      expect(find.text('20'), findsOneWidget); // previousWeight 預填
      expect(find.text('10'), findsOneWidget); // previousReps 預填
      await _fillAddSetSheet(tester, weight: '100', reps: '5');

      // 正式組儲存後自動啟動休息倒數。
      expect(find.byKey(const Key('restTimerBar')), findsOneWidget);

      await tester.tap(find.byKey(Key('toggleExerciseCompletedButton_$workoutExerciseId')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();

      // summary 報告:暖身組(20x10=200)排除,只計正式組(100x5=500)。
      expect(find.byKey(const Key('summaryVolumeValue')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('summaryVolumeValue')),
          matching: find.text('500 kg'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('summarySetsValue')), matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('workoutSummaryDoneButton')));
      await tester.pumpAndSettle();

      // 回到開始畫面(草稿已收尾)。
      expect(find.byKey(const Key('startFreeWorkoutButton')), findsOneWidget);

      // 切回首頁,今日卡應該反映這筆已完成訓練,數字排除暖身組。
      await tester.tap(find.widgetWithText(NavigationDestination, '首頁'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('todayWorkoutCard')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('todayWorkoutCard')), matching: find.text('500 kg')),
        findsOneWidget,
      );
    },
  );

  testWidgets('從模板開始:選系統模板「全身訓練」→ 初始組展開為 3×10 → 記錄 → 完成', (tester) async {
    final harness = await _setUpLoggedInHarness();
    await _pumpApp(tester, harness);

    await tester.tap(find.widgetWithText(NavigationDestination, '訓練'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startFromTemplateButton')));
    await tester.pumpAndSettle();

    expect(find.text('全身訓練'), findsOneWidget);
    await tester.tap(find.byKey(Key('templatePickerCardTap_${await _systemTemplateId(harness.db, '全身訓練')}')));
    await tester.pumpAndSettle();

    final workoutRepo = WorkoutRepository(harness.db, ExerciseRepository(harness.db));
    final draft = await workoutRepo.fetchDraft(testUserId);
    expect(draft, isNotNull);
    expect(draft!.exercises, hasLength(5)); // 全身訓練模板固定 5 個動作

    // 第一個動作「深蹲」:suggestedSets=3、suggestedReps=10,展開成 3 組
    // weight=0、reps=10(對照 EnhancedWorkoutFlowView.startWorkoutFromTemplate)。
    final squatExercise = draft.exercises.first;
    expect(squatExercise.sets, hasLength(3));
    expect(squatExercise.sets.every((s) => s.weight == 0 && s.reps == 10), isTrue);

    // 畫面上也看得到這 3 組(setRow key 帶 set id)。
    for (final set in squatExercise.sets) {
      expect(find.byKey(Key('setRow_${set.id}')), findsOneWidget);
    }

    // 記錄第一組的實際重量(把預填的 0kg 改成 40kg)。
    final firstSetId = squatExercise.sets.first.id;
    await tester.tap(find.byKey(Key('editSetButton_$firstSetId')));
    await tester.pumpAndSettle();
    await _fillAddSetSheet(tester, weight: '40', reps: '10');

    final afterEdit = await workoutRepo.fetchById(draft.id);
    expect(afterEdit!.exercises.first.sets.first.weight, 40);

    // 完成所有動作才能結算——逐一標記完成。
    for (final exercise in draft.exercises) {
      await tester.tap(find.byKey(Key('toggleExerciseCompletedButton_${exercise.id}')));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('summaryExercisesValue')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('summaryExercisesValue')), matching: find.text('5')),
      findsOneWidget,
    );
  });
}

Future<String> _systemTemplateId(AppDatabase db, String name) async {
  final row = await (db.select(db.templates)..where((t) => t.name.equals(name))).getSingle();
  return row.id;
}
