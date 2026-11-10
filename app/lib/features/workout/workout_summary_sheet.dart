// 訓練完成結算報告(對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/WorkoutSummaryReportView.swift`)。
// 統計卡的四個數字直接讀 [Workout] 已由 `WorkoutRepository.completeWorkout`
// 算好的欄位(totalVolume/totalSets/totalExercises 已排除暖身組,見
// workout_repository.dart),這裡不重算。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/weight_format.dart' as weight_format;
import '../../core/theme/app_semantic_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/metric_tile.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/workout.dart';
import '../settings/preferences/weight_unit.dart';
import 'workout_metric_row.dart';
import 'workout_ui_shared.dart';

/// 顯示結算報告。關閉後回到開始畫面(呼叫端不需要另外處理——訓練完成時
/// [WorkoutController.completeWorkout] 已經把 state 收回 idle)。
Future<void> showWorkoutSummarySheet(
  BuildContext context,
  Workout workout,
  int newPersonalRecordCount,
) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _WorkoutSummarySheet(
      workout: workout,
      newPersonalRecordCount: newPersonalRecordCount,
    ),
  );
}

class _WorkoutSummarySheet extends ConsumerWidget {
  const _WorkoutSummarySheet({
    required this.workout,
    required this.newPersonalRecordCount,
  });

  final Workout workout;
  final int newPersonalRecordCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Scaffold(
        // 關閉入口只留底部主按鈕(頂部不再放「完成」)。
        appBar: AppBar(
          title: const Text('訓練完成'),
          automaticallyImplyLeading: false,
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageHorizontal,
              AppSpacing.sm,
              AppSpacing.pageHorizontal,
              AppSpacing.md,
            ),
            child: FilledButton(
              key: const Key('workoutSummaryDoneButton'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: context.semanticColors.success,
                    size: 40,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    '訓練完成！',
                    key: const Key('summaryTitleText'),
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Column(
                  children: [
                    FittedMetricRow(
                      tiles: [
                        MetricTile(
                          key: const Key('summaryDurationValue'),
                          label: '訓練時長',
                          value: _formatMinutes(workout.duration ?? 0),
                        ),
                        MetricTile(
                          key: const Key('summaryVolumeValue'),
                          label: '總容量',
                          value: weight_format.formatWeightValue(
                            workout.totalVolume,
                            unit,
                            decimals: 0,
                          ),
                          unit: unitSuffix(unit),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FittedMetricRow(
                      tiles: [
                        MetricTile(
                          key: const Key('summarySetsValue'),
                          label: '總組數',
                          value: '${workout.totalSets}',
                        ),
                        MetricTile(
                          key: const Key('summaryExercisesValue'),
                          label: '動作數量',
                          value: '${workout.totalExercises}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (newPersonalRecordCount > 0) ...[
                const SizedBox(height: AppSpacing.md),
                _PersonalRecordBanner(count: newPersonalRecordCount),
              ],
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: '動作詳情'),
              for (final exercise in workout.exercises) ...[
                AppCard(
                  key: Key('summaryExerciseRow_${exercise.id}'),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.exerciseName ??
                            exercise.exercise?.name ??
                            '未知動作',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final group in _groupSets(exercise.sets))
                            Chip(
                              key: Key('summarySetBadge_${group.first.id}'),
                              label: Text(_setLabel(group, unit)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

/// 新 PR 醒目卡片:`semanticColors.pr` 的淡底 + 描邊 + 獎盃圖示(不用 emoji)。
class _PersonalRecordBanner extends StatelessWidget {
  const _PersonalRecordBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pr = context.semanticColors.pr;
    return Container(
      key: const Key('summaryNewPRBanner'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: pr.withValues(alpha: 0.16),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: pr, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events, color: pr, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '本次訓練創造了 $count 個新 PR！',
              key: const Key('summaryNewPRText'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 把同重量 × 同次數 × 同暖身屬性的組合併(保留首次出現順序)。
List<List<WorkoutSet>> _groupSets(List<WorkoutSet> sets) {
  final groups = <String, List<WorkoutSet>>{};
  for (final set in sets) {
    groups
        .putIfAbsent('${set.weight}|${set.reps}|${set.isWarmup}', () => [])
        .add(set);
  }
  return groups.values.toList();
}

/// 例如 `80kg × 8`、重複 2 組時 `80kg × 8 ×2`、暖身 `20kg × 10 (暖身)`。
String _setLabel(List<WorkoutSet> group, WeightUnit unit) {
  final set = group.first;
  final base =
      '${trimZeros(kgToDisplay(set.weight, unit))}${unitSuffix(unit)} × ${set.reps}'
      '${set.isWarmup ? ' (暖身)' : ''}';
  return group.length > 1 ? '$base ×${group.length}' : base;
}

String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours > 0) return '$hours小時$mins分鐘';
  return '$mins分鐘';
}
