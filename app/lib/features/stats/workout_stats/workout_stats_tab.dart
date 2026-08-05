// 「訓練統計」子頁:容量趨勢圖 + PR 入口 + 本週統計 + 最近訓練。對應 iOS
// `Views/Stats/StatsView.swift` 的 `WorkoutStatsView`。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/stat_card.dart';
import '../../../data/models/workout.dart';
import '../placeholders/pr_list_page.dart';
import 'volume_chart_section.dart';
import 'workout_stats_controller.dart';
import 'workout_stats_format.dart';

class WorkoutStatsTab extends ConsumerWidget {
  const WorkoutStatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(workoutStatsControllerProvider);

    return statsAsync.when(
      data: (state) => _WorkoutStatsContent(state: state),
      loading: () => const Center(child: CircularProgressIndicator()),
      // 非同步失敗路徑:固定文案 + 重試按鈕,invalidate provider 重新查詢
      // ——對照 dashboard_page.dart 的 error 分支慣例。
      error: (error, stackTrace) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('載入失敗，請稍後再試'),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('workoutStatsErrorRetryButton'),
              onPressed: () => ref.invalidate(workoutStatsControllerProvider),
              child: const Text('重試'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutStatsContent extends ConsumerWidget {
  const _WorkoutStatsContent({required this.state});

  final WorkoutStatsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(workoutStatsControllerProvider.notifier);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VolumeChartSection(
            timeRange: state.timeRange,
            muscleGroupFilter: state.muscleGroupFilter,
            dataPoints: state.dataPoints,
            stats: state.stats,
            onTimeRangeChanged: controller.changeTimeRange,
            onMuscleGroupFilterChanged: controller.selectMuscleGroupFilter,
          ),
          const SizedBox(height: 20),
          _PrEntryCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (context) => const PrListPage()),
            ),
          ),
          const SizedBox(height: 20),
          _WeekStatsRow(
            weekWorkoutCount: state.weekWorkoutCount,
            weekTotalVolume: state.weekTotalVolume,
          ),
          const SizedBox(height: 20),
          _RecentWorkoutsSection(recentWorkouts: state.recentWorkouts),
        ],
      ),
    );
  }
}

class _PrEntryCard extends StatelessWidget {
  const _PrEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('prEntryCard'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                Colors.orange.withValues(alpha: 0.1),
                Colors.yellow.withValues(alpha: 0.1),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.emoji_events, color: Colors.orange),
              const SizedBox(width: 12),
              Text('個人記錄 (PR)', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekStatsRow extends StatelessWidget {
  const _WeekStatsRow({required this.weekWorkoutCount, required this.weekTotalVolume});

  final int weekWorkoutCount;
  final double weekTotalVolume;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('本週統計', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                key: const Key('statsWeekWorkoutCountCard'),
                icon: Icons.fitness_center,
                color: Colors.blue,
                title: '訓練次數',
                value: '$weekWorkoutCount',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                key: const Key('statsWeekTotalVolumeCard'),
                icon: Icons.bar_chart,
                color: Colors.green,
                title: '總容量',
                value: formatVolumeBare(weekTotalVolume),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecentWorkoutsSection extends StatelessWidget {
  const _RecentWorkoutsSection({required this.recentWorkouts});

  final List<Workout> recentWorkouts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近訓練', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (recentWorkouts.isEmpty)
          const Padding(
            key: Key('statsRecentWorkoutsEmpty'),
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('尚無訓練記錄')),
          )
        else
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
      key: Key('statsRecentWorkoutRow-${workout.id}'),
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
                    style:
                        Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
