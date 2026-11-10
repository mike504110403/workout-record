// 「訓練統計」子頁:容量趨勢圖 + PR 入口 + 本週統計 + 最近訓練。對應 iOS
// `Views/Stats/StatsView.swift` 的 `WorkoutStatsView`。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/workout.dart';
import '../../settings/preferences/weight_unit.dart';
import '../pr/pr_list_controller.dart';
import '../pr/pr_list_page.dart';
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
            const SizedBox(height: AppSpacing.md),
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

    // 下拉刷新接上 controller.refresh()——比照 dashboard_page.dart 的
    // RefreshIndicator 慣例。r2 review 打回記錄:refresh() 先前是死碼(定義
    // 了但沒有任何呼叫端),這裡接上,不是刪掉那個方法。
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.pagePadding.copyWith(top: AppSpacing.sm, bottom: AppSpacing.xl),
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
            const SizedBox(height: AppSpacing.xl),
            _PrEntryCard(
              onTap: () {
                // PR 排行頁的 provider 非 autoDispose,push 前失效讓每次
                // 進入都重新查詢(否則二次進入看到舊快照;WAVE4 merge 接線)。
                ref.invalidate(prListControllerProvider);
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => const PrListPage()));
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            _WeekStatsRow(weekWorkoutCount: state.weekWorkoutCount, weekTotalVolume: state.weekTotalVolume),
            const SizedBox(height: AppSpacing.xl),
            _RecentWorkoutsSection(recentWorkouts: state.recentWorkouts),
          ],
        ),
      ),
    );
  }
}

class _PrEntryCard extends StatelessWidget {
  const _PrEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard(
      key: const Key('prEntryCard'),
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.emoji_events, color: context.semanticColors.pr),
          const SizedBox(width: AppSpacing.md),
          Text('個人記錄 (PR)', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _WeekStatsRow extends ConsumerWidget {
  const _WeekStatsRow({required this.weekWorkoutCount, required this.weekTotalVolume});

  final int weekWorkoutCount;
  final double weekTotalVolume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '本週統計'),
        Row(
          children: [
            Expanded(
              child: AppCard(
                key: const Key('statsWeekWorkoutCountCard'),
                child: MetricTile(value: '$weekWorkoutCount', label: '訓練次數'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppCard(
                key: const Key('statsWeekTotalVolumeCard'),
                // 數字不帶單位(沿用既有慣例),單位放進標籤。
                child: MetricTile(
                  value: formatVolumeBare(weekTotalVolume, unit),
                  label: '總容量 (${unitSuffix(unit)})',
                ),
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
        const SectionHeader(title: '最近訓練'),
        // 對齊 iOS `EmptyWorkoutStatsView`(圖示 + 「尚無訓練記錄」+ 「開始
        // 你的第一次訓練吧！」兩行文案)。
        if (recentWorkouts.isEmpty)
          const EmptyState(
            key: Key('statsRecentWorkoutsEmpty'),
            icon: Icons.directions_walk,
            title: '尚無訓練記錄',
            message: '開始你的第一次訓練吧！',
          )
        else
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
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: Key('statsRecentWorkoutRow-${workout.id}'),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatWorkoutDateTime(workout.startedAt),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${workout.totalExercises} 個動作 • ${workout.totalSets} 組',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatVolumeKg(workout.totalVolume, unit),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${workout.duration ?? 0} 分鐘',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
