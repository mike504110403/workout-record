// 快速操作三按鈕。對應 iOS 版 DashboardView 的 `quickActionsSection`。
import 'package:flutter/material.dart';

class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({
    super.key,
    required this.onRecordWeight,
    required this.onStartWorkout,
    required this.onViewProgress,
  });

  final VoidCallback onRecordWeight;
  final VoidCallback onStartWorkout;
  final VoidCallback onViewProgress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('快速操作', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickActionButton(
                key: const Key('quickActionRecordWeight'),
                icon: Icons.monitor_weight_outlined,
                label: '記錄體重',
                color: Colors.blue,
                onTap: onRecordWeight,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionButton(
                key: const Key('quickActionStartWorkout'),
                icon: Icons.fitness_center,
                label: '開始訓練',
                color: Colors.green,
                onTap: onStartWorkout,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionButton(
                key: const Key('quickActionViewProgress'),
                icon: Icons.show_chart,
                label: '查看進度',
                color: Colors.orange,
                onTap: onViewProgress,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
