// 訓練完成結算報告(對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/WorkoutSummaryReportView.swift`)。
// 統計卡的四個數字直接讀 [Workout] 已由 `WorkoutRepository.completeWorkout`
// 算好的欄位(totalVolume/totalSets/totalExercises 已排除暖身組,見
// workout_repository.dart),這裡不重算。
import 'package:flutter/material.dart';

import '../../data/models/workout.dart';

/// 顯示結算報告。關閉後回到開始畫面(呼叫端不需要另外處理——訓練完成時
/// [WorkoutController.completeWorkout] 已經把 state 收回 idle)。
Future<void> showWorkoutSummarySheet(
  BuildContext context,
  Workout workout,
  int newPersonalRecordCount,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _WorkoutSummarySheet(workout: workout, newPersonalRecordCount: newPersonalRecordCount),
  );
}

class _WorkoutSummarySheet extends StatelessWidget {
  const _WorkoutSummarySheet({required this.workout, required this.newPersonalRecordCount});

  final Workout workout;
  final int newPersonalRecordCount;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('訓練完成'),
          automaticallyImplyLeading: false,
          actions: [
            TextButton(
              key: const Key('workoutSummaryDoneButton'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 56),
              const SizedBox(height: 8),
              Text('訓練完成！', key: const Key('summaryTitleText'), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 2.4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  _StatTile(
                    label: '訓練時長',
                    value: _formatMinutes(workout.duration ?? 0),
                    valueKey: const Key('summaryDurationValue'),
                  ),
                  _StatTile(
                    label: '總容量',
                    value: '${workout.totalVolume.toStringAsFixed(0)} kg',
                    valueKey: const Key('summaryVolumeValue'),
                  ),
                  _StatTile(
                    label: '總組數',
                    value: '${workout.totalSets}',
                    valueKey: const Key('summarySetsValue'),
                  ),
                  _StatTile(
                    label: '動作數量',
                    value: '${workout.totalExercises}',
                    valueKey: const Key('summaryExercisesValue'),
                  ),
                ],
              ),
              if (newPersonalRecordCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '🏆 本次訓練創造了 $newPersonalRecordCount 個新 PR！',
                  key: const Key('summaryNewPRText'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
              const SizedBox(height: 16),
              Text('動作詳情', style: Theme.of(context).textTheme.titleMedium),
              for (final exercise in workout.exercises)
                Padding(
                  key: Key('summaryExerciseRow_${exercise.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.exerciseName ?? exercise.exercise?.name ?? '未知動作',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final set in exercise.sets)
                            Chip(
                              key: Key('summarySetBadge_${set.id}'),
                              label: Text(
                                '${_trimZeros(set.weight)}kg × ${set.reps}${set.isWarmup ? ' (暖身)' : ''}',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.valueKey});

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    // key 掛在 wrapper(Card)而非 Text 本身,對照 dashboard 慣例
    // (week_stats_section.dart/today_overview_section.dart)——測試用
    // find.descendant(of: find.byKey(...), matching: find.text(...))。
    return Card(
      key: valueKey,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours > 0) return '$hours小時$mins分鐘';
  return '$mins分鐘';
}

String _trimZeros(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toString();
}
