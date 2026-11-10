// 本週卡:把原本重複的「今日概覽」與「本週統計」合併成一張。
// 由上而下:標題列(含「查看進度」次要入口)→ 本週次數/容量 → 目標進度 → 今日狀態。
//
// 次數與目標合在同一格:有設定週目標時顯示「1 / 4 次」(目前值為大數字、目標與
// 單位為小字),沒有目標時顯示「1 次」,不再另外重複一份「訓練次數」。
//
// 目標進度用條:達標(>= 100%)用 success 語意色,其餘用 primary;百分比文字不
// 夾上限(超越目標顯示 200%),條本身夾在 0~100%。
//
// 版式沿用既有的 key,讓導航與測試縫不變:goalProgressCard/goalEmptyState 是目標
// 區塊本身,goalProgressSectionEntry 是它的點擊容器(進目標設定頁)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/user_goal.dart';
import '../../../data/models/workout.dart';
import '../../settings/preferences/weight_unit.dart';
import '../dashboard_format.dart';

class WeekSummaryCard extends ConsumerWidget {
  const WeekSummaryCard({
    super.key,
    required this.weekWorkoutCount,
    required this.weekTotalVolume,
    required this.userGoal,
    required this.goalPercentage,
    required this.motivationalMessage,
    required this.todayWorkout,
    required this.onViewProgress,
    required this.onOpenGoal,
  });

  final int weekWorkoutCount;
  final double weekTotalVolume;
  final UserGoal? userGoal;
  final double? goalPercentage;
  final String motivationalMessage;
  final Workout? todayWorkout;
  final VoidCallback onViewProgress;

  /// 點擊目標區塊(進度或空狀態)時觸發,導去目標設定頁。
  final VoidCallback onOpenGoal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final goal = userGoal;
    final percentage = goalPercentage;
    final hasGoal = goal != null && percentage != null;

    return AppCard(
      key: const Key('weekSummaryCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '本週',
            padding: EdgeInsets.zero,
            trailing: TextButton.icon(
              key: const Key('quickActionViewProgress'),
              onPressed: onViewProgress,
              icon: const Icon(Icons.chevron_right),
              iconAlignment: IconAlignment.end,
              label: const Text('查看進度'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FittedTile(
                  child: MetricTile(
                    key: const Key('weekWorkoutCountCard'),
                    value: '$weekWorkoutCount',
                    unit: hasGoal ? '/ ${goal.weeklyWorkoutGoal} 次' : '次',
                    label: '訓練次數',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _FittedTile(
                  child: MetricTile(
                    key: const Key('weekTotalVolumeCard'),
                    value: formatVolumeBare(weekTotalVolume, unit),
                    unit: unitSuffix(unit),
                    label: '總容量',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasGoal)
            _GoalProgress(
              percentage: percentage,
              message: motivationalMessage,
              onTap: onOpenGoal,
            )
          else
            _GoalEmpty(message: motivationalMessage, onTap: onOpenGoal),
          const Divider(height: AppSpacing.xl),
          if (todayWorkout != null)
            _TodayDone(workout: todayWorkout!, unit: unit)
          else
            const _TodayEmpty(),
        ],
      ),
    );
  }
}

/// 放不下時等比縮小(5 位數容量不被 MetricTile 內的 ellipsis 截斷)。
class _FittedTile extends StatelessWidget {
  const _FittedTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    );
  }
}

class _GoalProgress extends StatelessWidget {
  const _GoalProgress({
    required this.percentage,
    required this.message,
    required this.onTap,
  });

  final double percentage;
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reached = percentage >= 100;
    final barColor = reached ? context.semanticColors.success : colors.primary;

    return KeyedSubtree(
      key: const Key('goalProgressCard'),
      child: InkWell(
        key: const Key('goalProgressSectionEntry'),
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: (percentage / 100).clamp(0, 1),
                minHeight: AppSpacing.sm,
                color: barColor,
                backgroundColor: colors.surfaceContainerHighest,
                borderRadius: AppRadius.chipRadius,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: AppNumberStyles.body(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: barColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalEmpty extends StatelessWidget {
  const _GoalEmpty({required this.message, required this.onTap});

  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return KeyedSubtree(
      key: const Key('goalEmptyState'),
      child: InkWell(
        key: const Key('goalProgressSectionEntry'),
        onTap: onTap,
        borderRadius: AppRadius.controlRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.flag_outlined, size: 20, color: colors.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayDone extends StatelessWidget {
  const _TodayDone({required this.workout, required this.unit});

  final Workout workout;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      key: const Key('todayWorkoutCard'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle, size: 20, color: context.semanticColors.success),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今日已完成訓練',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${workout.duration ?? 0} 分鐘 · '
                '${formatVolumeKg(workout.totalVolume, unit)} · '
                '${workout.totalSets} 組 · '
                '${workout.totalExercises} 個動作',
                style: AppNumberStyles.body(context).copyWith(
                  fontSize: theme.textTheme.bodySmall?.fontSize,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayEmpty extends StatelessWidget {
  const _TodayEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      key: const Key('noWorkoutTodayCard'),
      children: [
        Icon(Icons.radio_button_unchecked, size: 20, color: colors.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '今日尚未訓練',
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
