// 共用的統計卡片(圖示 + 顏色 + 標題 + 數值)。從
// `features/dashboard/widgets/week_stats_section.dart` 的私有 `_StatCard`
// 抽出(波 4 stats 訓練統計子頁也需要同一張卡片,見波 2 遺留的抽共用計畫)。
// 抽出後 dashboard 端改成 import 這裡的 [StatCard],視覺與既有行為不變
// (欄位簽名照抄原 `_StatCard`)。
import 'package:flutter/material.dart';

class StatCard extends StatelessWidget {
  const StatCard({
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
