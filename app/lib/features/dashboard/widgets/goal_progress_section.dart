// 本週目標進度區塊。對應 iOS 版 DashboardView 的 `goalProgressSection`。
//
// 差異(brief 明定):iOS 沒有目標時整個區塊不渲染(`if viewModel.userGoal
// != nil`);本波改成一律渲染區塊標題,沒有目標時顯示空狀態提示文字。
//
// 波 5 接線:iOS 標題列的齒輪圖示連去 GoalSettingsView,本波在 Dashboard
// 端補上同樣的導航入口——這裡加一個 [onTap] callback,不改卡片內容/空狀態
// 文案本身;要不要導航、導去哪一律由呼叫端(dashboard_page.dart)決定,本
// 檔案不 import GoalSettingsPage、不知道目的地,維持單純的呈現元件。
//
// 版式(review r2 最後一輪修訂):標題列(含 chevron 提示可點,S3 要求)在
// 卡外——同 week_stats_section.dart:27、recent_workouts_section.dart 的既有
// 慣例(標題文字是區塊層級,不屬於任何一張卡片);點擊容器
// `Card`+`InkWell`(S3:照 quick_actions_section.dart 的
// `_QuickActionButton` 慣例,有 ripple 回饋)下移到內層,直接就是
// goalEmptyState/goalProgressCard 那張卡本身,不是另外包一層外卡——避免
// 卡中卡與 padding 三層疊加(先前一版:頁面 16＋外層 Card 16＋內層 Card
// 16)。
import 'package:flutter/material.dart';

import '../../../data/models/user_goal.dart';

class GoalProgressSection extends StatelessWidget {
  const GoalProgressSection({
    super.key,
    required this.userGoal,
    required this.weekWorkoutCount,
    required this.goalPercentage,
    required this.motivationalMessage,
    required this.onTap,
  });

  final UserGoal? userGoal;
  final int weekWorkoutCount;
  final double? goalPercentage;
  final String motivationalMessage;

  /// 點擊整個區塊時觸發(波 5:導去目標設定頁)。review 打回 S4:呼叫端
  /// (dashboard_page.dart)一律會提供,改成 `required`——可為 null 的舊
  /// 簽章暗示「可能不可互動」這個本頁面實際上不存在的狀態。
  final VoidCallback onTap;

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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('本週目標', style: Theme.of(context).textTheme.titleMedium),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (goal == null || percentage == null)
          Card(
            key: const Key('goalEmptyState'),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('goalProgressSectionEntry'),
              onTap: onTap,
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
            ),
          )
        else
          Card(
            key: const Key('goalProgressCard'),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('goalProgressSectionEntry'),
              onTap: onTap,
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
          ),
      ],
    );
  }
}
