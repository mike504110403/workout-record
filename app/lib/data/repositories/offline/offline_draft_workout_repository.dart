import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/workout.dart';
import '../supabase/supabase_mapping.dart';
import '../workout_repository.dart';

/// 雲端模式的 [WorkoutRepository] 裝飾器:**進行中訓練草稿只存本機**,
/// 「完成訓練」時才一次上傳整份訓練。
///
/// 包住 `SupabaseWorkoutRepository`([_remote]),讓訓練進行中可以離線使用
/// (開始、加/刪動作、加/改/刪組、標記完成、放棄都不打網路)。
///
/// - **草稿存哪**:SharedPreferences,一筆草稿一個 key([keyPrefix] + workoutId),
///   值是與 PostgREST 巢狀查詢同形狀的 JSON(見 [workoutToNestedJson]),
///   內含 `user_id`;[fetchDraft] 依 userId 過濾,不同帳號互不可見。App 重啟後
///   照樣讀得回來,走既有「繼續上次訓練」流程恢復。
/// - **哪些方法走本機**:[create](`endedAt == null` 的草稿)、[fetchDraft](只看
///   本機)、以及目標 id 命中本機草稿時的所有草稿操作與 [fetchById]/[getWorkout]/
///   [update]/[delete]/[discardDraft]/[recomputeSummary]。未命中一律委派 [_remote]
///   (編輯已完成訓練、列表、統計等照舊走雲端)。
/// - **完成訓練**:[completeWorkout] 命中本機草稿時,在本機依
///   [nonWarmupTotalVolume]/[nonWarmupTotalSets] 算好統計(與 Drift 版、
///   `complete_workout` RPC 同規則,暖身組不計),再以 `_remote.create`
///   (`create_workout` RPC)一次上傳帶 `ended_at` 的完整訓練;**成功才刪本機
///   草稿**。上傳失敗時草稿原封不動,可重試。
/// - **冪等**:上傳失敗時先回查 `_remote.fetchById(id)`——雲端已有這筆**已完成**
///   的訓練(上次上傳其實成功、只是回應遺失;或主鍵衝突)就視為成功、刪本機草稿、
///   回傳雲端那份,不重複建立。回查也失敗(仍離線)則拋出原本的上傳錯誤。
///   本機草稿已刪後再對同 id 呼叫 [completeWorkout] 會委派給
///   `_remote.completeWorkout`(DB 級冪等,對已完成訓練不改寫),讓 controller
///   「上傳成功但記 PR 失敗 → 重按完成」能拿回已完成的訓練補記 PR。
class OfflineDraftWorkoutRepository implements WorkoutRepository {
  OfflineDraftWorkoutRepository(
    this._remote,
    this._prefs, {
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final WorkoutRepository _remote;
  final SharedPreferences _prefs;
  final DateTime Function() _now;

  /// 本機草稿的 SharedPreferences key 前綴(後接 workoutId)。
  static const keyPrefix = 'offline_workout_draft.v1.';

  // MARK: - 本機草稿存取

  Workout? _load(String workoutId) {
    final raw = _prefs.getString('$keyPrefix$workoutId');
    if (raw == null) return null;
    return workoutFromNestedJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  List<Workout> _loadAll() => [
    for (final key in _prefs.getKeys())
      if (key.startsWith(keyPrefix)) ?_load(key.substring(keyPrefix.length)),
  ];

  Future<void> _save(Workout draft) async {
    final ok = await _prefs.setString(
      '$keyPrefix${draft.id}',
      jsonEncode(workoutToNestedJson(draft)),
    );
    if (!ok) throw StateError('本機訓練草稿寫入失敗: ${draft.id}');
  }

  Future<void> _remove(String workoutId) async {
    await _prefs.remove('$keyPrefix$workoutId');
  }

  Workout? _findDraftByExercise(String workoutExerciseId) {
    for (final draft in _loadAll()) {
      if (draft.exercises.any((e) => e.id == workoutExerciseId)) return draft;
    }
    return null;
  }

  Workout? _findDraftBySet(String setId) {
    for (final draft in _loadAll()) {
      if (draft.exercises.any((e) => e.sets.any((s) => s.id == setId))) {
        return draft;
      }
    }
    return null;
  }

  Future<void> _saveExercises(Workout draft, List<WorkoutExercise> exercises) =>
      _save(draft.copyWith(exercises: exercises));

  // MARK: - Create

  @override
  Future<void> create(Workout workout) async {
    if (workout.endedAt != null) return _remote.create(workout);
    if (_load(workout.id) != null) {
      throw StateError('Workout already exists: ${workout.id}');
    }
    await _save(workout);
  }

  // MARK: - Draft mutations

  @override
  Future<void> addExerciseToWorkout(WorkoutExercise exercise) async {
    final draft = _load(exercise.workoutId);
    if (draft == null) return _remote.addExerciseToWorkout(exercise);
    if (draft.exercises.any((e) => e.id == exercise.id)) {
      throw StateError('WorkoutExercise already exists: ${exercise.id}');
    }
    await _saveExercises(draft, [...draft.exercises, exercise]);
  }

  /// 同 Drift 版:刪除後剩餘動作 orderIndex 重編成 0..N-1;動作不存在或不屬於
  /// 這筆草稿拋 StateError。
  @override
  Future<void> removeExercise(
    String workoutExerciseId, {
    required String workoutId,
  }) async {
    final draft = _load(workoutId);
    if (draft == null) {
      return _remote.removeExercise(workoutExerciseId, workoutId: workoutId);
    }
    if (!draft.exercises.any((e) => e.id == workoutExerciseId)) {
      throw StateError('WorkoutExercise not found: $workoutExerciseId');
    }
    final remaining = [
      for (final e in draft.exercises)
        if (e.id != workoutExerciseId) e,
    ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    await _saveExercises(draft, [
      for (var i = 0; i < remaining.length; i++)
        remaining[i].copyWith(orderIndex: i),
    ]);
  }

  @override
  Future<void> setExerciseCompleted(
    String workoutExerciseId, {
    required bool isCompleted,
  }) async {
    final draft = _findDraftByExercise(workoutExerciseId);
    if (draft == null) {
      return _remote.setExerciseCompleted(
        workoutExerciseId,
        isCompleted: isCompleted,
      );
    }
    await _saveExercises(draft, [
      for (final e in draft.exercises)
        e.id == workoutExerciseId
            ? e.copyWith(isCompleted: isCompleted, updatedAt: _now())
            : e,
    ]);
  }

  @override
  Future<void> addSet(WorkoutSet set) async {
    final draft = _findDraftByExercise(set.workoutExerciseId);
    if (draft == null) return _remote.addSet(set);
    if (draft.exercises.any((e) => e.sets.any((s) => s.id == set.id))) {
      throw StateError('WorkoutSet already exists: ${set.id}');
    }
    await _saveExercises(draft, [
      for (final e in draft.exercises)
        e.id == set.workoutExerciseId ? e.copyWith(sets: [...e.sets, set]) : e,
    ]);
  }

  /// 同 Drift 版:只改 weight/reps/volume/rpe/restSeconds/isWarmup(含改成 null),
  /// 並 bump updatedAt;其餘欄位(setNumber、note、createdAt)保留原值。
  @override
  Future<void> updateSet(WorkoutSet set) async {
    final draft = _findDraftBySet(set.id);
    if (draft == null) return _remote.updateSet(set);
    final now = _now();
    await _saveExercises(draft, [
      for (final e in draft.exercises)
        e.copyWith(
          sets: [
            for (final s in e.sets)
              s.id == set.id
                  ? WorkoutSet(
                      id: s.id,
                      workoutExerciseId: s.workoutExerciseId,
                      setNumber: s.setNumber,
                      weight: set.weight,
                      reps: set.reps,
                      volume: set.volume,
                      rpe: set.rpe,
                      restSeconds: set.restSeconds,
                      isWarmup: set.isWarmup,
                      note: s.note,
                      createdAt: s.createdAt,
                      updatedAt: now,
                    )
                  : s,
          ],
        ),
    ]);
  }

  /// 同 Drift 版:刪除後同動作剩餘組數 setNumber 重編成 1..N;組數不存在拋
  /// StateError。
  @override
  Future<void> deleteSet(
    String setId, {
    required String workoutExerciseId,
  }) async {
    final draft = _findDraftByExercise(workoutExerciseId);
    if (draft == null) {
      return _remote.deleteSet(setId, workoutExerciseId: workoutExerciseId);
    }
    final exercise = draft.exercises.firstWhere(
      (e) => e.id == workoutExerciseId,
    );
    if (!exercise.sets.any((s) => s.id == setId)) {
      throw StateError('WorkoutSet not found: $setId');
    }
    final remaining = [
      for (final s in exercise.sets)
        if (s.id != setId) s,
    ]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    await _saveExercises(draft, [
      for (final e in draft.exercises)
        e.id == workoutExerciseId
            ? e.copyWith(
                sets: [
                  for (var i = 0; i < remaining.length; i++)
                    remaining[i].copyWith(setNumber: i + 1),
                ],
              )
            : e,
    ]);
  }

  /// 本機草稿直接刪除(冪等);不在本機的 id 委派雲端(雲端版本身只刪
  /// `ended_at IS NULL` 的列)。
  @override
  Future<void> discardDraft(String workoutId) async {
    if (_load(workoutId) != null) return _remove(workoutId);
    return _remote.discardDraft(workoutId);
  }

  // MARK: - Read

  @override
  Future<List<Workout>> fetchAll() => _remote.fetchAll();

  @override
  Future<List<Workout>> getAllWorkouts() => _remote.getAllWorkouts();

  @override
  Future<Workout?> fetchById(String id) async =>
      _load(id) ?? await _remote.fetchById(id);

  @override
  Future<Workout?> getWorkout(String id) => fetchById(id);

  /// 只查本機:草稿只存在本機,離線也要能開始/恢復訓練,不打雲端。同一使用者
  /// 萬一有多筆,取 startedAt 最新的一筆(同 Drift 版)。
  @override
  Future<Workout?> fetchDraft(String userId) async {
    final drafts = [
      for (final d in _loadAll())
        if (d.userId == userId && d.endedAt == null) d,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return drafts.isEmpty ? null : drafts.first;
  }

  @override
  Future<List<Workout>> fetchByDateRange(DateTime from, DateTime to) =>
      _remote.fetchByDateRange(from, to);

  @override
  Future<List<Workout>> fetchRecent(int limit) => _remote.fetchRecent(limit);

  // MARK: - Update / Delete

  @override
  Future<void> update(Workout workout) async {
    final draft = _load(workout.id);
    if (draft == null) return _remote.update(workout);
    await _save(
      Workout(
        id: draft.id,
        userId: draft.userId,
        startedAt: draft.startedAt,
        endedAt: workout.endedAt,
        duration: workout.duration,
        totalVolume: workout.totalVolume,
        totalSets: workout.totalSets,
        totalExercises: workout.totalExercises,
        note: workout.note,
        templateId: draft.templateId,
        isSynced: false,
        exercises: draft.exercises,
        createdAt: draft.createdAt,
        updatedAt: _now(),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    if (_load(id) != null) return _remove(id);
    return _remote.delete(id);
  }

  @override
  Future<void> deleteOlderThan(DateTime date) => _remote.deleteOlderThan(date);

  // MARK: - Statistics

  @override
  Future<double> calculateTotalVolume({DateTime? from, DateTime? to}) =>
      _remote.calculateTotalVolume(from: from, to: to);

  @override
  Future<int> countWorkouts({DateTime? from, DateTime? to}) =>
      _remote.countWorkouts(from: from, to: to);

  @override
  Future<Workout> completeWorkout(String workoutId, {DateTime? endedAt}) async {
    final draft = _load(workoutId);
    if (draft == null) {
      return _remote.completeWorkout(workoutId, endedAt: endedAt);
    }

    final resolvedEndedAt = endedAt ?? _now();
    final completed = draft.copyWith(
      endedAt: resolvedEndedAt,
      duration: resolvedEndedAt.difference(draft.startedAt).inMinutes,
      totalVolume: nonWarmupTotalVolume(draft.exercises),
      totalSets: nonWarmupTotalSets(draft.exercises),
      totalExercises: draft.exercises.length,
      isSynced: false,
      updatedAt: _now(),
    );

    Workout result = completed;
    try {
      await _remote.create(completed);
    } catch (error, stackTrace) {
      final existing = await _probeUploaded(workoutId);
      if (existing == null) Error.throwWithStackTrace(error, stackTrace);
      result = existing;
    }
    await _remove(workoutId);
    return result;
  }

  /// 上傳失敗後回查雲端是否已有這筆已完成的訓練;回查失敗或不存在回 null。
  Future<Workout?> _probeUploaded(String workoutId) async {
    try {
      final existing = await _remote.fetchById(workoutId);
      return existing?.endedAt == null ? null : existing;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Workout> recomputeSummary(String workoutId) async {
    if (_load(workoutId) != null) {
      throw StateError(
        'recomputeSummary: workout $workoutId 還是進行中的草稿(endedAt IS NULL),'
        '只有已完成的訓練才能重算 summary',
      );
    }
    return _remote.recomputeSummary(workoutId);
  }
}
