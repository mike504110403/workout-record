// 進行中訓練畫面(對照 iOS `WorkoutInProgressView`,見
// ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/WorkoutView.swift:152-351)。
// 動作列表 + 記組 + 組間休息 + 即時統計 + 完成/放棄。
import '../settings/preferences/default_rest_seconds_preference.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/weight_format.dart' as weight_format;
import '../../core/theme/app_semantic_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/metric_tile.dart';
import '../../data/models/workout.dart';
import '../settings/preferences/weight_unit.dart';
import 'add_set_sheet.dart';
import 'exercise_picker/exercise_picker_sheet.dart';
import 'rest_timer_bar.dart';
import 'rest_timer_controller.dart';
import 'workout_controller.dart';
import 'workout_metric_row.dart';
import 'workout_summary_sheet.dart';
import 'workout_ui_shared.dart';

class WorkoutInProgressView extends ConsumerWidget {
  const WorkoutInProgressView({super.key});

  Future<void> _addExercise(BuildContext context, WidgetRef ref) async {
    final selected = await showExercisePicker(context);
    if (selected == null || selected.isEmpty || !context.mounted) return;
    try {
      await ref
          .read(workoutControllerProvider.notifier)
          .addExercise(selected.first);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('新增動作失敗:$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(workoutControllerProvider).value;
    final draft = flow?.draft;
    // 理論上不會發生(父層 workout_page.dart 只在 draft != null 時掛載這個
    // widget),但完成/放棄成功後 state 會變回 idle——這裡短暫防禦性
    // 回傳空白,下一次 build 父層就會切回 StartWorkoutView。
    if (draft == null || flow == null) return const SizedBox.shrink();

    return Column(
      children: [
        const RestTimerBar(),
        _WorkoutHeader(
          draft: draft,
          isCompleting: flow.isCompleting,
          isAbandoning: flow.isAbandoning,
        ),
        Expanded(
          child: draft.exercises.isEmpty
              ? _EmptyExercisesPrompt(onAdd: () => _addExercise(context, ref))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageHorizontal,
                    AppSpacing.sm,
                    AppSpacing.pageHorizontal,
                    AppSpacing.lg,
                  ),
                  children: [
                    for (final exercise in draft.exercises) ...[
                      _ExerciseCard(
                        key: ValueKey(exercise.id),
                        exercise: exercise,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    OutlinedButton.icon(
                      key: const Key('addExerciseButton'),
                      onPressed: () => _addExercise(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('新增動作'),
                    ),
                  ],
                ),
        ),
        _BottomActions(
          isBusy: flow.isCompleting || flow.isAbandoning,
          isCompleting: flow.isCompleting,
        ),
      ],
    );
  }
}

class _EmptyExercisesPrompt extends StatelessWidget {
  const _EmptyExercisesPrompt({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fitness_center,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('還沒有動作', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              key: const Key('addExerciseButtonEmptyState'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('新增動作'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 訓練時長每秒跳 + 即時統計(時長 · 容量 · 組數,對照
/// `WorkoutInProgressView.workoutHeader`),右側 ⋯ 選單收納「放棄訓練」。
/// 獨立 `StatefulWidget` 只為了 `Timer.periodic` 驅動的每秒重繪,不影響其餘
/// 畫面的 rebuild 範圍。
class _WorkoutHeader extends ConsumerStatefulWidget {
  const _WorkoutHeader({
    required this.draft,
    required this.isCompleting,
    required this.isAbandoning,
  });

  final Workout draft;
  final bool isCompleting;
  final bool isAbandoning;

  @override
  ConsumerState<_WorkoutHeader> createState() => _WorkoutHeaderState();
}

class _WorkoutHeaderState extends ConsumerState<_WorkoutHeader> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(weightUnitProvider);
    // 時長從 draft.startedAt 現算——重啟恢復後 startedAt 就是原本的開始
    // 時間,「時長從原 startedAt 續算」不需要額外欄位或邏輯。
    final elapsed = DateTime.now().difference(widget.draft.startedAt);
    final totalVolume = nonWarmupTotalVolume(widget.draft.exercises);
    final totalSets = nonWarmupTotalSets(widget.draft.exercises);
    final busy = widget.isCompleting || widget.isAbandoning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        AppSpacing.sm,
        AppSpacing.pageHorizontal,
        0,
      ),
      child: AppCard(
        padding: const EdgeInsets.only(
          left: AppSpacing.lg,
          top: AppSpacing.sm,
          bottom: AppSpacing.sm,
          right: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: FittedMetricRow(
                tiles: [
                  MetricTile(
                    key: const Key('workoutDurationValue'),
                    value: _formatDuration(elapsed),
                    label: '時長',
                  ),
                  MetricTile(
                    key: const Key('workoutTotalVolumeValue'),
                    value: weight_format.formatWeightValue(
                      totalVolume,
                      unit,
                      decimals: 0,
                    ),
                    unit: unitSuffix(unit),
                    label: '容量',
                  ),
                  MetricTile(
                    key: const Key('workoutTotalSetsValue'),
                    value: '$totalSets',
                    label: '組數',
                  ),
                ],
              ),
            ),
            if (widget.isAbandoning)
              const SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              PopupMenuButton<_WorkoutMenuAction>(
                key: const Key('workoutMoreMenuButton'),
                tooltip: '更多',
                enabled: !busy,
                onSelected: (action) {
                  switch (action) {
                    case _WorkoutMenuAction.abandon:
                      _confirmAbandon(context, ref);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: const Key('abandonWorkoutButton'),
                    value: _WorkoutMenuAction.abandon,
                    child: Text(
                      '放棄訓練',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

enum _WorkoutMenuAction { abandon }

/// 時長顯示:不滿 1 小時 `MM:SS`,滿 1 小時 `H:MM:SS`。
String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({super.key, required this.exercise});

  final WorkoutExercise exercise;

  String get _displayName =>
      exercise.exerciseName ?? exercise.exercise?.name ?? '未知動作';

  Future<void> _openAddSetSheet(BuildContext context, WidgetRef ref) async {
    final lastSet = exercise.sets.isEmpty ? null : exercise.sets.last;
    final result = await showAddSetSheet(
      context,
      exerciseName: _displayName,
      setNumber: exercise.sets.length + 1,
      initialRestSeconds: ref.read(defaultRestSecondsProvider),
      previousWeight: lastSet?.weight,
      previousReps: lastSet?.reps,
    );
    if (result == null || !context.mounted) return;

    try {
      await ref
          .read(workoutControllerProvider.notifier)
          .addSet(
            workoutExerciseId: exercise.id,
            weight: result.weight,
            reps: result.reps,
            rpe: result.rpe,
            isWarmup: result.isWarmup,
            restSeconds: result.restSeconds,
          );
      // 儲存組後自動啟動組間休息倒數(D 規格)——暖身組不啟動(對照 iOS
      // AddSetSheet 只在 `!isWarmup` 時提供休息秒數選項),非暖身組時再依
      // `autoStartRestTimer` 開關決定是否真的啟動(見 add_set_sheet.dart
      // `AddSetResult.autoStartRestTimer` 文件的與 iOS 刻意差異說明)。
      // `start()` 內部一律先取消既有計時器再重啟,天生涵蓋「休息計時中
      // 儲存下一組 → 重啟計時器」(矩陣)。
      if (!result.isWarmup && result.autoStartRestTimer) {
        ref
            .read(restTimerControllerProvider.notifier)
            .start(seconds: result.restSeconds, exerciseName: _displayName);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('記錄組數失敗:$e')));
    }
  }

  Future<void> _editSet(
    BuildContext context,
    WidgetRef ref,
    WorkoutSet set,
  ) async {
    final result = await showAddSetSheet(
      context,
      exerciseName: _displayName,
      setNumber: set.setNumber,
      initialWeight: set.weight,
      initialReps: set.reps,
      initialRpe: set.rpe,
      initialIsWarmup: set.isWarmup,
      initialRestSeconds:
          set.restSeconds ?? ref.read(defaultRestSecondsProvider),
      // 編輯既有組不該觸發新的休息倒數,整顆開關隱藏不渲染(對照
      // add_set_sheet.dart `AddSetResult.autoStartRestTimer` 文件——不留一顆
      // 點了沒用的開關,code review r2 major 修正)。
      showAutoStartRestTimer: false,
    );
    if (result == null || !context.mounted) return;

    try {
      await ref
          .read(workoutControllerProvider.notifier)
          .updateSet(
            set.copyWith(
              weight: result.weight,
              reps: result.reps,
              rpe: result.rpe,
              isWarmup: result.isWarmup,
              restSeconds: result.restSeconds,
            ),
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新組數失敗:$e')));
    }
  }

  Future<void> _deleteSet(
    BuildContext context,
    WidgetRef ref,
    WorkoutSet set,
  ) async {
    try {
      await ref
          .read(workoutControllerProvider.notifier)
          .deleteSet(set.id, workoutExerciseId: exercise.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('刪除組數失敗:$e')));
    }
  }

  Future<void> _toggleCompleted(BuildContext context, WidgetRef ref) async {
    if (!exercise.isCompleted && exercise.sets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請至少記錄一組訓練後再完成動作')));
      return;
    }
    try {
      await ref
          .read(workoutControllerProvider.notifier)
          .setExerciseCompleted(
            exercise.id,
            isCompleted: !exercise.isCompleted,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新動作狀態失敗:$e')));
    }
  }

  Future<void> _deleteExercise(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(workoutControllerProvider.notifier)
          .removeExercise(exercise.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('刪除動作失敗:$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final theme = Theme.of(context);
    return AppCard(
      key: Key('exerciseCard_${exercise.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Text(_displayName, style: theme.textTheme.titleMedium),
                ),
              ),
              if (exercise.isCompleted)
                Icon(Icons.check_circle, color: context.semanticColors.success),
              IconButton(
                key: Key('deleteExerciseButton_${exercise.id}'),
                tooltip: '刪除動作',
                icon: const Icon(Icons.delete_outline),
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: () => _deleteExercise(context, ref),
              ),
            ],
          ),
          for (final set in exercise.sets)
            _SetRow(
              key: Key('setRow_${set.id}'),
              set: set,
              unit: unit,
              onEdit: () => _editSet(context, ref, set),
              onDelete: () => _deleteSet(context, ref, set),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (!exercise.isCompleted) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('addSetButton_${exercise.id}'),
                    onPressed: () => _openAddSetSheet(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('新增組數'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: FilledButton.tonalIcon(
                  key: Key('toggleExerciseCompletedButton_${exercise.id}'),
                  onPressed: () => _toggleCompleted(context, ref),
                  icon: Icon(exercise.isCompleted ? Icons.undo : Icons.check),
                  label: Text(exercise.isCompleted ? '取消完成' : '完成動作'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 單組列:序號 · 重量 × 次數(RPE 次要灰字)· 暖身 chip · 編輯/刪除。
class _SetRow extends StatelessWidget {
  const _SetRow({
    super.key,
    required this.set,
    required this.unit,
    required this.onEdit,
    required this.onDelete,
  });

  final WorkoutSet set;
  final WeightUnit unit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

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
            key: Key('editSetButton_${set.id}'),
            tooltip: '編輯這組',
            visualDensity: VisualDensity.compact,
            color: colors.onSurfaceVariant,
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
          IconButton(
            key: Key('deleteSetButton_${set.id}'),
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

Future<void> _confirmAbandon(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('放棄訓練'),
      content: const Text('確定要放棄這次訓練嗎？已記錄的內容都會被刪除，此動作無法復原。'),
      actions: [
        TextButton(
          key: const Key('abandonWorkoutCancelButton'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('abandonWorkoutConfirmButton'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('放棄'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(workoutControllerProvider.notifier).abandonWorkout();
    ref.read(restTimerControllerProvider.notifier).skip();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('放棄訓練失敗:$e')));
  }
}

/// 按下「完成訓練」:有動作尚未標記完成時先跳一次確認(取消 → 什麼都不做;
/// 結束 → 繼續完成)。全部動作都已完成(或沒有任何動作)時不跳確認。
Future<void> _onCompletePressed(BuildContext context, WidgetRef ref) async {
  // 以按下當下的草稿為準(不用 build 時捕獲的快照)。
  final draft = ref.read(workoutControllerProvider).value?.draft;
  if (draft == null) return;
  final pending = draft.exercises.where((e) => !e.isCompleted).length;
  if (pending > 0) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('completeWorkoutConfirmDialog'),
        title: const Text('結束訓練'),
        content: Text('有 $pending 個動作尚未完成,仍要結束訓練?'),
        actions: [
          TextButton(
            key: const Key('completeWorkoutCancelButton'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('completeWorkoutConfirmButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('結束'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
  }
  await _completeWorkout(context, ref);
}

Future<void> _completeWorkout(BuildContext context, WidgetRef ref) async {
  try {
    final outcome = await ref
        .read(workoutControllerProvider.notifier)
        .completeWorkout();
    if (!context.mounted) return;
    if (outcome is WorkoutCompleted) {
      ref.read(restTimerControllerProvider.notifier).skip();
      await showWorkoutSummarySheet(
        context,
        outcome.workout,
        outcome.newPersonalRecordCount,
      );
    }
    // WorkoutCompletionNoOp:已經完成過了(冪等),不重複彈 summary。
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('完成訓練失敗,訓練已保留在這台裝置,恢復網路後再按一次「完成訓練」')),
    );
  }
}

/// 固定在底部的主按鈕:全寬「完成訓練」。隨時可按(不再要求每個動作都先按過
/// 「完成動作」)——尚有未完成動作時由 [_onCompletePressed] 跳確認。
class _BottomActions extends ConsumerWidget {
  const _BottomActions({required this.isBusy, required this.isCompleting});

  final bool isBusy;
  final bool isCompleting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
            vertical: AppSpacing.md,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('completeWorkoutButton'),
              onPressed: isBusy ? null : () => _onCompletePressed(context, ref),
              child: isCompleting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('完成訓練'),
            ),
          ),
        ),
      ),
    );
  }
}
