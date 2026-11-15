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
    '${displayWeight(weightKg, unit)} ${unitSuffix(unit)} × $reps';

/// 重量未定(沒有上次紀錄的 0 kg 計畫組)顯示「— kg × 10」,不能顯示成「0 kg」。
String _unsetWeightReps(int reps, WeightUnit unit) => '— ${unitSuffix(unit)} × $reps';

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
  const _SetNumberBadge({required this.number, this.outlined = false, this.done = false});

  final int number;
  final bool outlined;

  /// 已記錄的組:實心 primary 底、白字(計畫組維持外框)。
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? colors.primary : (outlined ? null : colors.surfaceContainerHighest),
        border: outlined ? Border.all(color: colors.outlineVariant) : null,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: theme.textTheme.labelMedium?.tabular.copyWith(
          color: done ? colors.onPrimary : colors.onSurfaceVariant,
        ),
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
    this.displayNumber,
  });

  final WorkoutSet set;
  final WeightUnit unit;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;
  final bool enabled;

  /// 列上顯示的組序號。預設用 `set.setNumber`;有待刪的組被隱藏時,後面的列要照
  /// 「刪完重編」的結果顯示,由呼叫端傳入。
  final int? displayNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dismissible(
      key: ValueKey('dismissSet_${set.id}'),
      direction: enabled ? DismissDirection.endToStart : DismissDirection.none,
      background: _swipeBackground(context),
      // [onDelete] 回 true＝列隱藏(延遲刪除、可復原,見 workout_pending_actions.dart),
      // 呼叫端在同一個 frame 內把這組排除出清單;回 false＝滑回原位。
      confirmDismiss: (_) => onDelete(),
      // 已記錄的組:淡色底 + 實心組號徽章,與外框徽章的計畫組一眼可分。Material
      // 承接底色,點擊水波才畫得出來。
      child: Material(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        child: InkWell(
        key: Key('setRowTap_${set.id}'),
        onTap: enabled ? onEdit : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              _SetNumberBadge(number: displayNumber ?? set.setNumber, done: true),
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
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
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
    this.weightUnset = false,
  });

  final PlannedSet planned;
  final int setNumber;
  final WeightUnit unit;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;
  final Future<bool> Function() onRemove;
  final bool enabled;

  /// 重量未定(該動作沒有上次紀錄且計畫重量為 0):顯示「— kg × N」;呼叫端也要把
  /// [onConfirm] 接成開記組 sheet,不直接記 0 kg。
  final bool weightUnset;

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
                  weightUnset ? _unsetWeightReps(planned.reps, unit) : _weightReps(planned.weight, planned.reps, unit),
                  style: AppNumberStyles.body(context).copyWith(color: colors.onSurfaceVariant),
                ),
              ),
              IconButton(
                key: Key('confirmPlannedSet_${planned.id}'),
                tooltip: '完成這組',
                icon: const Icon(Icons.radio_button_unchecked),
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
