// 進行中訓練頁的組列(ui-polish 改版):列內只顯示數字,「點列=編輯、左滑=
// 刪除」,不再放鉛筆與 X 兩顆小鈕(手指好按、版面乾淨)。計畫組(模板帶入、
// 尚未打勾)以灰色顯示,右側一顆勾即記成真實組。
//
// 歷史編輯頁仍用 widgets/set_row.dart 的 [SetRow](那頁不在這次改版範圍,
// 保留它的鉛筆/X 契約不動)。
import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../data/models/workout.dart';
import '../../settings/preferences/weight_unit.dart';
import '../planned_sets_store.dart';
import '../workout_ui_shared.dart';

String _weightReps(double weightKg, int reps, WeightUnit unit) =>
    '${trimZeros(kgToDisplay(weightKg, unit))} ${unitSuffix(unit)} × $reps';

/// 左滑露出的紅底刪除背景(真實組與計畫組共用)。
Widget _swipeBackground(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: AppSpacing.lg),
    color: colors.errorContainer,
    child: Icon(Icons.delete_outline, color: colors.onErrorContainer),
  );
}

class _SetNumberBadge extends StatelessWidget {
  const _SetNumberBadge({required this.number, this.outlined = false});

  final int number;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: outlined ? null : colors.surfaceContainerHighest,
        border: outlined ? Border.all(color: colors.outlineVariant) : null,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: theme.textTheme.labelMedium?.tabular.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}

/// 真實組:點列編輯、左滑刪除。[onDelete] 回傳 false 代表刪除失敗,列滑回原位。
/// [enabled] 為 false(結算寫入中)時點擊與左滑都停用。
class SwipeableSetRow extends StatelessWidget {
  const SwipeableSetRow({
    super.key,
    required this.set,
    required this.unit,
    required this.onEdit,
    required this.onDelete,
    this.enabled = true,
  });

  final WorkoutSet set;
  final WeightUnit unit;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dismissible(
      key: ValueKey('dismissSet_${set.id}'),
      direction: enabled ? DismissDirection.endToStart : DismissDirection.none,
      background: _swipeBackground(context),
      // 等刪除真的寫入成功才讓列消失;失敗時滑回原位(controller 已序列化
      // 寫入,這裡不用自己防連滑)。
      confirmDismiss: (_) => onDelete(),
      child: InkWell(
        key: Key('setRowTap_${set.id}'),
        onTap: enabled ? onEdit : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              _SetNumberBadge(number: set.setNumber),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _weightReps(set.weight, set.reps, unit),
                        style: AppNumberStyles.body(context).copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (set.rpe != null)
                        TextSpan(
                          text: '  RPE ${trimZeros(set.rpe!)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ),
              if (set.isWarmup)
                Text(
                  '暖身',
                  style: theme.textTheme.labelSmall?.copyWith(color: colors.tertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 計畫組:灰色數字;右側勾=照這組數字記成真實組,點列=開記組 sheet 改數字
/// 後再存,左滑=不做這組。[onRemove] 回傳 false 代表移除失敗,列滑回原位。
/// [enabled] 為 false(結算寫入中)時勾、點擊、左滑都停用。
class PlannedSetRow extends StatelessWidget {
  const PlannedSetRow({
    super.key,
    required this.planned,
    required this.setNumber,
    required this.unit,
    required this.onConfirm,
    required this.onEdit,
    required this.onRemove,
    this.enabled = true,
  });

  final PlannedSet planned;
  final int setNumber;
  final WeightUnit unit;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;
  final Future<bool> Function() onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('dismissPlanned_${planned.id}'),
      direction: enabled ? DismissDirection.endToStart : DismissDirection.none,
      background: _swipeBackground(context),
      // 同真實組:等 controller 移除完再讓列消失;移除失敗時滑回原位(不然列
      // 已從畫面消失、state 卻還留著那組,Dismissible 會報錯)。
      confirmDismiss: (_) => onRemove(),
      child: InkWell(
        key: Key('plannedSetRow_${planned.id}'),
        onTap: enabled ? onEdit : null,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xs),
          child: Row(
            children: [
              _SetNumberBadge(number: setNumber, outlined: true),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _weightReps(planned.weight, planned.reps, unit),
                  style: AppNumberStyles.body(context).copyWith(color: colors.onSurfaceVariant),
                ),
              ),
              IconButton(
                key: Key('confirmPlannedSet_${planned.id}'),
                tooltip: '完成這組',
                icon: const Icon(Icons.check_circle_outline),
                color: colors.primary,
                onPressed: enabled ? onConfirm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
