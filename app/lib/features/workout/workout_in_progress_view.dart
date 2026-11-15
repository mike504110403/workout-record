// 進行中訓練畫面(對照 iOS `WorkoutInProgressView`,見
// ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/WorkoutView.swift:152-351)。
//
// ui-polish 改版(2026-11-11):
// - 頂端只留一列統計(時長 · 容量 · 組數)+ 右側 ⋯;休息計時(2026-11-16 起)
//   在底部主鈕正上方,單手拇指可及。
// - (2026-11-15 inprogress-ux)底部主鈕改「記下一組」(作用於目前動作),「完成」
//   移到頂列右側;刪組/刪動作/完成訓練都是延遲執行＋復原
//   (workout_pending_actions.dart)。
// - 完成訓練草稿 0 組時停用。拿掉「完成動作」鈕與「有 N 個
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
import 'workout_pending_actions.dart';
import 'workout_ui_shared.dart' show trimZeros;
import 'workout_summary_sheet.dart';

/// 選動作 → 加進草稿 → 自動開記組 sheet(選完動作直接記第一組,少一次點擊)。
/// 新增動作按鈕與 launcher 的「開始空白訓練」自動開 sheet 共用。
/// 「選完自動開記組」只做在這個呼叫端,`showExercisePicker` 本體不變(模板
/// 表單、歷史編輯頁也用它)。
Future<void> pickAndAddExercise(BuildContext context, WidgetRef ref) async {
  // 「最近用過」上次沒查到就趁這次開 sheet 重查(失敗結果不快取)。
  retryExerciseHistoryIfUnavailable(ref);
  final selected = await showExercisePicker(context, workoutMode: true, multiSelect: true);
  if (selected == null || selected.isEmpty || !context.mounted) return;
  final notifier = ref.read(workoutControllerProvider.notifier);
  // 依勾選順序逐個加;某一個失敗就停,已加的保留。
  for (final exercise in selected) {
    try {
      await notifier.addExercise(exercise);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新增動作失敗:$e')));
      return;
    }
    if (!context.mounted) return;
  }
  // 只選 1 個才自動開記組 sheet;一次加多個不自動開(不知道要先記哪個)。
  if (selected.length != 1) return;
  final exercise = selected.first;
  final added = ref.read(workoutControllerProvider).value?.draft?.exercises.lastOrNull;
  if (added == null || added.exerciseId != exercise.id) return;
  await recordSet(context, ref, added.id);
}

/// 動作卡「上次成績」一行字:上次組清單裡重量最大的一組(同重量取次數多者,
/// 再同取較前面的組)+ 組數,例如「上次 60 kg × 8・3 組」;最大重量為 0(自重)
/// 改顯示該動作最大次數「上次 12 下・3 組」。沒有組回 null(不顯示)。
/// 重量格式與組列一致(`trimZeros(kgToDisplay(..))`)。
@visibleForTesting
String? lastPerformanceText(List<WorkoutSet>? sets, WeightUnit unit) {
  if (sets == null || sets.isEmpty) return null;
  var best = sets.first;
  for (final s in sets.skip(1)) {
    if (s.weight > best.weight || (s.weight == best.weight && s.reps > best.reps)) best = s;
  }
  if (best.weight <= 0) {
    final maxReps = sets.fold<int>(0, (m, s) => s.reps > m ? s.reps : m);
    return '上次 $maxReps 下・${sets.length} 組';
  }
  return '上次 ${trimZeros(kgToDisplay(best.weight, unit))} ${unitSuffix(unit)} × ${best.reps}・${sets.length} 組';
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
  // 待刪(畫面已隱藏)的組不算:預填與組序號都照「刪完」的樣子。
  final sets = visibleSetsOf(exercise, ref.read(pendingActionsProvider));
  double? prevWeight;
  int? prevReps;
  if (sets.isNotEmpty) {
    prevWeight = sets.last.weight;
    prevReps = sets.last.reps;
  } else if (planned.isNotEmpty) {
    final shown = plannedDisplayValues(planned.first, history?.lastSetsByExerciseId[exercise.exerciseId], 0);
    prevWeight = shown.weight;
    prevReps = shown.reps;
  } else if (history?.lastSetFor(exercise.exerciseId) case final last?) {
    prevWeight = last.weight;
    prevReps = last.reps;
  }

  final notifier = ref.read(workoutControllerProvider.notifier);
  final pendingNotifier = ref.read(pendingActionsProvider.notifier);
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
      pendingNotifier.markTouched(workoutExerciseId);
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
    setNumber: sets.length + 1,
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

/// 重量未定的計畫組:該動作沒有上次紀錄([lastSets] 為 null 或空)**且**計畫重量為 0
/// (模板重量一律 0,見 templates/applied_template.dart)。這種組不能一鍵記成
/// 0 kg——列上顯示「— kg × N」,打勾改開記組 sheet。有上次紀錄(含上次就是
/// 0 kg 的徒手動作)照現行直接打勾。
bool plannedNeedsInput(PlannedSet planned, List<WorkoutSet>? lastSets) =>
    (lastSets == null || lastSets.isEmpty) && planned.weight == 0;

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
    // 待刪動作:畫面立即隱藏(DB 要等復原期結束才真刪)。
    final deletedExercises = ref.watch(pendingActionsProvider.select((p) => p.deletedExerciseIds));
    final visibleIds = [for (final id in ids.ids) if (!deletedExercises.contains(id)) id];
    final busy = ref.watch(_workoutBusyProvider);
    // 預熱「上次數字」查詢(best-effort,不 await;結果只用來預填)。
    ref.watch(exerciseHistoryProvider);
    // 理論上不會發生(父層 workout_page.dart 只在 draft != null 時掛載這個
    // widget),但完成/放棄成功後 state 會變回 idle——短暫回傳空白。
    if (!hasDraft) return const SizedBox.shrink();

    return Column(
      children: [
        const _WorkoutTopBar(),
        Expanded(
          child: visibleIds.isEmpty
              ? _EmptyExercisesPrompt(onAdd: busy ? null : () => pickAndAddExercise(context, ref))
              : ListView.builder(
                  key: const Key('workoutExerciseList'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pageHorizontal,
                    AppSpacing.sm,
                    AppSpacing.pageHorizontal,
                    AppSpacing.lg,
                  ),
                  itemCount: visibleIds.length + 1,
                  itemBuilder: (context, index) {
                    if (index == visibleIds.length) {
                      return OutlinedButton.icon(
                        key: const Key('addExerciseButton'),
                        onPressed: busy ? null : () => pickAndAddExercise(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('新增動作'),
                      );
                    }
                    final id = visibleIds[index];
                    return Padding(
                      key: ValueKey(id),
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _ExerciseCard(workoutExerciseId: id),
                    );
                  },
                ),
        ),
        // 休息計時列/結束提示在底部拇指區,緊貼主鈕上方(不顯示時不佔高度)。
        const RestTimerBar(),
        const _BottomActions(),
      ],
    );
  }
}

/// 整頁「忙碌」:結算寫入中、放棄寫入中、或完成流程進行中(flush/倒數/執行)。
/// 忙碌時新增動作、底部主鈕、卡片操作、完成鈕、⋯ 選單一律停用。
/// (收起鈕另算:倒數期間仍可收起,見 [_WorkoutTopBar];契約是沒復原就一定完成。)
final _workoutBusyProvider = Provider<bool>((ref) {
  final isCompleting = ref.watch(workoutControllerProvider.select((s) => s.value?.isCompleting ?? false));
  final isAbandoning = ref.watch(workoutControllerProvider.select((s) => s.value?.isAbandoning ?? false));
  final completeBusy = ref.watch(pendingActionsProvider.select((p) => p.completeBusy));
  return isCompleting || isAbandoning || completeBusy;
});

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

  final VoidCallback? onAdd;

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
    // 統計排除待刪項目(畫面已隱藏、DB 尚未真刪)。
    final totals = ref.watch(visibleTotalsProvider);
    final hasSets = ref.watch(workoutControllerProvider.select((s) => (s.value?.totalSetCount ?? 0) > 0));
    final isCompleting = ref.watch(workoutControllerProvider.select((s) => s.value?.isCompleting ?? false));
    final isAbandoning = ref.watch(workoutControllerProvider.select((s) => s.value?.isAbandoning ?? false));
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final numberStyle = AppNumberStyles.body(context).copyWith(fontWeight: FontWeight.w600);
    final sepStyle = theme.textTheme.bodyMedium?.copyWith(color: colors.outline);
    final busy = ref.watch(_workoutBusyProvider);
    // 收起鈕只在寫入中停用;完成倒數期間仍可收起(倒數照跑、時間到就完成)。
    final cannotMinimize = isCompleting || isAbandoning;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            key: const Key('workoutMinimizeButton'),
            tooltip: '收起(訓練保留)',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: cannotMinimize ? null : () => minimizeWorkoutPage(context),
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
          // 次要樣式的「完成」:0 組時停用;按下是延遲完成(可復原),見 [_completeWorkout]。
          FilledButton.tonal(
            key: const Key('completeWorkoutButton'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(56, 40),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            ),
            onPressed: busy || !hasSets ? null : () => _completeWorkout(context, ref),
            child: isCompleting
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('完成'),
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

/// 計畫組打勾([edited] 為 null)或點開編輯後存(帶 sheet 結果)。底部主按鈕與
/// 動作卡共用,所以是頂層函式、帶 [workoutExerciseId]。
Future<void> _confirmPlanned(
  BuildContext context,
  WidgetRef ref,
  String workoutExerciseId, {
  required PlannedSet planned,
  required ({double weight, int reps}) shown,
  required String name,
  AddSetResult? edited,
}) async {
  final int restSeconds = edited?.restSeconds ?? ref.read<int>(defaultRestSecondsProvider);
  final notifier = ref.read(workoutControllerProvider.notifier);
  final pendingNotifier = ref.read(pendingActionsProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await notifier.confirmPlannedSet(
      workoutExerciseId: workoutExerciseId,
      plannedSetId: planned.id,
      weight: edited?.weight ?? shown.weight,
      reps: edited?.reps ?? shown.reps,
      rpe: edited?.rpe,
      isWarmup: edited?.isWarmup ?? false,
      restSeconds: restSeconds,
    );
    pendingNotifier.markTouched(workoutExerciseId);
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
    messenger.showSnackBar(SnackBar(content: Text('記錄組數失敗:$e')));
  }
}

/// 點開計畫組編輯。[weightUnset](沒有上次紀錄的 0 kg 計畫組)重量欄留空、
/// 存檔鈕要等輸入重量後才可按,避免誤記 0 kg。
Future<void> _editPlanned(
  BuildContext context,
  WidgetRef ref,
  String workoutExerciseId, {
  required PlannedSet planned,
  required ({double weight, int reps}) shown,
  required int setNumber,
  required String name,
  required bool weightUnset,
}) async {
  final result = await showAddSetSheet(
    context,
    exerciseName: name,
    setNumber: setNumber,
    initialWeight: weightUnset ? null : shown.weight,
    initialReps: shown.reps,
    initialRestSeconds: ref.read(defaultRestSecondsProvider),
    compact: true,
  );
  if (result == null || !context.mounted) return;
  await _confirmPlanned(context, ref, workoutExerciseId, planned: planned, shown: shown, name: name, edited: result);
}

/// 計畫組打勾:重量未定的一律開記組 sheet,其餘直接記。
Future<void> _tapPlanned(
  BuildContext context,
  WidgetRef ref,
  String workoutExerciseId, {
  required PlannedSet planned,
  required ({double weight, int reps}) shown,
  required int setNumber,
  required String name,
  required bool weightUnset,
}) {
  if (weightUnset) {
    return _editPlanned(
      context,
      ref,
      workoutExerciseId,
      planned: planned,
      shown: shown,
      setNumber: setNumber,
      name: name,
      weightUnset: true,
    );
  }
  return _confirmPlanned(context, ref, workoutExerciseId, planned: planned, shown: shown, name: name);
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({required this.workoutExerciseId});

  final String workoutExerciseId;

  Future<void> _editSet(BuildContext context, WidgetRef ref, WorkoutSet set, String name, int displayNumber) async {
    final result = await showAddSetSheet(
      context,
      exerciseName: name,
      setNumber: displayNumber,
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
    final pendingNotifier = ref.read(pendingActionsProvider.notifier);
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
      pendingNotifier.markTouched(workoutExerciseId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新組數失敗:$e')));
    }
  }

  /// 左滑刪組:畫面立即隱藏、顯示「復原」SnackBar,5 秒後才真刪(見
  /// workout_pending_actions.dart)。回 true＝讓 Dismissible 滑掉(同一個 frame 內
  /// 這列已被排除出清單)。
  Future<bool> _deleteSet(BuildContext context, WidgetRef ref, WorkoutSet set, int displayNumber) async {
    final notifier = ref.read(workoutControllerProvider.notifier);
    final exerciseId = workoutExerciseId;
    return ref
        .read(pendingActionsProvider.notifier)
        .scheduleDeleteSet(
          setId: set.id,
          workoutExerciseId: exerciseId,
          message: '已刪除第 $displayNumber 組',
          run: () => notifier.deleteSet(set.id, workoutExerciseId: exerciseId),
          messenger: ScaffoldMessenger.of(context),
        );
  }

  void _deleteExercise(BuildContext context, WidgetRef ref, String name) {
    final notifier = ref.read(workoutControllerProvider.notifier);
    final exerciseId = workoutExerciseId;
    ref
        .read(pendingActionsProvider.notifier)
        .scheduleDeleteExercise(
          workoutExerciseId: exerciseId,
          message: '已刪除 $name',
          run: () => notifier.removeExercise(exerciseId),
          messenger: ScaffoldMessenger.of(context),
        );
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
    // 「上次數字」:計畫組預填 + 標題下的上次成績一行。select 到該動作那一份,
    // 別的動作的歷史變動不會重建這張卡;載入中/失敗/沒歷史都是 null。
    final history = ref.watch(exerciseHistoryProvider.select((h) => h.value?.lastSetsByExerciseId[exercise.exerciseId]));
    final unit = ref.watch(weightUnitProvider);
    final lastPerformance = lastPerformanceText(history, unit);
    // 結算寫入中/放棄中/完成倒數中:不再接受記組/改組/刪組,避免寫進一筆正在結清的訓練。
    final editable = !ref.watch(_workoutBusyProvider);
    // 待刪的組:畫面已隱藏(DB 要等復原期結束才真刪),組號照「刪完重編」顯示。
    final deletedSetIds = ref.watch(pendingActionsProvider.select((p) => p.deletedSetIds));
    final sets = [
      for (final set in exercise.sets)
        if (!deletedSetIds.contains(set.id)) set,
    ];
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium),
                    if (lastPerformance != null)
                      Text(
                        lastPerformance,
                        key: Key('lastPerformance_${exercise.id}'),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: Key('exerciseMoreButton_${exercise.id}'),
                tooltip: '動作選項',
                icon: Icon(Icons.more_horiz, color: theme.colorScheme.onSurfaceVariant),
                enabled: editable,
                onSelected: (_) => _deleteExercise(context, ref, name),
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
                for (var i = 0; i < sets.length; i++)
                  SwipeableSetRow(
                    key: Key('setRow_${sets[i].id}'),
                    set: sets[i],
                    displayNumber: i + 1,
                    unit: unit,
                    enabled: editable,
                    onEdit: () => _editSet(context, ref, sets[i], name, i + 1),
                    onDelete: () => _deleteSet(context, ref, sets[i], i + 1),
                  ),
                for (var j = 0; j < data.planned.length; j++)
                  Builder(
                    key: Key('plannedSet_${data.planned[j].id}'),
                    builder: (context) {
                      final planned = data.planned[j];
                      final position = sets.length + j;
                      final shown = plannedDisplayValues(planned, history, position);
                      final weightUnset = plannedNeedsInput(planned, history);
                      return PlannedSetRow(
                        planned: PlannedSet(id: planned.id, weight: shown.weight, reps: shown.reps),
                        setNumber: position + 1,
                        unit: unit,
                        enabled: editable,
                        weightUnset: weightUnset,
                        onConfirm: () => _tapPlanned(
                          context,
                          ref,
                          workoutExerciseId,
                          planned: planned,
                          shown: shown,
                          setNumber: position + 1,
                          name: name,
                          weightUnset: weightUnset,
                        ),
                        onEdit: () => _editPlanned(
                          context,
                          ref,
                          workoutExerciseId,
                          planned: planned,
                          shown: shown,
                          setNumber: position + 1,
                          name: name,
                          weightUnset: weightUnset,
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
  // 確認框開啟到放棄寫入結束這段期間,待刪計時一律暫停:否則到期的真刪會打在
  // 正在被丟棄的草稿上、跳出「刪除組數失敗」。取消或放棄失敗 → 恢復計時;成功 → reset。
  final pendingNotifier = ref.read(pendingActionsProvider.notifier)..pauseDeleteTimers();
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
  if (confirmed != true || !context.mounted) {
    pendingNotifier.resumeDeleteTimers();
    return;
  }

  // 放棄成功後 state 變 idle,這個 widget 隨即被拆掉——離開路徑與之後要用的
  // 東西一律先抓好,成功後不再碰這個 context/ref。
  final exit = WorkoutExit.of(context);
  final restTimer = ref.read(restTimerControllerProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(workoutControllerProvider.notifier).abandonWorkout();
  } catch (e) {
    pendingNotifier.resumeDeleteTimers();
    messenger.showSnackBar(SnackBar(content: Text('放棄訓練失敗:$e')));
    return;
  }
  restTimer.skip();
  pendingNotifier.reset();
  exit.toDashboard();
}

/// 按下「完成」:先在這裡把之後要用的東西全抓好(完成後 state 變 idle、這個 widget
/// 會被拆掉,延遲後的 callback 不得再碰 context/ref),交給 pending notifier 倒數
/// [kCompleteUndoWindow];沒按「復原」就一定會執行完成(見 workout_pending_actions.dart)。
void _completeWorkout(BuildContext context, WidgetRef ref) {
  final exit = WorkoutExit.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final restTimer = ref.read(restTimerControllerProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(workoutControllerProvider.notifier);

  /// 回 true＝已完成(含冪等 no-op);false＝失敗(已提示、草稿保留)。
  Future<bool> perform() async {
    final WorkoutCompletionOutcome outcome;
    try {
      outcome = await controller.completeWorkout();
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('完成訓練失敗,訓練已保留在這台裝置,恢復網路後再按一次「完成訓練」')),
      );
      return false;
    }
    // WorkoutCompletionNoOp:已經完成過了(冪等),不重複彈 summary。
    if (outcome is! WorkoutCompleted) return true;
    restTimer.skip();
    if (navigator.mounted) {
      await showWorkoutSummarySheet(navigator.context, outcome.workout, outcome.newPersonalRecordCount);
    }
    exit.toDashboard();
    return true;
  }

  ref.read(pendingActionsProvider.notifier).beginComplete(messenger: messenger, perform: perform);
}

/// 固定在底部的主按鈕:全寬「記下一組」,作用於「目前動作」(見
/// [resolveNextSetTarget])。沒有任何動作時變「新增動作」。
class _BottomActions extends ConsumerWidget {
  const _BottomActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftExercises = ref.watch(
      workoutControllerProvider.select((s) => s.value?.draft?.exercises ?? const <WorkoutExercise>[]),
    );
    final plannedSets = ref.watch(workoutControllerProvider.select((s) => s.value?.plannedSets ?? const {}));
    final pending = ref.watch(pendingActionsProvider);
    final busy = ref.watch(_workoutBusyProvider);
    final unit = ref.watch(weightUnitProvider);
    final colors = Theme.of(context).colorScheme;

    final visible = visibleExercisesOf(draftExercises, pending);
    final target = resolveNextSetTarget(visibleExercises: visible, plannedSets: plannedSets, pending: pending);
    final exercise = target.exercise;
    final planned = target.planned;

    // 標籤與動作:無動作＝新增動作;有剩餘計畫組＝完成下一組;否則＝記下一組。
    String label;
    VoidCallback? onPressed;
    if (exercise == null) {
      label = '新增動作';
      onPressed = () => pickAndAddExercise(context, ref);
    } else {
      final name = _exerciseName(exercise);
      if (planned == null) {
        label = '記下一組・$name';
        onPressed = () => recordSet(context, ref, exercise.id);
      } else {
        final history = ref.watch(
          exerciseHistoryProvider.select((h) => h.value?.lastSetsByExerciseId[exercise.exerciseId]),
        );
        final position = exercise.sets.length;
        final shown = plannedDisplayValues(planned, history, position);
        final weightUnset = plannedNeedsInput(planned, history);
        final weightText = weightUnset ? '—' : trimZeros(kgToDisplay(shown.weight, unit));
        label = '完成下一組・$name $weightText ${unitSuffix(unit)} × ${shown.reps}';
        onPressed = () => _tapPlanned(
          context,
          ref,
          exercise.id,
          planned: planned,
          shown: shown,
          setNumber: position + 1,
          name: name,
          weightUnset: weightUnset,
        );
      }
    }

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
              key: const Key('recordNextSetButton'),
              onPressed: busy ? null : onPressed,
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
    );
  }
}
