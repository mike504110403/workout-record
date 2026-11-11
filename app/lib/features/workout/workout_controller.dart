// 訓練核心流狀態機。對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/ViewModels/WorkoutViewModel.swift`,
// 但採波 3 拍板的刻意差異:進行中訓練 Drift 草稿寫穿(而非 iOS 的純記憶體)
// ——見 `.claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md`。
//
// **單一事實來源是 DB,不是本地鏡像狀態**:每個變動方法(addExercise/
// addSet/updateSet/deleteSet/...)寫入 Drift 後,一律重新
// `WorkoutRepository.fetchById` 整包草稿寫回 [state],不在 controller 端
// 自行維護一份可能與 DB 失準的鏡像物件。換來的代價是每個操作多一次
// SELECT,但對這個資料量(單一使用者、單次訓練最多幾十組)完全不是效能
// 瓶頸,換到的是「重啟後看到的畫面 == 這裡的 state」的簡單可驗證性。
//
// **序列化寫入**:所有變動方法都包在 [_synchronized] 之後才真正執行——
// 保證同一個 controller instance 上的操作依呼叫順序嚴格序列化執行,不會
// 並發交錯。這是矩陣裡「開始訓練連點兩下→只建一筆草稿」「完成與放棄互斥」
// 等情境的根本防線:UI 層的 loading 旗標([WorkoutFlowState.isCompleting]/
// [isAbandoning])是第一道防線(擋住使用者手指再次點擊),這裡的序列化鎖
// 是第二道、測試也直接命中的防線(即使繞過 UI 直接連續呼叫 controller 方法
// 也一樣安全)。
import '../settings/preferences/one_rm_formula_preference.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/uuid.dart';
import '../../data/models/exercise.dart';
import '../../data/models/personal_record.dart';
import '../../data/models/workout.dart';
import '../../data/providers.dart';
import '../auth/session_controller.dart';
import 'exercise_history.dart';
import 'one_rm_calculator.dart';
import 'planned_sets_store.dart';
import 'templates/applied_template.dart';
import 'workout_ui_shared.dart';
import '../auth/resolve_user_id.dart';

/// 訓練核心流的狀態。[draft] 為 null 代表沒有進行中的訓練(顯示開始畫面);
/// 非 null 時 `draft.endedAt` 必為 null(進行中草稿)。
class WorkoutFlowState {
  const WorkoutFlowState({
    this.draft,
    this.plannedSets = const {},
    this.isCompleting = false,
    this.isAbandoning = false,
  });

  final Workout? draft;

  /// 計畫組(模板帶入、尚未打勾),key 是 workoutExerciseId。**不是**真實
  /// `WorkoutSet`、不進 DB——存在本機附屬儲存([PlannedSetsStore]),見
  /// planned_sets_store.dart 檔頭。打勾([WorkoutController.confirmPlannedSet])
  /// 才變成真實組並從這裡移除。
  final Map<String, List<PlannedSet>> plannedSets;

  /// 完成訓練寫入中——UI 用來 disable「放棄」按鈕(矩陣:完成與放棄互斥,
  /// 結算進行中不可放棄)與「完成訓練」按鈕本身(避免連點觸發第二次結算,
  /// controller 層的序列化鎖是真正的防線,這個旗標只是 UI 提示)。
  final bool isCompleting;

  /// 放棄訓練寫入中——UI 用來 disable「完成訓練」/「放棄」按鈕。
  final bool isAbandoning;

  bool get isActive => draft != null;

  /// 草稿裡真實組的總數(含暖身)。0 組時不能完成訓練(沒有內容可存)。
  int get totalSetCount => draft?.exercises.fold<int>(0, (sum, e) => sum + e.sets.length) ?? 0;
}

/// [WorkoutController.completeWorkout] 的結果。冪等設計的關鍵型別——
/// 已經完成過一次之後再呼叫一次(矩陣:完成訓練連點/完成後再完成),回傳
/// [WorkoutCompletionNoOp] 而不是拋錯或重複結算,呼叫端(UI)依型別決定
/// 要不要彈 summary 報告。
sealed class WorkoutCompletionOutcome {
  const WorkoutCompletionOutcome();
}

class WorkoutCompleted extends WorkoutCompletionOutcome {
  const WorkoutCompleted({
    required this.workout,
    required this.newPersonalRecordCount,
  });

  /// 完成後的訓練(`endedAt` 非 null,統計欄位已由
  /// `WorkoutRepository.completeWorkout` 重新計算)。
  final Workout workout;

  /// 這次訓練新創造的 PR 數量(供 summary 報告顯示)。
  final int newPersonalRecordCount;
}

class WorkoutCompletionNoOp extends WorkoutCompletionOutcome {
  const WorkoutCompletionNoOp();
}

class WorkoutController extends AsyncNotifier<WorkoutFlowState> {
  Future<void> _lock = Future.value();

  /// 序列化執行:回傳的 Future 在前一個排入佇列的操作完成後才會開始執行
  /// [action]。見檔案開頭「序列化寫入」說明。用 [Completer] 標記「這個操作
  /// 做完了(不管成功或失敗)」,不讓單一操作失敗就讓 `_lock` 這條鏈本身
  /// 進入 completed-with-error 狀態(那樣後續所有排隊的操作都會被同一個
  /// 錯誤直接短路、永遠執行不到)——真正的錯誤還是從 [action] 本身的
  /// Future 往外拋給呼叫端。
  Future<T> _synchronized<T>(Future<T> Function() action) {
    final previousTurn = _lock;
    final doneWithThisTurn = Completer<void>();
    _lock = doneWithThisTurn.future;
    return previousTurn.then((_) async {
      try {
        return await action();
      } finally {
        doneWithThisTurn.complete();
      }
    });
  }

  @override
  Future<WorkoutFlowState> build() async {
    // 換帳號時歸零(對照 dashboard_controller/templates_controller 既有
    // 慣例)。刻意不在這裡自動接手上一個 session 遺留的草稿——是否要接手
    // 由 UI 呼叫 [checkForRecoverableDraft] + [resumeDraft] 明確決定(見
    // 這兩個方法的文件),build() 一律從乾淨的 idle 狀態開始。
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    // 計畫組附屬儲存的 GC(換帳號/刪帳號後留下的舊 key)。排進序列化鎖,
    // 保證比之後的開始訓練先跑完——不會把剛寫入的計畫組當成舊 key 刪掉。
    // 不 await:build 要立刻回 idle,GC 失敗(離線查不到草稿)也不影響任何事。
    unawaited(_synchronized(_gcPlannedSets));
    return const WorkoutFlowState();
  }

  PlannedSetsStore get _plannedStore => ref.read(plannedSetsStoreProvider);

  /// 刪掉不屬於「目前使用者草稿」的計畫組 key。只能在 [_synchronized] 內呼叫。
  /// 查不到使用者(未登入)時不動——沒有依據判斷哪些 key 是舊的。
  Future<void> _gcPlannedSets({Workout? knownDraft, bool draftKnown = false}) async {
    try {
      final String? keepId;
      if (draftKnown) {
        keepId = knownDraft?.id;
      } else {
        final userId = await _resolveUserId();
        if (userId == null) return;
        keepId = (await ref.read(workoutRepositoryProvider).fetchDraft(userId))?.id;
      }
      await _plannedStore.removeAllExcept(keepId);
    } catch (_) {
      // best-effort:下次 build/草稿檢查再清。
    }
  }

  /// 接手 [draft] 進 [state],連同它在附屬儲存裡的計畫組(App 重開續訓)。
  /// 計畫組只保留草稿裡仍存在的動作(以 workoutExerciseId 比對)——動作已被
  /// 刪掉的計畫組沒有意義。不依真實組數裁切:打勾時計畫組已從附屬儲存移除
  /// ([confirmPlannedSet]),剩下的就是還沒做的。
  WorkoutFlowState _flowFor(Workout? draft) {
    if (draft == null) return const WorkoutFlowState();
    Map<String, List<PlannedSet>> stored;
    try {
      stored = _plannedStore.read(draft.id);
    } catch (_) {
      stored = const {};
    }
    final exerciseIds = {for (final e in draft.exercises) e.id};
    return WorkoutFlowState(
      draft: draft,
      plannedSets: {
        for (final entry in stored.entries)
          if (exerciseIds.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  Future<String?> _resolveUserId() => resolveSessionUserId(ref);

  Future<String> _requireUserId() async {
    final userId = await _resolveUserId();
    if (userId == null) {
      throw StateError(
        'WorkoutController: 無法解析目前使用者 userId'
        '(session 沒有已登入的 appleUserId,或 UserRepository.getById 查無此人)',
      );
    }
    return userId;
  }

  // MARK: - 重啟恢復

  /// 查詢目前使用者是否有未完成的訓練草稿(進入 workout tab 或 App 啟動後
  /// 第一次呼叫)。**不會**改變 [state]——是否接手這筆草稿,由 UI 依使用者
  /// 在「繼續上次訓練 / 放棄」對話框的選擇呼叫 [resumeDraft] 或
  /// [discardRecoverableDraft] 決定。
  Future<Workout?> checkForRecoverableDraft() => _synchronized(() async {
    final userId = await _resolveUserId();
    if (userId == null) return null;
    final draft = await ref.read(workoutRepositoryProvider).fetchDraft(userId);
    await _gcPlannedSets(knownDraft: draft, draftKnown: true);
    return draft;
  });

  /// 使用者選擇「繼續上次訓練」:把草稿接手進 [state](動作/組/起始時間
  /// 全部照 DB 內容還原——duration 顯示由 UI 用 `draft.startedAt` 與現在
  /// 時間現算,不需要額外欄位,見 workout_in_progress_view.dart)。
  ///
  /// 接手前驗證 [workoutId] 確實還是「進行中」(`endedAt == null`)且屬於
  /// 目前登入的使用者([workout.userId] 相符)——`checkForRecoverableDraft`
  ///
  /// **與 [discardRecoverableDraft] 的守衛不對稱是刻意的**:兩者的
  /// [workoutId] 都來自同一次 `checkForRecoverableDraft` 呼叫(已經用目前
  /// userId 過濾過),理論上不需要再驗一次;這裡仍多驗證 userId,是因為
  /// 「接手」的後果是把資料寫進 [state] 讓使用者以為自己在編輯自己的
  /// 訓練——如果 async 空窗期間(對話框等使用者確認的那段時間)真的換了
  /// 帳號,接手到別人的草稿是嚴重錯誤,值得多一道防線;[discardRecoverableDraft]
  /// 呼叫的 [WorkoutRepository.discardDraft] 本身已有 `endedAt IS NULL`
  /// 結構守衛,刪錯的代價(頂多是一次無效的 no-op)遠低於接手錯資料,不需要
  /// 對稱地補 userId 檢查。
  /// 與這裡的呼叫之間有一段 UI 對話框等待使用者確認的空窗期,理論上不會
  /// 有東西在這段期間把草稿結清或換帳號,但驗證失敗時安全地 no-op(不接手
  /// 一筆已經不是「這個使用者的進行中草稿」的資料),好過信任呼叫端傳進來
  /// 的 id 一定還有效。
  Future<void> resumeDraft(String workoutId) => _synchronized(() async {
    if (state.value?.draft != null) return;
    final userId = await _resolveUserId();
    if (userId == null) return;
    final workout = await ref
        .read(workoutRepositoryProvider)
        .fetchById(workoutId);
    if (workout == null) return;
    if (workout.endedAt != null || workout.userId != userId) return;
    state = AsyncData(_flowFor(workout));
  });

  /// 使用者選擇「放棄」上次未完成的草稿:直接刪除,不接手進 [state]。不像
  /// [resumeDraft] 那樣額外驗證 userId——見 [resumeDraft] 文件「守衛不對稱
  /// 是刻意的」說明:刪除的代價(`WorkoutRepository.discardDraft` 已有
  /// `endedAt IS NULL` 結構守衛兜底,誤刪最多是一次 no-op)遠低於接手錯
  /// 資料,不值得為了對稱而多一次查詢。
  Future<void> discardRecoverableDraft(String workoutId) =>
      _synchronized(() async {
        await ref.read(workoutRepositoryProvider).discardDraft(workoutId);
        await _plannedStore.clear(workoutId);
      });

  // MARK: - 開始訓練

  /// 開始自由訓練。已有進行中草稿時 no-op(矩陣:開始訓練連點兩下/已有
  /// 草稿時再按開始,理論上 UI 不可達,這裡是 controller 層的守門)。
  ///
  /// 記憶體狀態([state.value?.draft])只擋得住同一個 controller instance
  /// 內連續呼叫的情境——`build()` 重跑(換帳號、`ref.invalidate` 重試)會
  /// 讓 [state] 回到乾淨的 idle,但 DB 裡草稿列本身沒有消失。因此開始前
  /// 一律先查一次 DB([WorkoutRepository.fetchDraft]):查到既有草稿就直接
  /// 接手進 [state],不會在草稿還沒被使用者明確放棄的情況下多開一筆。
  Future<void> startFreeWorkout() => _synchronized(() async {
    if (state.value?.draft != null) return;
    final userId = await _requireUserId();
    final repo = ref.read(workoutRepositoryProvider);
    final existingDraft = await repo.fetchDraft(userId);
    if (existingDraft != null) {
      state = AsyncData(_flowFor(existingDraft));
      return;
    }
    final now = DateTime.now();
    final workoutId = generateUuidV4();
    await repo.create(
      Workout(
        id: workoutId,
        userId: userId,
        startedAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    // 新的一場訓練:「最近用過/上次數字」重查一次(上一場若在別台裝置完成、
    // 或上次查詢失敗,這裡補回來)。
    ref.invalidate(exerciseHistoryProvider);
    state = AsyncData(WorkoutFlowState(draft: await repo.fetchById(workoutId)));
  });

  /// 從模板開始:[template] 已經是 `applyTemplate` 展開好的初始資料
  /// (suggestedSets/Reps 為 null 時的 `?? 3`/`?? 10` 已在 applied_template.dart
  /// 處理過),這裡只負責把它轉成一筆完整的 Workout 一次性寫入。已有進行中
  /// 草稿時 no-op,同 [startFreeWorkout](含開始前先查 DB 的孤兒草稿防線,
  /// 見該方法文件)。
  Future<void> startFromTemplate(AppliedTemplate template) =>
      _synchronized(() async {
        if (state.value?.draft != null) return;
        final userId = await _requireUserId();
        final repo = ref.read(workoutRepositoryProvider);
        final existingDraft = await repo.fetchDraft(userId);
        if (existingDraft != null) {
          state = AsyncData(_flowFor(existingDraft));
          return;
        }
        final now = DateTime.now();
        final workoutId = generateUuidV4();

        // Mike 2026-11-11 裁示 2:模板的組不再寫成真實 WorkoutSet(沒做的組
        // 不該被存進歷史),只建動作;組改成「計畫組」存本機附屬儲存,打勾
        // 才變成真實組。計畫組的數字存模板值,畫面顯示時再用「該動作上一次
        // 的數字」覆蓋(best-effort,見 exercise_history.dart)——歷史查詢
        // 不放在開始訓練的必經路徑上。
        final exercises = <WorkoutExercise>[];
        final planned = <String, List<PlannedSet>>{};
        for (var i = 0; i < template.exercises.length; i++) {
          final templateExercise = template.exercises[i];
          final workoutExerciseId = generateUuidV4();
          exercises.add(
            WorkoutExercise(
              id: workoutExerciseId,
              workoutId: workoutId,
              exerciseId: templateExercise.exerciseId,
              exerciseName: templateExercise.exerciseName,
              orderIndex: i,
              createdAt: now,
              updatedAt: now,
            ),
          );
          planned[workoutExerciseId] = [
            for (final templateSet in templateExercise.sets)
              PlannedSet(id: generateUuidV4(), weight: templateSet.weight, reps: templateSet.reps),
          ];
        }

        await repo.create(
          Workout(
            id: workoutId,
            userId: userId,
            startedAt: now,
            templateId: template.templateId,
            exercises: exercises,
            createdAt: now,
            updatedAt: now,
          ),
        );
        // 附屬儲存寫失敗不擋開始訓練(計畫組只是提示),畫面仍用記憶體裡的。
        try {
          await _plannedStore.write(workoutId, planned);
        } catch (_) {}
        // 同 [startFreeWorkout]:新的一場訓練重查歷史。
        ref.invalidate(exerciseHistoryProvider);
        final draft = await repo.fetchById(workoutId);
        state = AsyncData(
          WorkoutFlowState(draft: draft, plannedSets: draft == null ? const {} : planned),
        );
      });

  // MARK: - 進行中操作(草稿寫穿)

  Workout _requireDraft() {
    final draft = state.value?.draft;
    if (draft == null) {
      throw StateError('WorkoutController: 沒有進行中的訓練草稿');
    }
    return draft;
  }

  Future<void> _refresh(String workoutId) async {
    final repo = ref.read(workoutRepositoryProvider);
    final planned = state.value?.plannedSets ?? const {};
    state = AsyncData(WorkoutFlowState(draft: await repo.fetchById(workoutId), plannedSets: planned));
  }

  /// 更新計畫組(記憶體 + 附屬儲存)。附屬儲存寫失敗只影響「重開後還在不在」,
  /// 不擋這次操作。
  Future<void> _setPlanned(String workoutId, Map<String, List<PlannedSet>> planned) async {
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        WorkoutFlowState(
          draft: current.draft,
          plannedSets: planned,
          isCompleting: current.isCompleting,
          isAbandoning: current.isAbandoning,
        ),
      );
    }
    try {
      await _plannedStore.write(workoutId, planned);
    } catch (_) {}
  }

  Map<String, List<PlannedSet>> _withoutPlanned(String workoutExerciseId, String? plannedSetId) {
    final planned = {...?state.value?.plannedSets};
    final list = planned[workoutExerciseId];
    if (list == null) return planned;
    if (plannedSetId == null) {
      planned.remove(workoutExerciseId);
    } else {
      final remaining = [for (final p in list) if (p.id != plannedSetId) p];
      if (remaining.isEmpty) {
        planned.remove(workoutExerciseId);
      } else {
        planned[workoutExerciseId] = remaining;
      }
    }
    return planned;
  }

  /// 新增動作到進行中的訓練(對照 iOS `addExercise`,插在最前面顯示是 UI
  /// 層的排序選擇——這裡固定接在現有動作之後,orderIndex 依序遞增)。
  Future<void> addExercise(Exercise exercise) => _synchronized(() async {
    final draft = _requireDraft();
    final now = DateTime.now();
    await ref
        .read(workoutRepositoryProvider)
        .addExerciseToWorkout(
          WorkoutExercise(
            id: generateUuidV4(),
            workoutId: draft.id,
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            orderIndex: draft.exercises.length,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _refresh(draft.id);
  });

  Future<void> removeExercise(String workoutExerciseId) =>
      _synchronized(() async {
        final draft = _requireDraft();
        await ref
            .read(workoutRepositoryProvider)
            .removeExercise(workoutExerciseId, workoutId: draft.id);
        await _refresh(draft.id);
        if (state.value?.plannedSets.containsKey(workoutExerciseId) ?? false) {
          await _setPlanned(draft.id, _withoutPlanned(workoutExerciseId, null));
        }
      });

  /// 記一組新的組數。[setNumber] 由目前草稿裡該動作既有的組數長度 + 1 算出
  /// (對照 iOS `exercise.sets.count + 1`)——用 [_requireDraft] 目前的
  /// state 現算,不用另外查 DB。
  Future<void> addSet({
    required String workoutExerciseId,
    required double weight,
    required int reps,
    double? rpe,
    bool isWarmup = false,
    int restSeconds = kDefaultRestSeconds,
  }) => _synchronized(
    () => _addSet(
      workoutExerciseId: workoutExerciseId,
      weight: weight,
      reps: reps,
      rpe: rpe,
      isWarmup: isWarmup,
      restSeconds: restSeconds,
    ),
  );

  /// 計畫組打勾:照給定數字(呼叫端可能改過)記成真實組,成功後才移除該
  /// 計畫組;寫入失敗時計畫組留著,使用者可再按一次。
  Future<void> confirmPlannedSet({
    required String workoutExerciseId,
    required String plannedSetId,
    required double weight,
    required int reps,
    double? rpe,
    bool isWarmup = false,
    int restSeconds = kDefaultRestSeconds,
  }) => _synchronized(() async {
    await _addSet(
      workoutExerciseId: workoutExerciseId,
      weight: weight,
      reps: reps,
      rpe: rpe,
      isWarmup: isWarmup,
      restSeconds: restSeconds,
    );
    final draft = _requireDraft();
    await _setPlanned(draft.id, _withoutPlanned(workoutExerciseId, plannedSetId));
  });

  /// 不做這組計畫組(左滑)。只動附屬儲存,不碰 DB。
  Future<void> removePlannedSet({
    required String workoutExerciseId,
    required String plannedSetId,
  }) => _synchronized(() async {
    final draft = _requireDraft();
    await _setPlanned(draft.id, _withoutPlanned(workoutExerciseId, plannedSetId));
  });

  Future<void> _addSet({
    required String workoutExerciseId,
    required double weight,
    required int reps,
    double? rpe,
    bool isWarmup = false,
    int restSeconds = kDefaultRestSeconds,
  }) async {
    final draft = _requireDraft();
    final exercise = draft.exercises.firstWhere(
      (e) => e.id == workoutExerciseId,
      orElse: () => throw StateError('動作不存在於目前草稿:$workoutExerciseId'),
    );
    final now = DateTime.now();
    await ref
        .read(workoutRepositoryProvider)
        .addSet(
          WorkoutSet(
            id: generateUuidV4(),
            workoutExerciseId: workoutExerciseId,
            setNumber: exercise.sets.length + 1,
            weight: weight,
            reps: reps,
            rpe: rpe,
            restSeconds: restSeconds,
            isWarmup: isWarmup,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _refresh(draft.id);
  }

  /// 更新既有組數。[set] 通常是從目前 [WorkoutFlowState.draft] 讀出的既有
  /// `WorkoutSet` 再用 `copyWith` 改過欄位——呼叫端(編輯 sheet)負責組出
  /// 完整的新版本,這裡只負責寫入 + 刷新。
  Future<void> updateSet(WorkoutSet set) => _synchronized(() async {
    final draft = _requireDraft();
    await ref.read(workoutRepositoryProvider).updateSet(set);
    await _refresh(draft.id);
  });

  Future<void> deleteSet(String setId, {required String workoutExerciseId}) =>
      _synchronized(() async {
        final draft = _requireDraft();
        await ref
            .read(workoutRepositoryProvider)
            .deleteSet(setId, workoutExerciseId: workoutExerciseId);
        await _refresh(draft.id);
      });

  // MARK: - 完成 / 放棄

  /// 完成訓練:呼叫 `WorkoutRepository.completeWorkout` 重新計算統計(暖身組
  /// 已在 repository 層排除)、逐一檢查非暖身組是否創造新 PR(對照 iOS
  /// `WorkoutViewModel.checkAndRecordPRs`,見 one_rm_calculator.dart 與
  /// `PersonalRecordRepository.createIfNewPR`),完成後把 [state] 收回 idle。
  ///
  /// **冪等**(矩陣:完成訓練連點/完成後再完成):沒有進行中草稿時(代表
  /// 已經完成過、或從未開始)直接回傳 [WorkoutCompletionNoOp],不拋錯、不
  /// 重複結算、不重複建立 PR。
  ///
  /// **沒有任何組的動作在結算前自動丟棄**(Mike 2026-11-11 裁示 3:拿掉
  /// 「完成動作」鈕,有組就算完成)——`WorkoutExercise.isCompleted` 欄位
  /// 保留不動、也不在這裡寫 true:「完成」一律由「有沒有組」推導,少一輪
  /// 逐動作寫入(雲端模式每筆都是網路往返)。草稿 0 組時拋 [StateError]
  /// (UI 已停用完成鈕,這是 controller 層的守門,不存空訓練)。計畫組
  /// 附屬儲存只在結算**成功後**清除;失敗時保留,讓使用者重試時計畫組還在。
  Future<WorkoutCompletionOutcome> completeWorkout() => _synchronized(() async {
    final current = state.value;
    final draft = current?.draft;
    if (current == null || draft == null) return const WorkoutCompletionNoOp();
    if (current.totalSetCount == 0) {
      throw StateError('WorkoutController: 草稿沒有任何組,不能完成訓練');
    }

    final planned = current.plannedSets;
    state = AsyncData(WorkoutFlowState(draft: draft, plannedSets: planned, isCompleting: true));
    final workoutRepo = ref.read(workoutRepositoryProvider);
    try {
      for (final exercise in draft.exercises) {
        if (exercise.sets.isEmpty) {
          await workoutRepo.removeExercise(exercise.id, workoutId: draft.id);
        }
      }
      final completed = await workoutRepo.completeWorkout(draft.id);
      final newPRCount = await _recordPersonalRecords(completed);
      // 先清附屬儲存、最後才收回 idle:真機 SharedPreferences.remove 走
      // platform channel,若先 idle 再 await 清除,中間會畫一幀把進行中畫面
      // 拆掉,UI 端還沒拿到結果就失去 context(不彈結算、不回首頁)。
      try {
        await _plannedStore.clear(draft.id);
      } catch (_) {}
      state = const AsyncData(WorkoutFlowState());
      // 下一場訓練的「最近用過/上次數字」要包含這一場。
      ref.invalidate(exerciseHistoryProvider);
      return WorkoutCompleted(
        workout: completed,
        newPersonalRecordCount: newPRCount,
      );
    } catch (_) {
      // 失敗時解除 loading、草稿保留在 state,讓 UI 能重試(常備紀律:
      // 非同步失敗路徑不得 fire-and-forget)。空動作可能已被丟棄一部分,
      // 重新讀一次 DB 讓畫面與事實一致(讀不到就沿用原草稿)。
      Workout? latest;
      try {
        latest = await workoutRepo.fetchById(draft.id);
      } catch (_) {}
      // 雲端已收下(只是記 PR 失敗)時,讀回的是已完成的訓練(endedAt 非 null)
      // ——不能放進 state.draft(進行中草稿的不變式是 endedAt == null)。改用
      // 原草稿,但拿掉已在結算前丟棄的 0 組動作,重試時不再對它們發刪除。
      final Workout keep;
      if (latest == null) {
        keep = draft;
      } else if (latest.endedAt == null) {
        keep = latest;
      } else {
        keep = draft.copyWith(exercises: [for (final e in draft.exercises) if (e.sets.isNotEmpty) e]);
      }
      state = AsyncData(WorkoutFlowState(draft: keep, plannedSets: planned));
      rethrow;
    }
  });

  /// 逐一檢查非暖身組是否創造新 PR。刻意用循序 `for` + `await`(不是
  /// `Future.wait` 平行處理)——同一次訓練裡同一動作出現多組遞增重量時,
  /// 後面的組別要能比較到「這次訓練前面已經新建的 PR」,對齊 iOS
  /// `checkAndRecordPRs` 逐一 `try prRepository.create` 的循序寫入行為。
  Future<int> _recordPersonalRecords(Workout workout) async {
    final prRepo = ref.read(personalRecordRepositoryProvider);
    final now = DateTime.now();
    var newPRCount = 0;

    for (final exercise in workout.exercises) {
      for (final set in exercise.sets) {
        if (set.isWarmup) continue;

        final oneRepMax = calculateOneRepMax(
          weight: set.weight,
          reps: set.reps,
          formula: ref.read(oneRmFormulaProvider),
        );
        final candidate = PersonalRecord(
          id: generateUuidV4(),
          userId: workout.userId,
          exerciseId: exercise.exerciseId,
          weight: set.weight,
          reps: set.reps,
          oneRepMax: oneRepMax,
          // 對齊 iOS:PR 的 achievedAt 用訓練開始時間,不是組數建立時間。
          achievedAt: workout.startedAt,
          workoutId: workout.id,
          createdAt: now,
          updatedAt: now,
        );
        final created = await prRepo.createIfNewPR(candidate);
        if (created != null) newPRCount += 1;
      }
    }
    return newPRCount;
  }

  /// 放棄訓練:刪除草稿列(cascade 清子列),[state] 收回 idle。
  ///
  /// **冪等**(矩陣:放棄確認後再放棄):沒有進行中草稿時直接 no-op。
  /// **與完成互斥**(矩陣:結算進行中不可放棄):`_synchronized` 序列化
  /// 保證這個方法一定等到進行中的 [completeWorkout] 完全結束才會執行——
  /// 若 completeWorkout 已經成功把草稿結清,這裡讀到的 `state.draft` 已是
  /// null,自然落入冪等 no-op 分支,不會誤刪一筆已經不存在的草稿或訓練。
  Future<void> abandonWorkout() => _synchronized(() async {
    final draft = state.value?.draft;
    if (draft == null) return;

    final planned = state.value?.plannedSets ?? const <String, List<PlannedSet>>{};
    state = AsyncData(WorkoutFlowState(draft: draft, plannedSets: planned, isAbandoning: true));
    try {
      await ref.read(workoutRepositoryProvider).discardDraft(draft.id);
      // 先清附屬儲存再收回 idle,理由同 [completeWorkout]。
      try {
        await _plannedStore.clear(draft.id);
      } catch (_) {}
      state = const AsyncData(WorkoutFlowState());
    } catch (_) {
      state = AsyncData(WorkoutFlowState(draft: draft, plannedSets: planned));
      rethrow;
    }
  });
}

final workoutControllerProvider =
    AsyncNotifierProvider<WorkoutController, WorkoutFlowState>(
      WorkoutController.new,
    );
