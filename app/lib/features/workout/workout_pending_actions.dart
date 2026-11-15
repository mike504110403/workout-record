// 進行中訓練頁的「延遲執行＋復原」:刪組、刪動作、完成訓練都不立即動 DB,
// 先在畫面上生效、給一段可反悔的時間,到時才真的呼叫 [WorkoutController]。
//
// 為什麼不是「刪了再加回」:repository 刪除後會把剩餘組重編成 1..N、動作
// 重編 orderIndex,而 `updateSet` 不改 setNumber、介面也沒有改 orderIndex 的
// 方法;刪了再加回原位會重號且無唯一鍵擋、靜默寫壞資料。所以復原期結束前
// DB 一律不動。
//
// 設計重點:
// - 計時用自己的 [Timer],不依賴 `SnackBar.closed`(無障礙模式下帶 action 的
//   SnackBar 不會自動消失)。SnackBar 一律 `persist: false` 且 duration 等於
//   計時長度;計時觸發後按「復原」一律 no-op。
// - provider **不 autoDispose**:收起訓練頁(widget 被拆)不中斷計時;到時呼叫的
//   controller、messenger 都在按下當下抓好。「延遲後不得再碰」指發起端的
//   BuildContext/WidgetRef;這裡 notifier 用自己的 Ref。
// - 狀態以草稿 id 分區,只活在本場訓練:完成成功/放棄/草稿換成另一場時清空。
// - 同檔另存「目前動作」的記憶(最後一次記組/打勾/編輯的動作)與「本場曾有計畫組
//   的動作」集合,供底部主按鈕用;都不落地(重啟後退回用資料推算)。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ScaffoldMessengerState, SnackBar, SnackBarAction, Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/workout.dart';
import 'planned_sets_store.dart' show PlannedSet;
import 'workout_controller.dart';

/// 刪組/刪動作的復原時間。
const Duration kDeleteUndoWindow = Duration(seconds: 5);

/// 完成訓練的復原時間(從「即將完成訓練」SnackBar 顯示當下起算)。
const Duration kCompleteUndoWindow = Duration(seconds: 4);

/// 完成訓練的延遲流程階段。
enum CompletePhase {
  idle,

  /// 「即將完成訓練」倒數中,可復原。
  waiting,

  /// 倒數結束:flush 待刪項目 → `completeWorkout` 執行中,不可復原。
  running,
}

@immutable
class PendingActionsState {
  const PendingActionsState({
    this.draftId,
    this.deletedSetIds = const {},
    this.deletedExerciseIds = const {},
    this.completePhase = CompletePhase.idle,
    this.lastTouchedExerciseId,
    this.plannedExerciseIds = const {},
  });

  /// 這份狀態屬於哪一場草稿;null＝目前沒有進行中的訓練。
  final String? draftId;

  /// 畫面上已隱藏、尚未真刪的組 id。
  final Set<String> deletedSetIds;

  /// 畫面上已隱藏、尚未真刪的動作 id(workoutExerciseId)。
  final Set<String> deletedExerciseIds;
  final CompletePhase completePhase;

  /// 最後一次記組/打勾/編輯組成功的動作(workoutExerciseId);底部主按鈕的
  /// 「目前動作」。Drift 的 DateTime 只存到秒,同秒的 updatedAt 分不出先後,
  /// 所以另外記;沒有值(例如 App 重啟後)才退回用 updatedAt 推算。
  final String? lastTouchedExerciseId;

  /// 本場曾經有計畫組的動作 id。計畫組全做完後 plannedSets 的 key 會被移除,
  /// 光看 plannedSets 分不出「做完了」與「本來就是自由動作」。
  final Set<String> plannedExerciseIds;

  /// 完成流程進行中(倒數/執行):卡片、底部主鈕、完成鈕、選單、新增動作都停用。
  bool get completeBusy => completePhase != CompletePhase.idle;

  PendingActionsState copyWith({
    Set<String>? deletedSetIds,
    Set<String>? deletedExerciseIds,
    CompletePhase? completePhase,
    String? lastTouchedExerciseId,
    Set<String>? plannedExerciseIds,
  }) => PendingActionsState(
    draftId: draftId,
    deletedSetIds: deletedSetIds ?? this.deletedSetIds,
    deletedExerciseIds: deletedExerciseIds ?? this.deletedExerciseIds,
    completePhase: completePhase ?? this.completePhase,
    lastTouchedExerciseId: lastTouchedExerciseId ?? this.lastTouchedExerciseId,
    plannedExerciseIds: plannedExerciseIds ?? this.plannedExerciseIds,
  );
}

/// 一筆待真刪的項目。
class _PendingDelete {
  _PendingDelete({
    this.setId,
    this.exerciseId,
    this.parentExerciseId,
    required this.run,
    required this.errorPrefix,
    required this.messenger,
  });

  /// 刪組時的組 id;刪動作時為 null。
  final String? setId;

  /// 刪動作時的動作 id;刪組時為 null。
  final String? exerciseId;

  /// 刪組時該組所屬動作(flush 時動作也待刪就直接丟棄這筆)。
  final String? parentExerciseId;
  final Future<void> Function() run;
  final String errorPrefix;
  final ScaffoldMessengerState messenger;
  Timer? timer;

  /// 已開始真刪(計時到或被 flush)。進行中就不能再復原。
  Future<bool>? running;

  /// 這筆的「復原」SnackBar 是否已經關掉(計時觸發時只在還沒關時才主動收)。
  bool snackClosed = false;
}

class PendingActionsController extends Notifier<PendingActionsState> {
  final List<_PendingDelete> _deletes = [];
  Timer? _completeTimer;
  bool _completeSnackClosed = true;
  bool _disposed = false;

  @override
  PendingActionsState build() {
    ref.onDispose(() {
      _disposed = true;
      for (final d in _deletes) {
        d.timer?.cancel();
      }
      _deletes.clear();
      _completeTimer?.cancel();
      _completeTimer = null;
    });
    // 草稿換場/結束:舊場的待處理項目作廢(完成成功、放棄也走這裡)。同一場:把
    // 新出現的計畫組動作併進「曾有計畫組」集合。
    ref.listen(workoutControllerProvider, (_, next) {
      final flow = next.value;
      if (flow?.draft?.id != state.draftId) {
        _resetFor(flow);
        return;
      }
      if (flow == null) return;
      final fresh = flow.plannedSets.keys.where((k) => !state.plannedExerciseIds.contains(k));
      if (fresh.isNotEmpty) {
        state = state.copyWith(plannedExerciseIds: {...state.plannedExerciseIds, ...fresh});
      }
    });
    return _initialStateFor(ref.read(workoutControllerProvider).value);
  }

  PendingActionsState _initialStateFor(WorkoutFlowState? flow) {
    final draft = flow?.draft;
    if (flow == null || draft == null) return const PendingActionsState();
    return PendingActionsState(draftId: draft.id, plannedExerciseIds: {...flow.plannedSets.keys});
  }

  String? get _currentDraftId => ref.read(workoutControllerProvider).value?.draft?.id;

  // MARK: - 目前動作

  /// 記組/打勾/編輯組成功後呼叫,把 [workoutExerciseId] 記成目前動作。
  void markTouched(String workoutExerciseId) {
    if (_disposed || state.draftId == null) return;
    state = state.copyWith(lastTouchedExerciseId: workoutExerciseId);
  }

  // MARK: - 刪除

  /// 隱藏 [setId] 並在 [kDeleteUndoWindow] 後呼叫 [run] 真刪;期間可從 SnackBar 復原。
  /// [run]、[messenger] 都由呼叫端在按下當下抓好。
  /// 回傳是否真的排程了(完成倒數中、草稿不符等情況不排程回 false;呼叫端據此決定
  /// 要不要讓 Dismissible 滑掉)。
  bool scheduleDeleteSet({
    required String setId,
    required String workoutExerciseId,
    required String message,
    required Future<void> Function() run,
    required ScaffoldMessengerState messenger,
  }) => _schedule(
    entry: _PendingDelete(
      setId: setId,
      parentExerciseId: workoutExerciseId,
      run: run,
      errorPrefix: '刪除組數失敗',
      messenger: messenger,
    ),
    message: message,
  );

  bool scheduleDeleteExercise({
    required String workoutExerciseId,
    required String message,
    required Future<void> Function() run,
    required ScaffoldMessengerState messenger,
  }) => _schedule(
    entry: _PendingDelete(
      exerciseId: workoutExerciseId,
      run: run,
      errorPrefix: '刪除動作失敗',
      messenger: messenger,
    ),
    message: message,
  );

  bool _schedule({required _PendingDelete entry, required String message}) {
    if (_disposed || state.draftId == null || _currentDraftId != state.draftId) return false;
    // 完成倒數/執行中不接受新的待刪(與 _undo 一致:這段時間待刪計時是暫停的)。
    if (state.completePhase != CompletePhase.idle) return false;
    _deletes.add(entry);
    final setId = entry.setId;
    final exerciseId = entry.exerciseId;
    state = state.copyWith(
      deletedSetIds: setId == null ? null : {...state.deletedSetIds, setId},
      deletedExerciseIds: exerciseId == null ? null : {...state.deletedExerciseIds, exerciseId},
    );
    _armDeleteTimer(entry);
    entry.snackClosed = false;
    final messenger = entry.messenger;
    if (!messenger.mounted) return true;
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: kDeleteUndoWindow,
        persist: false,
        action: SnackBarAction(label: '復原', onPressed: () => _undo(entry)),
      ),
    );
    unawaited(controller.closed.then((_) => entry.snackClosed = true));
    return true;
  }

  void _armDeleteTimer(_PendingDelete entry) {
    entry.timer?.cancel();
    entry.timer = Timer(kDeleteUndoWindow, () {
      // 計時到:SnackBar 還在(例如無障礙模式不會自己消失)就收掉,再真刪。
      if (!entry.snackClosed && entry.messenger.mounted) entry.messenger.hideCurrentSnackBar();
      unawaited(_execute(entry));
    });
  }

  void _undo(_PendingDelete entry) {
    // 已開始真刪(計時到)→ 來不及了;完成倒數中(計時暫停、SnackBar 已被取代)
    // 或已被 flush/清空 → 不在清單裡或不該動。
    if (_disposed || entry.running != null || !_deletes.contains(entry)) return;
    if (state.completePhase != CompletePhase.idle) return;
    entry.timer?.cancel();
    _release(entry);
  }

  /// 真刪。失敗 → 恢復顯示並浮出錯誤;**永不拋例外**(Timer callback 裡不能漏)。
  Future<bool> _execute(_PendingDelete entry) {
    final existing = entry.running;
    if (existing != null) return existing;
    entry.timer?.cancel();
    return entry.running = _executeInner(entry);
  }

  Future<bool> _executeInner(_PendingDelete entry) async {
    try {
      await entry.run();
      _release(entry);
      return true;
    } catch (e) {
      _release(entry);
      _showSnack(entry.messenger, SnackBar(content: Text('${entry.errorPrefix}:$e')));
      return false;
    }
  }

  /// 從待刪清單與畫面隱藏集合移除(真刪成功＝資料已消失;失敗/復原＝恢復顯示)。
  void _release(_PendingDelete entry) {
    _deletes.remove(entry);
    if (_disposed) return;
    final setId = entry.setId;
    final exerciseId = entry.exerciseId;
    state = state.copyWith(
      deletedSetIds: setId == null ? null : ({...state.deletedSetIds}..remove(setId)),
      deletedExerciseIds: exerciseId == null ? null : ({...state.deletedExerciseIds}..remove(exerciseId)),
    );
  }

  /// 暫停所有待刪計時(項目仍隱藏):進入完成倒數、放棄確認/寫入期間用。
  /// 之後必須 [resumeDeleteTimers](放棄成功則是 [reset])。
  void pauseDeleteTimers() {
    for (final d in _deletes) {
      if (d.running == null) d.timer?.cancel();
    }
  }

  /// 恢復待刪計時:重新計 [kDeleteUndoWindow],到期真刪(不再顯示復原 SnackBar)。
  void resumeDeleteTimers() {
    for (final d in _deletes) {
      if (d.running == null) {
        d.snackClosed = true;
        _armDeleteTimer(d);
      }
    }
  }

  /// 完成前 flush:先組後動作;所屬動作也待刪的組直接丟棄(刪動作會連帶刪組,
  /// 避免本機草稿找不到而轉打雲端 RPC);遇到「刪除中」的等它完成、不重刪。
  /// 任一筆失敗就中止並回 false(該項已恢復顯示、已浮出錯誤)。
  Future<bool> _flushForComplete() async {
    final pendingExercises = {
      for (final d in _deletes)
        if (d.exerciseId != null) d.exerciseId!,
    };
    for (final d in List.of(_deletes)) {
      if (d.setId != null && d.running == null && pendingExercises.contains(d.parentExerciseId)) {
        d.timer?.cancel();
        _release(d);
      }
    }
    final ordered = [
      ..._deletes.where((d) => d.setId != null),
      ..._deletes.where((d) => d.exerciseId != null),
    ];
    for (final entry in ordered) {
      if (!await _execute(entry)) return false;
      if (_disposed) return false;
    }
    return true;
  }

  // MARK: - 完成訓練

  int _visibleSetCount() {
    final exercises = ref.read(workoutControllerProvider).value?.draft?.exercises ?? const <WorkoutExercise>[];
    return totalSetCountOf(visibleExercisesOf(exercises, state));
  }

  /// 按下「完成訓練」:排除待刪後 0 組就擋下;否則立刻鎖住(防連點)、暫停待刪計時、
  /// 顯示「即將完成訓練」(可復原)並開始 [kCompleteUndoWindow] 倒數;沒復原就先
  /// flush 待刪項目再呼叫 [perform]。
  ///
  /// **契約**:只要沒按復原就一定會完成——不依賴 SnackBar 是否還在、也不依賴發起的
  /// widget 是否還 mounted。[perform] 由呼叫端組好(只用按下當下抓好的東西),
  /// 回傳 true＝已完成(或冪等 no-op)、false＝失敗(它自己已提示),不得拋例外。
  void beginComplete({required ScaffoldMessengerState messenger, required Future<bool> Function() perform}) {
    if (_disposed || state.completePhase != CompletePhase.idle) return;
    if (_visibleSetCount() == 0) {
      _showSnack(messenger, const SnackBar(content: Text('沒有任何組，無法完成')));
      return;
    }
    state = state.copyWith(completePhase: CompletePhase.waiting);
    pauseDeleteTimers();
    if (messenger.mounted) {
      messenger.hideCurrentSnackBar();
      _completeSnackClosed = false;
      final controller = messenger.showSnackBar(
        SnackBar(
          content: const Text('即將完成訓練'),
          duration: kCompleteUndoWindow,
          persist: false,
          action: SnackBarAction(label: '復原', onPressed: cancelComplete),
        ),
      );
      unawaited(controller.closed.then((_) => _completeSnackClosed = true));
    }
    _completeTimer = Timer(kCompleteUndoWindow, () => unawaited(_runComplete(messenger, perform)));
  }

  /// 倒數中按「復原」。倒數已結束(執行中)就來不及了。
  void cancelComplete() {
    if (_disposed || state.completePhase != CompletePhase.waiting) return;
    _completeTimer?.cancel();
    _completeTimer = null;
    state = state.copyWith(completePhase: CompletePhase.idle);
    resumeDeleteTimers();
  }

  Future<void> _runComplete(ScaffoldMessengerState messenger, Future<bool> Function() perform) async {
    _completeTimer = null;
    if (_disposed) return;
    state = state.copyWith(completePhase: CompletePhase.running);
    if (!_completeSnackClosed && messenger.mounted) messenger.hideCurrentSnackBar();

    if (!await _flushForComplete()) {
      // 有項目刪不掉:已恢復顯示並提示錯誤,不往下完成;其餘待刪項目重新計時。
      if (_disposed) return;
      state = state.copyWith(completePhase: CompletePhase.idle);
      resumeDeleteTimers();
      return;
    }

    var completed = false;
    try {
      completed = await perform();
    } catch (e) {
      // perform 約定自己處理失敗;這裡只是不讓例外漏成 uncaught async error。
      _showSnack(messenger, SnackBar(content: Text('完成訓練失敗:$e')));
    }
    if (_disposed) return;
    if (completed) {
      reset();
    } else if (state.completePhase == CompletePhase.running) {
      // 失敗:草稿保留、解除等待,使用者可再按一次完成。
      state = state.copyWith(completePhase: CompletePhase.idle);
    }
  }

  // MARK: - 清空

  /// 清空本場所有待處理狀態並取消計時(完成成功、放棄)。不真刪任何項目——
  /// 放棄是整張草稿丟掉,不需要。
  void reset() => _resetFor(ref.read(workoutControllerProvider).value);

  void _resetFor(WorkoutFlowState? flow) {
    for (final d in _deletes) {
      d.timer?.cancel();
    }
    _deletes.clear();
    _completeTimer?.cancel();
    _completeTimer = null;
    if (_disposed) return;
    state = _initialStateFor(flow);
  }

  void _showSnack(ScaffoldMessengerState messenger, SnackBar snackBar) {
    if (!messenger.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }
}

/// 非 autoDispose:收起訓練頁不會中斷延遲刪除/延遲完成的計時。
final pendingActionsProvider = NotifierProvider<PendingActionsController, PendingActionsState>(
  PendingActionsController.new,
);

// MARK: - 排除待刪項目的視圖

/// [exercise] 排除待刪組之後的組(保持原順序)。
List<WorkoutSet> visibleSetsOf(WorkoutExercise exercise, PendingActionsState pending) {
  if (pending.deletedSetIds.isEmpty) return exercise.sets;
  return [
    for (final s in exercise.sets)
      if (!pending.deletedSetIds.contains(s.id)) s,
  ];
}

/// 排除待刪動作與待刪組之後的動作清單(統計、目前動作推算用)。
List<WorkoutExercise> visibleExercisesOf(Iterable<WorkoutExercise> exercises, PendingActionsState pending) {
  return [
    for (final e in exercises)
      if (!pending.deletedExerciseIds.contains(e.id))
        if (pending.deletedSetIds.isEmpty) e else e.copyWith(sets: visibleSetsOf(e, pending)),
  ];
}

/// 真實組總數(含暖身,與 `WorkoutFlowState.totalSetCount` 同口徑)。
int totalSetCountOf(Iterable<WorkoutExercise> exercises) =>
    exercises.fold<int>(0, (sum, e) => sum + e.sets.length);

/// 畫面統計(容量、組數;暖身組不計),排除待刪項目。
final visibleTotalsProvider = Provider<({double volume, int sets})>((ref) {
  final exercises = ref.watch(workoutControllerProvider.select((s) => s.value?.draft?.exercises)) ?? const [];
  final pending = ref.watch(pendingActionsProvider);
  final visible = visibleExercisesOf(exercises, pending);
  return (volume: nonWarmupTotalVolume(visible), sets: nonWarmupTotalSets(visible));
});

// MARK: - 底部主按鈕的目標

/// 底部主按鈕作用的對象。[exercise] 為 null＝草稿沒有任何動作(按鈕＝新增動作);
/// [planned] 非 null＝該動作還有計畫組,這是第一個剩餘的(按鈕＝完成下一組)。
@immutable
class NextSetTarget {
  const NextSetTarget({this.exercise, this.planned});

  final WorkoutExercise? exercise;
  final PlannedSet? planned;
}

/// 推算「目前動作」與主按鈕目標。全由資料推算,不另存狀態(除了
/// [PendingActionsState.lastTouchedExerciseId] 這個同秒平手的補充):
/// 1. 目前動作＝最後一次記組/打勾/編輯的動作;沒有記憶(例如 App 重啟)就取
///    `updatedAt` 最新的那一組所屬動作(平手取清單中較後面的);草稿還沒有任何組＝
///    第一個動作。待刪項目一律排除([visibleExercises] 已排除)。
/// 2. 自動前進:目前動作「本場曾有計畫組」且已沒有剩餘計畫組,而清單中它之後(含
///    從頭繞回)有動作還有剩餘計畫組 → 改指向那個動作。自由動作不前進。
NextSetTarget resolveNextSetTarget({
  required List<WorkoutExercise> visibleExercises,
  required Map<String, List<PlannedSet>> plannedSets,
  required PendingActionsState pending,
}) {
  if (visibleExercises.isEmpty) return const NextSetTarget();
  var currentIndex = -1;
  final touched = pending.lastTouchedExerciseId;
  if (touched != null) currentIndex = visibleExercises.indexWhere((e) => e.id == touched);
  if (currentIndex < 0) {
    DateTime? latest;
    for (var i = 0; i < visibleExercises.length; i++) {
      for (final s in visibleExercises[i].sets) {
        if (latest == null || !s.updatedAt.isBefore(latest)) {
          latest = s.updatedAt;
          currentIndex = i;
        }
      }
    }
  }
  if (currentIndex < 0) currentIndex = 0;

  PlannedSet? firstRemaining(WorkoutExercise e) {
    final list = plannedSets[e.id];
    return list == null || list.isEmpty ? null : list.first;
  }

  final current = visibleExercises[currentIndex];
  final own = firstRemaining(current);
  if (own != null || !pending.plannedExerciseIds.contains(current.id)) {
    return NextSetTarget(exercise: current, planned: own);
  }
  for (var step = 1; step < visibleExercises.length; step++) {
    final candidate = visibleExercises[(currentIndex + step) % visibleExercises.length];
    final next = firstRemaining(candidate);
    if (next != null) return NextSetTarget(exercise: candidate, planned: next);
  }
  return NextSetTarget(exercise: current);
}
