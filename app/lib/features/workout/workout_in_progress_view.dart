// 進行中訓練畫面(對照 iOS `WorkoutInProgressView`,見
// ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/WorkoutView.swift:152-351)。
// 動作列表 + 記組 + 組間休息 + 即時統計 + 完成/放棄。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/workout.dart';
import 'add_set_sheet.dart';
import 'exercise_picker/exercise_picker_sheet.dart';
import 'rest_timer_bar.dart';
import 'rest_timer_controller.dart';
import 'workout_controller.dart';
import 'workout_summary_sheet.dart';

double _liveTotalVolume(Workout draft) => draft.exercises.fold<double>(
      0,
      (sum, e) => sum +
          e.sets.where((s) => !s.isWarmup).fold<double>(0, (s, set) => s + set.weight * set.reps),
    );

int _liveTotalSets(Workout draft) =>
    draft.exercises.fold<int>(0, (sum, e) => sum + e.sets.where((s) => !s.isWarmup).length);

class WorkoutInProgressView extends ConsumerWidget {
  const WorkoutInProgressView({super.key});

  Future<void> _addExercise(BuildContext context, WidgetRef ref) async {
    final selected = await showExercisePicker(context);
    if (selected == null || selected.isEmpty || !context.mounted) return;
    try {
      await ref.read(workoutControllerProvider.notifier).addExercise(selected.first);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增動作失敗:$e')));
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
        _WorkoutHeader(draft: draft),
        Expanded(
          child: draft.exercises.isEmpty
              ? _EmptyExercisesPrompt(onAdd: () => _addExercise(context, ref))
              : ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  children: [
                    for (final exercise in draft.exercises)
                      _ExerciseCard(key: ValueKey(exercise.id), exercise: exercise),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: OutlinedButton.icon(
                        key: const Key('addExerciseButton'),
                        onPressed: () => _addExercise(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('新增動作'),
                      ),
                    ),
                  ],
                ),
        ),
        _BottomActions(draft: draft, isCompleting: flow.isCompleting, isAbandoning: flow.isAbandoning),
      ],
    );
  }
}

class _EmptyExercisesPrompt extends StatelessWidget {
  const _EmptyExercisesPrompt({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('還沒有動作'),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('addExerciseButtonEmptyState'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('新增動作'),
          ),
        ],
      ),
    );
  }
}

/// 訓練時長每秒跳 + 即時統計(總容量/已完成組數/動作數,對照
/// `WorkoutInProgressView.workoutHeader`)。獨立 `StatefulWidget` 只為了
/// `Timer.periodic` 驅動的每秒重繪,不影響其餘畫面的 rebuild 範圍。
class _WorkoutHeader extends StatefulWidget {
  const _WorkoutHeader({required this.draft});

  final Workout draft;

  @override
  State<_WorkoutHeader> createState() => _WorkoutHeaderState();
}

class _WorkoutHeaderState extends State<_WorkoutHeader> {
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
    // 時長從 draft.startedAt 現算——重啟恢復後 startedAt 就是原本的開始
    // 時間,「時長從原 startedAt 續算」不需要額外欄位或邏輯。
    final elapsed = DateTime.now().difference(widget.draft.startedAt);
    final totalVolume = _liveTotalVolume(widget.draft);
    final totalSets = _liveTotalSets(widget.draft);

    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatColumn(
            label: '訓練時長',
            value: _formatDuration(elapsed),
            valueKey: const Key('workoutDurationValue'),
          ),
          _StatColumn(
            label: '總容量',
            value: '${totalVolume.toStringAsFixed(0)} kg',
            valueKey: const Key('workoutTotalVolumeValue'),
          ),
          _StatColumn(
            label: '總組數',
            value: '$totalSets',
            valueKey: const Key('workoutTotalSetsValue'),
          ),
          _StatColumn(
            label: '動作數',
            value: '${widget.draft.exercises.length}',
            valueKey: const Key('workoutExerciseCountValue'),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value, required this.valueKey});

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    // key 掛在 wrapper(Column)而非 Text 本身,對照 dashboard 慣例與
    // workout_summary_sheet.dart _StatTile 的修法——測試用
    // find.descendant(of: find.byKey(...), matching: find.text(...))。
    return Column(
      key: valueKey,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({super.key, required this.exercise});

  final WorkoutExercise exercise;

  String get _displayName => exercise.exerciseName ?? exercise.exercise?.name ?? '未知動作';

  Future<void> _openAddSetSheet(BuildContext context, WidgetRef ref) async {
    final lastSet = exercise.sets.isEmpty ? null : exercise.sets.last;
    final result = await showAddSetSheet(
      context,
      exerciseName: _displayName,
      setNumber: exercise.sets.length + 1,
      previousWeight: lastSet?.weight,
      previousReps: lastSet?.reps,
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(workoutControllerProvider.notifier).addSet(
            workoutExerciseId: exercise.id,
            weight: result.weight,
            reps: result.reps,
            rpe: result.rpe,
            isWarmup: result.isWarmup,
            restSeconds: result.restSeconds,
          );
      // 儲存組後自動啟動組間休息倒數(D 規格)——暖身組不啟動(對照 iOS
      // AddSetSheet 只在 `!isWarmup` 時提供休息秒數選項)。`start()` 內部
      // 一律先取消既有計時器再重啟,天生涵蓋「休息計時中儲存下一組 →
      // 重啟計時器」(矩陣)。
      if (!result.isWarmup) {
        ref.read(restTimerControllerProvider.notifier).start(
              seconds: result.restSeconds,
              exerciseName: _displayName,
            );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('記錄組數失敗:$e')));
    }
  }

  Future<void> _editSet(BuildContext context, WidgetRef ref, WorkoutSet set) async {
    final result = await showAddSetSheet(
      context,
      exerciseName: _displayName,
      setNumber: set.setNumber,
      initialWeight: set.weight,
      initialReps: set.reps,
      initialRpe: set.rpe,
      initialIsWarmup: set.isWarmup,
      initialRestSeconds: set.restSeconds ?? 90,
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(workoutControllerProvider.notifier).updateSet(set.copyWith(
            weight: result.weight,
            reps: result.reps,
            rpe: result.rpe,
            isWarmup: result.isWarmup,
            restSeconds: result.restSeconds,
          ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新組數失敗:$e')));
    }
  }

  Future<void> _deleteSet(BuildContext context, WidgetRef ref, WorkoutSet set) async {
    try {
      await ref
          .read(workoutControllerProvider.notifier)
          .deleteSet(set.id, workoutExerciseId: exercise.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除組數失敗:$e')));
    }
  }

  Future<void> _toggleCompleted(BuildContext context, WidgetRef ref) async {
    if (!exercise.isCompleted && exercise.sets.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請至少記錄一組訓練後再完成動作')));
      return;
    }
    try {
      await ref
          .read(workoutControllerProvider.notifier)
          .setExerciseCompleted(exercise.id, isCompleted: !exercise.isCompleted);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新動作狀態失敗:$e')));
    }
  }

  Future<void> _deleteExercise(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(workoutControllerProvider.notifier).removeExercise(exercise.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除動作失敗:$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      key: Key('exerciseCard_${exercise.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_displayName, style: Theme.of(context).textTheme.titleMedium),
                ),
                if (exercise.isCompleted)
                  Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                IconButton(
                  key: Key('deleteExerciseButton_${exercise.id}'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteExercise(context, ref),
                ),
              ],
            ),
            for (final set in exercise.sets)
              ListTile(
                key: Key('setRow_${set.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text('#${set.setNumber}${set.isWarmup ? ' 暖身' : ''}'),
                title: Text(
                  '${_trimZeros(set.weight)} kg × ${set.reps} 次'
                  '${set.rpe != null ? '  RPE ${_trimZeros(set.rpe!)}' : ''}',
                ),
                subtitle: Text('容量 ${set.volume.toStringAsFixed(0)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('editSetButton_${set.id}'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editSet(context, ref, set),
                    ),
                    IconButton(
                      key: Key('deleteSetButton_${set.id}'),
                      icon: const Icon(Icons.close),
                      onPressed: () => _deleteSet(context, ref, set),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
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
                  const SizedBox(width: 8),
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
      ),
    );
  }
}

class _BottomActions extends ConsumerWidget {
  const _BottomActions({
    required this.draft,
    required this.isCompleting,
    required this.isAbandoning,
  });

  final Workout draft;
  final bool isCompleting;
  final bool isAbandoning;

  /// 對照 iOS `canCompleteWorkout`:至少一個動作,且每個動作都已標記完成
  /// 且至少有一組記錄。
  bool get _canComplete =>
      draft.exercises.isNotEmpty &&
      draft.exercises.every((e) => e.isCompleted && e.sets.isNotEmpty);

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('放棄訓練失敗:$e')));
    }
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    try {
      final outcome = await ref.read(workoutControllerProvider.notifier).completeWorkout();
      if (!context.mounted) return;
      if (outcome is WorkoutCompleted) {
        ref.read(restTimerControllerProvider.notifier).skip();
        await showWorkoutSummarySheet(context, outcome.workout, outcome.newPersonalRecordCount);
      }
      // WorkoutCompletionNoOp:已經完成過了(冪等),不重複彈 summary。
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('完成訓練失敗:$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = isCompleting || isAbandoning;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('abandonWorkoutButton'),
                onPressed: busy ? null : () => _confirmAbandon(context, ref),
                child: isAbandoning
                    ? const SizedBox(
                        height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('放棄'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('completeWorkoutButton'),
                onPressed: (busy || !_canComplete) ? null : () => _complete(context, ref),
                child: isCompleting
                    ? const SizedBox(
                        height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('完成訓練'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _trimZeros(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toString();
}
