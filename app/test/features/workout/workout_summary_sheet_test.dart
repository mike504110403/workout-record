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

import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';
import 'package:workout_record/features/workout/workout_summary_sheet.dart';
import 'package:workout_record/features/workout/workout_ui_shared.dart';

Workout _buildWorkout() {
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
        sets: [
          WorkoutSet(
            id: 'set-1',
            workoutExerciseId: 'we-1',
            setNumber: 1,
            weight: 100,
            reps: 5,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    ],
  );
}

Future<void> _pumpSummary(WidgetTester tester, {WeightUnit? weightUnit}) async {
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
                showWorkoutSummarySheet(context, _buildWorkout(), 0),
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
}
