// 今日概覽區塊。對應 iOS 版 DashboardView 的
// `todayOverviewSection`/`TodayWorkoutCard`/`NoWorkoutTodayCard`/`BodyWeightMiniCard`。
//
// 差異:iOS 的 TodayWorkoutCard 只顯示時長/總容量/組數三個指標,這裡照
// brief 需求多加「動作數」第四個指標(`workout.totalExercises`)。
import 'package:flutter/material.dart';

import '../../../data/models/workout.dart';
import '../dashboard_format.dart';

class TodayOverviewSection extends StatelessWidget {
  const TodayOverviewSection({
    super.key,
    required this.todayWorkout,
    required this.currentWeight,
  });

  final Workout? todayWorkout;
  final double? currentWeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('今日概覽', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (todayWorkout != null)
          _TodayWorkoutCard(workout: todayWorkout!)
        else
          const _NoWorkoutTodayCard(),
        const SizedBox(height: 12),
        _BodyWeightMiniCard(currentWeight: currentWeight),
      ],
    );
  }
}

class _TodayWorkoutCard extends StatelessWidget {
  const _TodayWorkoutCard({required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('todayWorkoutCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  '今日已完成訓練',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(label: '訓練時長', value: '${workout.duration ?? 0} 分鐘'),
                ),
                Expanded(
                  child: _Metric(label: '總容量', value: formatVolumeKg(workout.totalVolume)),
                ),
                Expanded(
                  child: _Metric(label: '組數', value: '${workout.totalSets}'),
                ),
                Expanded(
                  child: _Metric(label: '動作數', value: '${workout.totalExercises}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _NoWorkoutTodayCard extends StatelessWidget {
  const _NoWorkoutTodayCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('noWorkoutTodayCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.directions_walk, size: 40, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('今日尚未訓練', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '點擊下方「開始訓練」開始記錄',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyWeightMiniCard extends StatelessWidget {
  const _BodyWeightMiniCard({required this.currentWeight});

  final double? currentWeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('bodyWeightMiniCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '當前體重',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentWeight != null ? formatWeightKg(currentWeight!) : '尚未記錄',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: currentWeight == null ? colorScheme.onSurfaceVariant : null,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.show_chart, size: 30, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
