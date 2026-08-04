// 本週統計區塊(兩張 StatCard)。對應 iOS 版 DashboardView 的
// `weekStatsSection` + `Views/Components/StatCardView.swift`。
import 'package:flutter/material.dart';

import '../dashboard_format.dart';

class WeekStatsSection extends StatelessWidget {
  const WeekStatsSection({
    super.key,
    required this.weekWorkoutCount,
    required this.weekTotalVolume,
  });

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
              child: _StatCard(
                key: const Key('weekWorkoutCountCard'),
                icon: Icons.fitness_center,
                color: Colors.blue,
                title: '訓練次數',
                value: '$weekWorkoutCount',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                key: const Key('weekTotalVolumeCard'),
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
