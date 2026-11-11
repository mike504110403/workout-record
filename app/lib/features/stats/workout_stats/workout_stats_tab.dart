// 「訓練統計」子頁:容量趨勢圖(PR 入口收在趨勢區標題列)。對應 iOS
// `Views/Stats/StatsView.swift` 的 `WorkoutStatsView`。
// 介面改版:本週統計/最近訓練與首頁、歷史重複,已拿掉。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../pr/pr_list_controller.dart';
import '../pr/pr_list_page.dart';
import 'volume_chart_section.dart';
import 'workout_stats_controller.dart';

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
        child: VolumeChartSection(
          timeRange: state.timeRange,
          muscleGroupFilter: state.muscleGroupFilter,
          dataPoints: state.dataPoints,
          stats: state.stats,
          onTimeRangeChanged: controller.changeTimeRange,
          onMuscleGroupFilterChanged: controller.selectMuscleGroupFilter,
          onOpenPr: () {
            // PR 排行頁的 provider 非 autoDispose,push 前失效讓每次
            // 進入都重新查詢(否則二次進入看到舊快照;WAVE4 merge 接線)。
            ref.invalidate(prListControllerProvider);
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => const PrListPage()));
          },
        ),
      ),
    );
  }
}
