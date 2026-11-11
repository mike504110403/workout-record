// 「開始訓練」下方的「最近用的模板」chip 列:最多 4 個,一點就用該模板開始訓練。
// 沒有模板時整列不顯示(不留空白)。chip 清單由 [dashboardRecentTemplatesProvider]
// 排好,這裡只負責畫與回報點擊。
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../data/models/workout_template.dart';

class RecentTemplatesRow extends StatelessWidget {
  const RecentTemplatesRow({
    super.key,
    required this.templates,
    required this.onSelected,
    this.title = '最近用的模板',
  });

  final List<WorkoutTemplate> templates;
  final ValueChanged<WorkoutTemplate> onSelected;

  /// 有使用紀錄是「最近用的模板」;沒有紀錄、列模板清單時由呼叫端改成「模板」。
  final String title;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          // 最多 4 個、名稱可能很長:單列橫向捲動,不換行撐高版面。
          SingleChildScrollView(
            key: const Key('recentTemplatesRow'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final template in templates)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ActionChip(
                      key: Key('recentTemplateChip-${template.id}'),
                      label: Text(template.name),
                      onPressed: () => onSelected(template),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
