// 單筆訓練的摘要卡——列表檢視、日曆檢視「當天訓練清單」共用同一份(對照
// iOS `WorkoutHistoryCard`)。顯示欄位依 brief 規格:日期、總容量、時長、
// 動作數(不含組數——組數留給詳情頁的完整 summary)。另顯示星期幾與動作名
// 摘要(「槓鈴臥推、深蹲 +2」)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/models/workout.dart';
import '../../settings/preferences/weight_unit.dart';
import '../history_format.dart';

class WorkoutHistoryCard extends ConsumerWidget {
  const WorkoutHistoryCard({super.key, required this.workout, required this.onTap, this.isDeleting = false});

  final Workout workout;
  final VoidCallback onTap;

  /// true 時在卡片上蓋一層 loading 遮罩、停用點擊——對應
  /// `HistoryListController.deletingIds` 追蹤中的這一筆(見該檔案文件注
  /// 解:刪除失敗時這個旗標會被移除,遮罩隨之解除,不會卡死)。
  final bool isDeleting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    final summary = summarizeWorkoutExercises(workout);
    return Card(
      key: Key('historyWorkoutCard-${workout.id}'),
      // 全域 Card theme 的 margin 為 0,列與列的間距由卡片自己補。
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InkWell(
            onTap: isDeleting ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(formatHistoryDate(workout.startedAt), style: theme.textTheme.titleMedium),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              formatHistoryWeekday(workout.startedAt),
                              key: Key('historyWorkoutWeekday-${workout.id}'),
                              style: muted,
                            ),
                          ],
                        ),
                        if (summary != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            summary,
                            key: Key('historyWorkoutSummary-${workout.id}'),
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Icon(Icons.timer_outlined, size: 14, color: colors.onSurfaceVariant),
                            const SizedBox(width: AppSpacing.xs),
                            Text(formatDurationMinutes(workout.duration), style: muted),
                            const SizedBox(width: AppSpacing.lg),
                            Icon(Icons.fitness_center, size: 14, color: colors.onSurfaceVariant),
                            const SizedBox(width: AppSpacing.xs),
                            Text('${workout.totalExercises} 個動作', style: muted),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    formatVolumeKg(workout.totalVolume, unit),
                    style: AppNumberStyles.medium(context).copyWith(color: colors.primary),
                  ),
                ],
              ),
            ),
          ),
          if (isDeleting)
            Positioned.fill(
              child: Container(
                color: colors.surface.withValues(alpha: 0.7),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    key: Key('historyWorkoutDeletingIndicator-${workout.id}'),
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
