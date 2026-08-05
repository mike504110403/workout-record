// 本週統計區塊(兩張 StatCard)。對應 iOS 版 DashboardView 的
// `weekStatsSection` + `Views/Components/StatCardView.swift`。
//
// StatCard 本體已抽到 `core/widgets/stat_card.dart` 共用(波 4 stats 訓練
// 統計子頁也需要同一張卡片,波 2 遺留的抽共用計畫在波 4 兌現)——這裡只保留
// 「本週統計」這個區塊本身(標題 + 兩張卡片排版),卡片外觀不變。
import 'package:flutter/material.dart';

import '../../../core/widgets/stat_card.dart';
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
              child: StatCard(
                key: const Key('weekWorkoutCountCard'),
                icon: Icons.fitness_center,
                color: Colors.blue,
                title: '訓練次數',
                value: '$weekWorkoutCount',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
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
