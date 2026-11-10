// 訓練完成結算報告(workout_summary_sheet.dart)的獨立 widget 測試——不需要
// 走完整訓練流程(exercise picker/記組/完成),直接建一個 [Workout] fixture
// 呼叫 `showWorkoutSummarySheet`,只測顯示層本身(對照
// workout_in_progress_view_test.dart 用最小 harness 而非完整
// `WorkItOutApp` 的手法)。波 6:覆蓋「summary」消費群組的 lb 模式回歸。
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/core/theme/app_semantic_colors.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';
import 'package:workout_record/features/workout/workout_summary_sheet.dart';
import 'package:workout_record/features/workout/workout_ui_shared.dart';

WorkoutSet _set(String id, int n, double weight, int reps, {bool warmup = false}) {
  final now = DateTime.now();
  return WorkoutSet(
    id: id,
    workoutExerciseId: 'we-1',
    setNumber: n,
    weight: weight,
    reps: reps,
    isWarmup: warmup,
    createdAt: now,
    updatedAt: now,
  );
}

Workout _buildWorkout({List<WorkoutSet>? sets}) {
  final now = DateTime.now();
  return Workout(
    id: 'w-summary',
    userId: 'u-1',
    startedAt: now,
    endedAt: now,
    duration: 60,
    totalVolume: 500,
    totalSets: 1,
    totalExercises: 1,
    createdAt: now,
    updatedAt: now,
    exercises: [
      WorkoutExercise(
        id: 'we-1',
        workoutId: 'w-summary',
        exerciseId: 'ex-1',
        exerciseName: 'Fixture 動作',
        createdAt: now,
        updatedAt: now,
        sets: sets ?? [_set('set-1', 1, 100, 5)],
      ),
    ],
  );
}

Future<void> _pumpSummary(
  WidgetTester tester, {
  WeightUnit? weightUnit,
  Workout? workout,
  int prCount = 0,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (weightUnit != null) weightUnitProvider.overrideWithValue(weightUnit),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showWorkoutSummarySheet(context, workout ?? _buildWorkout(), prCount),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('kg 模式(no-op 基準):總容量卡與單組徽章維持既有字串', (tester) async {
    await _pumpSummary(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('summaryVolumeValue')),
        matching: find.text('500 kg'),
      ),
      findsOneWidget,
    );
    expect(find.text('100kg × 5'), findsOneWidget);
  });

  // 波 6:override weightUnitProvider 成 lb——覆蓋「summary」消費群組。
  // 變異:漏接 provider、恆用 kg 版格式化,這些斷言必紅。
  testWidgets('lb 模式:總容量卡與單組徽章換算成 lb 顯示,字尾正確', (tester) async {
    await _pumpSummary(tester, weightUnit: WeightUnit.lb);

    final expectedVolume =
        '${kgToDisplay(500, WeightUnit.lb).toStringAsFixed(0)} lb';
    expect(
      find.descendant(
        of: find.byKey(const Key('summaryVolumeValue')),
        matching: find.text(expectedVolume),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('summaryVolumeValue')),
        matching: find.text('500 kg'),
      ),
      findsNothing,
    );

    final expectedSetWeight = '${trimZeros(kgToDisplay(100, WeightUnit.lb))}lb';
    expect(find.text('$expectedSetWeight × 5'), findsOneWidget);
  });

  testWidgets('同重量 × 次數的組合併顯示「80kg × 8 ×2」;單組不加 ×1;暖身獨立不併入', (tester) async {
    await _pumpSummary(
      tester,
      workout: _buildWorkout(
        sets: [
          _set('s1', 1, 20, 10, warmup: true),
          _set('s2', 2, 80, 8),
          _set('s3', 3, 80, 8),
          _set('s4', 4, 60, 10),
          _set('s5', 5, 80, 8),
        ],
      ),
    );

    expect(find.text('80kg × 8 ×3'), findsOneWidget);
    expect(find.text('60kg × 10'), findsOneWidget);
    expect(find.text('20kg × 10 (暖身)'), findsOneWidget);
    // 合併後 5 組只剩 3 個徽章。
    expect(find.byWidgetPredicate((w) => w is Chip), findsNWidgets(3));
  });

  testWidgets('PR:醒目卡片用 semanticColors.pr,文案不含 emoji', (tester) async {
    await _pumpSummary(tester, prCount: 2);

    expect(find.byKey(const Key('summaryNewPRBanner')), findsOneWidget);
    final text = tester.widget<Text>(find.byKey(const Key('summaryNewPRText')));
    expect(text.data, '本次訓練創造了 2 個新 PR！');
    expect(text.data!.contains('🏆'), isFalse);
    final decoration =
        tester.widget<Container>(find.byKey(const Key('summaryNewPRBanner'))).decoration! as BoxDecoration;
    expect((decoration.border! as Border).top.color, AppSemanticColors.light.pr);
  });

  testWidgets('沒有新 PR:不顯示 PR 卡片', (tester) async {
    await _pumpSummary(tester, prCount: 0);
    expect(find.byKey(const Key('summaryNewPRBanner')), findsNothing);
    expect(find.byKey(const Key('summaryNewPRText')), findsNothing);
  });

  testWidgets('關閉入口只留底部主按鈕:頂部不再有「完成」', (tester) async {
    await _pumpSummary(tester);

    expect(find.byKey(const Key('workoutSummaryDoneButton')), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(TextButton)), findsNothing);

    await tester.tap(find.byKey(const Key('workoutSummaryDoneButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('summaryTitleText')), findsNothing);
  });
}
