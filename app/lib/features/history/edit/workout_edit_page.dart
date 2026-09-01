// 編輯已完成訓練畫面(波 5)。建構子吃 [workoutId](`Navigator.push` 進入)
// ——本波刻意不掛任何入口,入口在詳情頁上是 WAVE5-MERGE stub,大腦 merge
// 後接線(見 brief「波 5 編輯已完成訓練」規格細節 1)。寫穿模型:每個編輯
// 操作直接寫 DB,沒有取消/還原,離開頁面即是最新狀態
// (`workout_edit_controller.dart` `WorkoutEditController`)。
//
// 日期時間(startedAt/endedAt/duration)不可編輯——這個頁面本身完全不顯示
// 它們(不是「唯讀展示」,是根本沒有渲染),沒有任何輸入框能改到它們
// (code review Std-9:先前這裡寫「這裡只讀顯示」與實作不符,頁面沒有任何
// 日期時間相關的 Text/顯示元件,修正措辭)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/workout.dart';
import '../../workout/add_set_sheet.dart';
import '../../workout/exercise_picker/exercise_picker_sheet.dart';
import '../../workout/workout_ui_shared.dart';
import 'workout_edit_controller.dart';

class WorkoutEditPage extends ConsumerWidget {
  const WorkoutEditPage({super.key, required this.workoutId});

  final String workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(workoutEditControllerProvider(workoutId));
    // isSaving 期間擋返回(code review Std-7):寫入中途使用者按 AppBar 左上角
    // 返回鍵或系統手勢/實體返回鍵離開頁面,`_mutate` 的寫入仍在背景跑,離開
    // 後的畫面看不到失敗浮出的 SnackBar、也無從重試——擋在原地更安全。
    // `PopScope` 的 `canPop: false` 同時擋得住系統返回**與** AppBar 預設
    // 返回鍵(它底層呼叫 `Navigator.maybePop`,會尊重 `PopScope` 的
    // popDisposition)。只做這一層 UI 防線,controller 端的 `ref.mounted`
    // 不動(reviewer 裁示範圍)。
    final isSaving = asyncState.value?.isSaving ?? false;

    return PopScope(
      canPop: !isSaving,
      child: Scaffold(
        appBar: AppBar(title: const Text('編輯訓練')),
        body: asyncState.when(
          data: (state) => _WorkoutEditBody(workoutId: workoutId, state: state),
          loading: () => const Center(child: CircularProgressIndicator()),
          // 固定文案,不把 exception 內容塞進 UI(對齊 dashboard_page.dart 慣例)。
          error: (error, stackTrace) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('載入失敗，請稍後再試'),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('workoutEditRetryButton'),
                  onPressed: () => ref.invalidate(workoutEditControllerProvider(workoutId)),
                  child: const Text('重試'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _addExercise(BuildContext context, WidgetRef ref, String workoutId) async {
  final selected = await showExercisePicker(context);
  if (selected == null || selected.isEmpty || !context.mounted) return;
  try {
    await ref.read(workoutEditControllerProvider(workoutId).notifier).addExercise(selected.first);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增動作失敗:$e')));
  }
}

class _WorkoutEditBody extends ConsumerWidget {
  const _WorkoutEditBody({required this.workoutId, required this.state});

  final String workoutId;
  final WorkoutEditState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = state.workout;
    return Column(
      children: [
        if (state.isSaving)
          const LinearProgressIndicator(key: Key('workoutEditSavingIndicator')),
        Expanded(
          // 寫入進行中時整頁擋互動,避免使用者在同一個 workout 上疊加下一個
          // 操作(controller 端已有 `_synchronized` 序列化鎖兜底,這裡是 UI
          // 層的第一道防線,對照 workout_in_progress_view.dart busy 旗標的
          // 用途)。
          child: AbsorbPointer(
            absorbing: state.isSaving,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _SummaryHeader(workout: workout),
                const SizedBox(height: 16),
                _NoteSection(workoutId: workoutId, note: workout.note),
                const SizedBox(height: 16),
                const Text('動作', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (workout.exercises.isEmpty)
                  const Padding(
                    key: Key('workoutEditEmptyExercisesHint'),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('這筆訓練目前沒有任何動作'),
                  ),
                for (final exercise in workout.exercises)
                  _ExerciseEditCard(
                    key: ValueKey(exercise.id),
                    workoutId: workoutId,
                    exercise: exercise,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: OutlinedButton.icon(
                    key: const Key('workoutEditAddExerciseButton'),
                    onPressed: () => _addExercise(context, ref, workoutId),
                    icon: const Icon(Icons.add),
                    label: const Text('新增動作'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    // 讀「已持久」的欄位(不是從 workout.exercises 現算)——code review
    // Std-6:顯示要對照「DB 裡實際存的事實」,不是拿目前記憶體裡的
    // exercises 現算一份自己的答案。這兩者理論上永遠一致(每次變更後
    // `_mutate` 都會先跑 `recomputeSummary` 才把新 workout 寫回 state),
    // 差別在**鑑別力**:如果 recomputeSummary 哪天失效(忘記呼叫、算錯、
    // guard 擋掉了),現算版本會自己算出正確答案、把 bug 藏起來讓畫面看起來
    // 一切正常;讀持久欄位則會誠實顯示出跟 DB 一致的(可能是錯的)值,測試
    // 斷言才真的在驗證「recompute 有沒有真的發生」,不是在驗證
    // `nonWarmupTotalVolume` 這個純函式本身。
    final totalVolume = workout.totalVolume;
    final totalSets = workout.totalSets;
    final totalExercises = workout.totalExercises;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatColumn(
            label: '總容量',
            value: '${totalVolume.toStringAsFixed(0)} kg',
            valueKey: const Key('workoutEditTotalVolumeValue'),
          ),
          _StatColumn(
            label: '總組數',
            value: '$totalSets',
            valueKey: const Key('workoutEditTotalSetsValue'),
          ),
          _StatColumn(
            label: '動作數',
            value: '$totalExercises',
            valueKey: const Key('workoutEditExerciseCountValue'),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value, required this.valueKey});

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: valueKey,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _NoteSection extends ConsumerStatefulWidget {
  const _NoteSection({required this.workoutId, required this.note});

  final String workoutId;
  final String? note;

  @override
  ConsumerState<_NoteSection> createState() => _NoteSectionState();
}

class _NoteSectionState extends ConsumerState<_NoteSection> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note ?? '');
  }

  @override
  void didUpdateWidget(covariant _NoteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部(DB 重讀)資料變動時同步輸入框內容——只在使用者目前顯示的文字
    // 還等於「舊值」時才覆寫(代表使用者還沒動過這個欄位),避免使用者打
    // 到一半被別的操作觸發的重讀蓋掉。
    if (oldWidget.note != widget.note && _controller.text == (oldWidget.note ?? '')) {
      _controller.text = widget.note ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    try {
      await ref
          .read(workoutEditControllerProvider(widget.workoutId).notifier)
          .updateNote(text.isEmpty ? null : text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('備註已更新')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新備註失敗:$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('備註', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        TextField(
          key: const Key('workoutEditNoteField'),
          controller: _controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '訓練備註(選填)',
            border: OutlineInputBorder(),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('workoutEditSaveNoteButton'),
            onPressed: _save,
            child: const Text('儲存備註'),
          ),
        ),
      ],
    );
  }
}

class _ExerciseEditCard extends ConsumerWidget {
  const _ExerciseEditCard({super.key, required this.workoutId, required this.exercise});

  final String workoutId;
  final WorkoutExercise exercise;

  String get _displayName => exercise.exerciseName ?? exercise.exercise?.name ?? '未知動作';

  Future<void> _confirmDeleteExercise(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除動作'),
        content: Text('確定要刪除「$_displayName」嗎？這個動作底下的所有組數會一併刪除，此動作無法復原。'),
        actions: [
          TextButton(
            key: const Key('workoutEditDeleteExerciseCancelButton'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('workoutEditDeleteExerciseConfirmButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(workoutEditControllerProvider(workoutId).notifier).removeExercise(exercise.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除動作失敗:$e')));
    }
  }

  Future<void> _confirmDeleteSet(BuildContext context, WidgetRef ref, WorkoutSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除組數'),
        content: const Text('確定要刪除這一組嗎？此動作無法復原。'),
        actions: [
          TextButton(
            key: const Key('workoutEditDeleteSetCancelButton'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('workoutEditDeleteSetConfirmButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(workoutEditControllerProvider(workoutId).notifier)
          .deleteSet(set.id, workoutExerciseId: exercise.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除組數失敗:$e')));
    }
  }

  Future<void> _addSet(BuildContext context, WidgetRef ref) async {
    final result = await showAddSetSheet(
      context,
      exerciseName: _displayName,
      setNumber: exercise.sets.length + 1,
      // 編輯已完成訓練沒有「組間休息倒數」這件事,整顆開關不渲染(對照
      // workout_in_progress_view.dart `_editSet` 對既有組的用法)。
      showAutoStartRestTimer: false,
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(workoutEditControllerProvider(workoutId).notifier).addSet(
            workoutExerciseId: exercise.id,
            weight: result.weight,
            reps: result.reps,
            rpe: result.rpe,
            isWarmup: result.isWarmup,
            restSeconds: result.restSeconds,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增組數失敗:$e')));
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
      initialRestSeconds: set.restSeconds ?? kDefaultRestSeconds,
      showAutoStartRestTimer: false,
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(workoutEditControllerProvider(workoutId).notifier).updateSet(set.copyWith(
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      key: Key('workoutEditExerciseCard_${exercise.id}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
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
                IconButton(
                  key: Key('workoutEditDeleteExerciseButton_${exercise.id}'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDeleteExercise(context, ref),
                ),
              ],
            ),
            for (final set in exercise.sets)
              ListTile(
                key: Key('workoutEditSetRow_${set.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text('#${set.setNumber}${set.isWarmup ? ' 暖身' : ''}'),
                title: Text(
                  '${trimZeros(set.weight)} kg × ${set.reps} 次'
                  '${set.rpe != null ? '  RPE ${trimZeros(set.rpe!)}' : ''}',
                ),
                subtitle: Text('容量 ${set.volume.toStringAsFixed(0)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('workoutEditEditSetButton_${set.id}'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editSet(context, ref, set),
                    ),
                    IconButton(
                      key: Key('workoutEditDeleteSetButton_${set.id}'),
                      icon: const Icon(Icons.close),
                      onPressed: () => _confirmDeleteSet(context, ref, set),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: Key('workoutEditAddSetButton_${exercise.id}'),
                onPressed: () => _addSet(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('新增組數'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
