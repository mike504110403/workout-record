// 進行中訓練畫面(對照 iOS `WorkoutInProgressView`,見
// ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/WorkoutView.swift:152-351)。
//
// ui-polish 改版(2026-11-11):
// - 頂端只留一列統計(時長 · 容量 · 組數)+ 右側 ⋯;休息計時緊貼其下。
// - 底部固定全寬「完成訓練」;草稿 0 組時停用。拿掉「完成動作」鈕與「有 N 個
//   動作未完成」確認框(Mike 裁示 3:有組就算完成,0 組動作完成時自動丟棄,
//   見 `WorkoutController.completeWorkout`)。
// - 動作卡:刪除動作收進卡片 ⋯;組列「點列=編輯、左滑=刪除」;模板帶入的
//   計畫組灰色顯示,打勾才記成真實組(Mike 裁示 2)。
// - 效能:每張卡用 `select` 只監聽自己那個動作;清單用 builder;每秒更新的
//   時長抽成獨立小 widget,不帶著整頁重建。
import '../settings/preferences/default_rest_seconds_preference.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/weight_format.dart' as weight_format;
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/exercise.dart';
import '../../data/models/workout.dart';
import '../settings/preferences/weight_unit.dart';
import 'add_set_sheet.dart';
import 'exercise_history.dart';
import 'exercise_picker/exercise_picker_sheet.dart';
import 'planned_sets_store.dart';
import 'rest_timer_bar.dart';
import 'rest_timer_controller.dart';
import 'widgets/workout_set_tiles.dart';
import 'workout_controller.dart';
import 'workout_page.dart';
import 'workout_summary_sheet.dart';

/// 選動作 → 加進草稿 → 自動開記組 sheet(選完動作直接記第一組,少一次點擊)。
/// 新增動作按鈕與 launcher 的「開始空白訓練」自動開 sheet 共用。
/// 「選完自動開記組」只做在這個呼叫端,`showExercisePicker` 本體不變(模板
/// 表單、歷史編輯頁也用它)。
Future<void> pickAndAddExercise(BuildContext context, WidgetRef ref) async {
  // 「最近用過」上次沒查到就趁這次開 sheet 重查(失敗結果不快取)。
  retryExerciseHistoryIfUnavailable(ref);
  final selected = await showExercisePicker(context, workoutMode: true);
  if (selected == null || selected.isEmpty || !context.mounted) return;
  final Exercise exercise = selected.first;
  final notifier = ref.read(workoutControllerProvider.notifier);
  try {
    await notifier.addExercise(exercise);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增動作失敗:$e')));
    return;
  }
  if (!context.mounted) return;
  final added = ref.read(workoutControllerProvider).value?.draft?.exercises.lastOrNull;
  if (added == null || added.exerciseId != exercise.id) return;
  await recordSet(context, ref, added.id);
}

String _exerciseName(WorkoutExercise exercise) =>
    exercise.exerciseName ?? exercise.exercise?.name ?? '未知動作';

WorkoutExercise? _findExercise(WidgetRef ref, String workoutExerciseId) {
  final draft = ref.read(workoutControllerProvider).value?.draft;
  if (draft == null) return null;
  for (final e in draft.exercises) {
    if (e.id == workoutExerciseId) return e;
  }
  return null;
}

/// 存完一組後依開關啟動組間休息(暖身組不啟動;對照 add_set_sheet.dart
/// `AddSetResult.autoStartRestTimer` 文件)。`start()` 會先取消既有計時器。
void _maybeStartRest(WidgetRef ref, AddSetResult result, String exerciseName) {
  if (!result.isWarmup && result.autoStartRestTimer) {
    ref.read(restTimerControllerProvider.notifier).start(seconds: result.restSeconds, exerciseName: exerciseName);
  }
}

/// 記一組新的組(含「存並再記一組」)。預填:這個動作上一組;還沒有組時用
/// 計畫組的第一組,再沒有就用該動作歷史最後一組(best-effort,查不到空白)。
Future<void> recordSet(BuildContext context, WidgetRef ref, String workoutExerciseId) async {
  final exercise = _findExercise(ref, workoutExerciseId);
  if (exercise == null) return;
  final name = _exerciseName(exercise);
  final history = ref.read(exerciseHistoryProvider).value;
  // 這次預填用手上的快照;上次查詢失敗就順手重查,下一組/下一張卡用得到。
  retryExerciseHistoryIfUnavailable(ref);
  final planned = ref.read(workoutControllerProvider).value?.plannedSets[workoutExerciseId] ?? const [];
  double? prevWeight;
  int? prevReps;
  if (exercise.sets.isNotEmpty) {
    prevWeight = exercise.sets.last.weight;
    prevReps = exercise.sets.last.reps;
  } else if (planned.isNotEmpty) {
    final shown = plannedDisplayValues(planned.first, history?.lastSetsByExerciseId[exercise.exerciseId], 0);
    prevWeight = shown.weight;
    prevReps = shown.reps;
  } else if (history?.lastSetFor(exercise.exerciseId) case final last?) {
    prevWeight = last.weight;
    prevReps = last.reps;
  }

  final notifier = ref.read(workoutControllerProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);

  Future<bool> save(AddSetResult result) async {
    try {
      await notifier.addSet(
        workoutExerciseId: workoutExerciseId,
        weight: result.weight,
        reps: result.reps,
        rpe: result.rpe,
        isWarmup: result.isWarmup,
        restSeconds: result.restSeconds,
      );
      _maybeStartRest(ref, result, name);
      return true;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('記錄組數失敗:$e')));
      return false;
    }
  }

  final result = await showAddSetSheet(
    context,
    exerciseName: name,
    setNumber: exercise.sets.length + 1,
    initialRestSeconds: ref.read(defaultRestSecondsProvider),
    previousWeight: prevWeight,
    previousReps: prevReps,
    compact: true,
    onSaveAndContinue: save,
  );
  if (result == null || !context.mounted) return;
  await save(result);
}

/// 計畫組顯示/預填的數字:該動作上一次同一組的數字;沒練過才用模板值
/// (模板重量一律 0,見 templates/applied_template.dart)。[position] 是這組
/// 在該動作裡的組位置(0 起算,已記的真實組也算在前面)。
/// [lastSets] 是該動作上一次的組(`ExerciseHistory.lastSetsByExerciseId`);
/// 上一次組數比較少時沿用最後一組。
({double weight, int reps}) plannedDisplayValues(PlannedSet planned, List<WorkoutSet>? lastSets, int position) {
  if (lastSets == null || lastSets.isEmpty) return (weight: planned.weight, reps: planned.reps);
  final last = lastSets[position < lastSets.length ? position : lastSets.length - 1];
  return (weight: last.weight, reps: last.reps);
}

class WorkoutInProgressView extends ConsumerWidget {
  const WorkoutInProgressView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只監聽「動作 id 清單」——組數/數字變動由各張卡自己的 select 處理,
    // 不讓整個清單跟著每一次記組重建。
    final ids = ref.watch(
      workoutControllerProvider.select((s) => _IdList([for (final e in s.value?.draft?.exercises ?? const <WorkoutExercise>[]) e.id])),
    );
    final hasDraft = ref.watch(workoutControllerProvider.select((s) => s.value?.draft != null));
    // 預熱「上次數字」查詢(best-effort,不 await;結果只用來預填)。
    ref.watch(exerciseHistoryProvider);
    // 理論上不會發生(父層 workout_page.dart 只在 draft != null 時掛載這個
    // widget),但完成/放棄成功後 state 會變回 idle——短暫回傳空白。
    if (!hasDraft) return const SizedBox.shrink();

    return Column(
      children: [
        const _WorkoutTopBar(),
        const RestTimerBar(),
        Expanded(
          child: ids.ids.isEmpty
              ? _EmptyExercisesPrompt(onAdd: () => pickAndAddExercise(context, ref))
              : ListView.builder(
                  key: const Key('workoutExerciseList'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageHorizontal,
                    AppSpacing.sm,
                    AppSpacing.pageHorizontal,
                    AppSpacing.lg,
                  ),
                  itemCount: ids.ids.length + 1,
                  itemBuilder: (context, index) {
                    if (index == ids.ids.length) {
                      return OutlinedButton.icon(
                        key: const Key('addExerciseButton'),
                        onPressed: () => pickAndAddExercise(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('新增動作'),
                      );
                    }
                    final id = ids.ids[index];
                    return Padding(
                      key: ValueKey(id),
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _ExerciseCard(workoutExerciseId: id),
                    );
                  },
                ),
        ),
        const _BottomActions(),
      ],
    );
  }
}

/// 以內容比較的 id 清單(`select` 用 `==` 判斷要不要重建,List 預設比 identity)。
@immutable
class _IdList {
  const _IdList(this.ids);

  final List<String> ids;

  @override
  bool operator ==(Object other) => other is _IdList && listEquals(other.ids, ids);

  @override
  int get hashCode => Object.hashAll(ids);
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
            Text('還沒有動作', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
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

/// 頂端一列:收起 · 時長 · 容量 · 組數 · ⋯。
class _WorkoutTopBar extends ConsumerWidget {
  const _WorkoutTopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final startedAt = ref.watch(workoutControllerProvider.select((s) => s.value?.draft?.startedAt));
    final totals = ref.watch(
      workoutControllerProvider.select((s) {
        final exercises = s.value?.draft?.exercises ?? const <WorkoutExercise>[];
        return (volume: nonWarmupTotalVolume(exercises), sets: nonWarmupTotalSets(exercises));
      }),
    );
    final isCompleting = ref.watch(workoutControllerProvider.select((s) => s.value?.isCompleting ?? false));
    final isAbandoning = ref.watch(workoutControllerProvider.select((s) => s.value?.isAbandoning ?? false));
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final numberStyle = AppNumberStyles.body(context).copyWith(fontWeight: FontWeight.w600);
    final sepStyle = theme.textTheme.bodyMedium?.copyWith(color: colors.outline);
    final busy = isCompleting || isAbandoning;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            key: const Key('workoutMinimizeButton'),
            tooltip: '收起(訓練保留)',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: busy ? null : () => minimizeWorkoutPage(context),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  // key 掛在外層 KeyedSubtree:測試用 descendant 找數字文字。
                  if (startedAt != null)
                    KeyedSubtree(
                      key: const Key('workoutDurationValue'),
                      child: _ElapsedText(startedAt: startedAt, style: numberStyle),
                    ),
                  Text('  ·  ', style: sepStyle),
                  KeyedSubtree(
                    key: const Key('workoutTotalVolumeValue'),
                    child: Text(
                      '${weight_format.formatWeightValue(totals.volume, unit, decimals: 0)} ${unitSuffix(unit)}',
                      style: numberStyle,
                    ),
                  ),
                  Text('  ·  ', style: sepStyle),
                  KeyedSubtree(
                    key: const Key('workoutTotalSetsValue'),
                    child: Text('${totals.sets} 組', style: numberStyle),
                  ),
                ],
              ),
            ),
          ),
          if (isAbandoning)
            const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
                  child: Text('放棄訓練', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _WorkoutMenuAction { abandon }

/// 每秒更新的訓練時長。獨立小 widget:Timer 只重建這一段文字。時長從
/// `draft.startedAt` 現算——重啟恢復後照原本開始時間續算,不需要額外欄位。
class _ElapsedText extends StatefulWidget {
  const _ElapsedText({required this.startedAt, this.style});

  final DateTime startedAt;
  final TextStyle? style;

  @override
  State<_ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<_ElapsedText> {
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
    return Text(_formatDuration(DateTime.now().difference(widget.startedAt)), style: widget.style);
  }
}

/// 時長顯示:不滿 1 小時 `MM:SS`,滿 1 小時 `H:MM:SS`。
String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

/// 一張動作卡需要的資料快照,`==` 比內容——讓 `select` 只在「這個動作」的
/// 組或計畫組真的變了才重建這張卡(model 本身沒有實作值相等)。
@immutable
class _CardData {
  const _CardData(this.exercise, this.planned);

  final WorkoutExercise exercise;
  final List<PlannedSet> planned;

  static bool _sameSet(WorkoutSet a, WorkoutSet b) =>
      a.id == b.id &&
      a.setNumber == b.setNumber &&
      a.weight == b.weight &&
      a.reps == b.reps &&
      a.rpe == b.rpe &&
      a.isWarmup == b.isWarmup &&
      a.restSeconds == b.restSeconds &&
      a.updatedAt == b.updatedAt;

  @override
  bool operator ==(Object other) {
    if (other is! _CardData) return false;
    final a = exercise;
    final b = other.exercise;
    if (a.id != b.id || _exerciseName(a) != _exerciseName(b) || a.sets.length != b.sets.length) return false;
    for (var i = 0; i < a.sets.length; i++) {
      if (!_sameSet(a.sets[i], b.sets[i])) return false;
    }
    return listEquals(planned, other.planned);
  }

  @override
  int get hashCode => Object.hash(exercise.id, exercise.sets.length, planned.length);
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({required this.workoutExerciseId});

  final String workoutExerciseId;

  Future<void> _editSet(BuildContext context, WidgetRef ref, WorkoutSet set, String name) async {
    final result = await showAddSetSheet(
      context,
      exerciseName: name,
      setNumber: set.setNumber,
      initialWeight: set.weight,
      initialReps: set.reps,
      initialRpe: set.rpe,
      initialIsWarmup: set.isWarmup,
      initialRestSeconds: set.restSeconds ?? ref.read(defaultRestSecondsProvider),
      // 編輯既有組不該觸發新的休息倒數,整顆開關隱藏不渲染(code review r2
      // major:不留一顆點了沒用的開關)。
      showAutoStartRestTimer: false,
      compact: true,
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新組數失敗:$e')));
    }
  }

  Future<bool> _deleteSet(BuildContext context, WidgetRef ref, WorkoutSet set) async {
    try {
      await ref.read(workoutControllerProvider.notifier).deleteSet(set.id, workoutExerciseId: workoutExerciseId);
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除組數失敗:$e')));
      }
      return false;
    }
  }

  Future<void> _deleteExercise(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(workoutControllerProvider.notifier).removeExercise(workoutExerciseId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除動作失敗:$e')));
    }
  }

  /// 計畫組打勾([edited] 為 null)或點開編輯後存(帶 sheet 結果)。
  Future<void> _confirmPlanned(
    BuildContext context,
    WidgetRef ref, {
    required PlannedSet planned,
    required ({double weight, int reps}) shown,
    required String name,
    AddSetResult? edited,
  }) async {
    final int restSeconds = edited?.restSeconds ?? ref.read<int>(defaultRestSecondsProvider);
    try {
      await ref
          .read(workoutControllerProvider.notifier)
          .confirmPlannedSet(
            workoutExerciseId: workoutExerciseId,
            plannedSetId: planned.id,
            weight: edited?.weight ?? shown.weight,
            reps: edited?.reps ?? shown.reps,
            rpe: edited?.rpe,
            isWarmup: edited?.isWarmup ?? false,
            restSeconds: restSeconds,
          );
      _maybeStartRest(
        ref,
        edited ??
            AddSetResult(
              weight: shown.weight,
              reps: shown.reps,
              isWarmup: false,
              restSeconds: restSeconds,
              autoStartRestTimer: true,
            ),
        name,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('記錄組數失敗:$e')));
    }
  }

  Future<void> _editPlanned(
    BuildContext context,
    WidgetRef ref, {
    required PlannedSet planned,
    required ({double weight, int reps}) shown,
    required int setNumber,
    required String name,
  }) async {
    final result = await showAddSetSheet(
      context,
      exerciseName: name,
      setNumber: setNumber,
      initialWeight: shown.weight,
      initialReps: shown.reps,
      initialRestSeconds: ref.read(defaultRestSecondsProvider),
      compact: true,
    );
    if (result == null || !context.mounted) return;
    await _confirmPlanned(context, ref, planned: planned, shown: shown, name: name, edited: result);
  }

  /// 回傳 false 代表移除失敗:左滑的列要滑回原位,不能先消失。
  Future<bool> _removePlanned(BuildContext context, WidgetRef ref, PlannedSet planned) async {
    try {
      await ref
          .read(workoutControllerProvider.notifier)
          .removePlannedSet(workoutExerciseId: workoutExerciseId, plannedSetId: planned.id);
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('移除計畫組失敗:$e')));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
      workoutControllerProvider.select((s) {
        final flow = s.value;
        final exercises = flow?.draft?.exercises ?? const <WorkoutExercise>[];
        for (final e in exercises) {
          if (e.id == workoutExerciseId) return _CardData(e, flow?.plannedSets[e.id] ?? const []);
        }
        return null;
      }),
    );
    if (data == null) return const SizedBox.shrink();
    final exercise = data.exercise;
    // 只在有計畫組時才需要「上次數字」;select 到該動作那一份,別的動作的
    // 歷史變動不會重建這張卡。
    final history = data.planned.isEmpty
        ? null
        : ref.watch(exerciseHistoryProvider.select((h) => h.value?.lastSetsByExerciseId[exercise.exerciseId]));
    final unit = ref.watch(weightUnitProvider);
    // 結算寫入中:不再接受記組/改組/刪組,避免寫進一筆正在結清的訓練。
    final editable = !ref.watch(workoutControllerProvider.select((s) => s.value?.isCompleting ?? false));
    final theme = Theme.of(context);
    final name = _exerciseName(exercise);

    return AppCard(
      key: Key('exerciseCard_${exercise.id}'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: theme.textTheme.titleMedium)),
              PopupMenuButton<String>(
                key: Key('exerciseMoreButton_${exercise.id}'),
                tooltip: '動作選項',
                icon: Icon(Icons.more_horiz, color: theme.colorScheme.onSurfaceVariant),
                onSelected: (_) => _deleteExercise(context, ref),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: Key('deleteExerciseButton_${exercise.id}'),
                    value: 'delete',
                    child: Text('刪除動作', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final set in exercise.sets)
                  SwipeableSetRow(
                    key: Key('setRow_${set.id}'),
                    set: set,
                    unit: unit,
                    enabled: editable,
                    onEdit: () => _editSet(context, ref, set, name),
                    onDelete: () => _deleteSet(context, ref, set),
                  ),
                for (var j = 0; j < data.planned.length; j++)
                  Builder(
                    key: Key('plannedSet_${data.planned[j].id}'),
                    builder: (context) {
                      final planned = data.planned[j];
                      final position = exercise.sets.length + j;
                      final shown = plannedDisplayValues(planned, history, position);
                      return PlannedSetRow(
                        planned: PlannedSet(id: planned.id, weight: shown.weight, reps: shown.reps),
                        setNumber: position + 1,
                        unit: unit,
                        enabled: editable,
                        onConfirm: () =>
                            _confirmPlanned(context, ref, planned: planned, shown: shown, name: name),
                        onEdit: () => _editPlanned(
                          context,
                          ref,
                          planned: planned,
                          shown: shown,
                          setNumber: position + 1,
                          name: name,
                        ),
                        onRemove: () => _removePlanned(context, ref, planned),
                      );
                    },
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('addSetButton_${exercise.id}'),
              onPressed: editable ? () => recordSet(context, ref, exercise.id) : null,
              icon: const Icon(Icons.add),
              label: const Text('新增組數'),
            ),
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

  // 放棄成功後 state 變 idle,這個 widget 隨即被拆掉——離開路徑與之後要用的
  // 東西一律先抓好,成功後不再碰這個 context/ref。
  final exit = WorkoutExit.of(context);
  final restTimer = ref.read(restTimerControllerProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(workoutControllerProvider.notifier).abandonWorkout();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('放棄訓練失敗:$e')));
    return;
  }
  restTimer.skip();
  exit.toDashboard();
}

Future<void> _completeWorkout(BuildContext context, WidgetRef ref) async {
  // 完成後 state 變 idle、這個 widget 會被拆掉(真機上可能在 await 回來之前
  // 就已經拆掉);結算 sheet 與回首頁都改用進入時抓好的根 navigator 與
  // [WorkoutExit],不依賴這個 context/ref。
  final exit = WorkoutExit.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final restTimer = ref.read(restTimerControllerProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  final WorkoutCompletionOutcome outcome;
  try {
    outcome = await ref.read(workoutControllerProvider.notifier).completeWorkout();
  } catch (e) {
    messenger.showSnackBar(
      const SnackBar(content: Text('完成訓練失敗,訓練已保留在這台裝置,恢復網路後再按一次「完成訓練」')),
    );
    return;
  }
  // WorkoutCompletionNoOp:已經完成過了(冪等),不重複彈 summary。
  if (outcome is! WorkoutCompleted) return;
  restTimer.skip();
  if (navigator.mounted) {
    await showWorkoutSummarySheet(navigator.context, outcome.workout, outcome.newPersonalRecordCount);
  }
  exit.toDashboard();
}

/// 固定在底部的主按鈕:全寬「完成訓練」。一組都還沒記時停用(不存空訓練;
/// 要離開走 ⋯ 的「放棄訓練」或左上收起)。
class _BottomActions extends ConsumerWidget {
  const _BottomActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSets = ref.watch(workoutControllerProvider.select((s) => (s.value?.totalSetCount ?? 0) > 0));
    final isCompleting = ref.watch(workoutControllerProvider.select((s) => s.value?.isCompleting ?? false));
    final isAbandoning = ref.watch(workoutControllerProvider.select((s) => s.value?.isAbandoning ?? false));
    final colors = Theme.of(context).colorScheme;
    final busy = isCompleting || isAbandoning;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal, vertical: AppSpacing.md),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('completeWorkoutButton'),
              onPressed: busy || !hasSets ? null : () => _completeWorkout(context, ref),
              child: isCompleting
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('完成訓練'),
            ),
          ),
        ),
      ),
    );
  }
}
