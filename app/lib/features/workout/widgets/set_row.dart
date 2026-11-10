// 單組列(進行中訓練頁與歷史編輯頁共用):序號圓標 · 重量 × 次數 · RPE 灰字 ·
// 暖身 chip · 編輯/刪除。
import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/models/workout.dart';
import '../../settings/preferences/weight_unit.dart';
import '../workout_ui_shared.dart';

/// 單組列:序號 · 重量 × 次數(RPE 次要灰字)· 暖身 chip · 編輯/刪除。
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.set,
    required this.unit,
    required this.onEdit,
    required this.onDelete,
    this.editButtonKey,
    this.deleteButtonKey,
  });

  final WorkoutSet set;
  final WeightUnit unit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 編輯/刪除鈕的 key。預設沿用進行中頁的 `editSetButton_<id>`/
  /// `deleteSetButton_<id>`;歷史編輯頁傳入自己既有的 key 以保留測試契約。
  final Key? editButtonKey;
  final Key? deleteButtonKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${set.setNumber}',
              style: theme.textTheme.labelMedium?.tabular.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        '${trimZeros(kgToDisplay(set.weight, unit))} ${unitSuffix(unit)} × ${set.reps} 次',
                    style: AppNumberStyles.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (set.rpe != null)
                    TextSpan(
                      text: '  RPE ${trimZeros(set.rpe!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (set.isWarmup) ...[
            const SizedBox(width: AppSpacing.sm),
            Chip(
              label: const Text('暖身'),
              labelStyle: theme.textTheme.labelSmall,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: colors.tertiaryContainer,
              labelPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
              ),
            ),
          ],
          IconButton(
            key: editButtonKey ?? Key('editSetButton_${set.id}'),
            tooltip: '編輯這組',
            visualDensity: VisualDensity.compact,
            color: colors.onSurfaceVariant,
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
          IconButton(
            key: deleteButtonKey ?? Key('deleteSetButton_${set.id}'),
            tooltip: '刪除這組',
            visualDensity: VisualDensity.compact,
            color: colors.onSurfaceVariant,
            icon: const Icon(Icons.close),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
