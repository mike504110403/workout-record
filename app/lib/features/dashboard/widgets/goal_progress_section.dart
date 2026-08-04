// 本週目標進度區塊。對應 iOS 版 DashboardView 的 `goalProgressSection`。
//
// 差異(brief 明定):iOS 沒有目標時整個區塊不渲染(`if viewModel.userGoal
// != nil`);本波改成一律渲染區塊標題,沒有目標時顯示空狀態提示文字——本波
// 不做目標設定頁(iOS 的 GoalSettingsView 屬後續波次),所以這裡也不掛任何
// 導航(iOS 標題列的齒輪圖示連去 GoalSettingsView,本波拿掉)。
import 'package:flutter/material.dart';

import '../../../data/models/user_goal.dart';

class GoalProgressSection extends StatelessWidget {
  const GoalProgressSection({
    super.key,
    required this.userGoal,
    required this.weekWorkoutCount,
    required this.goalPercentage,
    required this.motivationalMessage,
  });

  final UserGoal? userGoal;
  final int weekWorkoutCount;
  final double? goalPercentage;
  final String motivationalMessage;

  Color _progressColor(double percentage) {
    if (percentage < 30) return Colors.red;
    if (percentage < 70) return Colors.orange;
    if (percentage < 100) return Colors.blue;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final goal = userGoal;
    final percentage = goalPercentage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('本週目標', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (goal == null || percentage == null)
          Card(
            key: const Key('goalEmptyState'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                motivationalMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          Card(
            key: const Key('goalProgressCard'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '訓練次數',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        '$weekWorkoutCount / ${goal.weeklyWorkoutGoal} 次',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (percentage / 100).clamp(0, 1),
                      minHeight: 8,
                      color: _progressColor(percentage),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          motivationalMessage,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _progressColor(percentage),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
