// 最近訓練區塊。對應 iOS 版 DashboardView 的 `recentWorkoutsSection` +
// `RecentWorkoutRow`。
import 'package:flutter/material.dart';

import '../../../data/models/workout.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('最近訓練', style: Theme.of(context).textTheme.titleMedium),
            TextButton(
              key: const Key('viewAllWorkoutsButton'),
              onPressed: onViewAll,
              child: const Text('查看全部'),
            ),
          ],
        ),
        for (final workout in recentWorkouts) _RecentWorkoutRow(workout: workout),
      ],
    );
  }
}

class _RecentWorkoutRow extends StatelessWidget {
  const _RecentWorkoutRow({required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      key: Key('recentWorkoutRow-${workout.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatWorkoutDateTime(workout.startedAt),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${workout.totalExercises} 個動作 • ${workout.totalSets} 組',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatVolumeKg(workout.totalVolume),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${workout.duration ?? 0} 分鐘',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
