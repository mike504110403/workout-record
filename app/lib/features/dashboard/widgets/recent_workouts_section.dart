// 最近訓練區塊。對應 iOS 版 DashboardView 的 `recentWorkoutsSection` +
// `RecentWorkoutRow`。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/workout.dart';
import '../../settings/preferences/weight_unit.dart';
import '../dashboard_format.dart';

class RecentWorkoutsSection extends StatelessWidget {
  const RecentWorkoutsSection({
    super.key,
    required this.recentWorkouts,
    required this.onViewAll,
  });

  final List<Workout> recentWorkouts;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '最近訓練',
          padding: EdgeInsets.zero,
          trailing: TextButton(
            key: const Key('viewAllWorkoutsButton'),
            onPressed: onViewAll,
            child: const Text('查看全部'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (recentWorkouts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              '完成第一次訓練後會顯示在這裡',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        for (final workout in recentWorkouts) _RecentWorkoutRow(workout: workout),
      ],
    );
  }
}

class _RecentWorkoutRow extends ConsumerWidget {
  const _RecentWorkoutRow({required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final secondary = AppNumberStyles.body(context).copyWith(
      fontSize: theme.textTheme.bodySmall?.fontSize,
      color: colors.onSurfaceVariant,
    );
    return Padding(
      key: Key('recentWorkoutRow-${workout.id}'),
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatWorkoutDateTime(workout.startedAt),
                    style: AppNumberStyles.body(context).copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('${workout.totalExercises} 個動作 • ${workout.totalSets} 組', style: secondary),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatVolumeKg(workout.totalVolume, unit),
                  style: AppNumberStyles.body(context).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('${workout.duration ?? 0} 分鐘', style: secondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
