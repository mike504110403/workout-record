import 'package:drift/drift.dart';

import '../db/app_database.dart' as db;
import '../models/workout.dart';
import 'exercise_repository.dart';

/// 訓練記錄的資料存取層。對照 iOS 版
/// `ios/WorkoutRecord/WorkoutRecord/Sources/Repositories/WorkoutRepository.swift`。
class WorkoutRepository {
  WorkoutRepository(this._db, this._exerciseRepository);

  final db.AppDatabase _db;
  final ExerciseRepository _exerciseRepository;

  // MARK: - Create

  /// 建立訓練記錄,連同其下的 exercises 與 sets 一併寫入(單一 transaction)。
  /// 波 3 訓練核心流也用這個方法「開始訓練」——傳入 `endedAt: null` 的
  /// [Workout](自由訓練 exercises 為空清單;從模板開始則帶入
  /// `applyTemplate` 展開好的 exercises/sets),即完成「開始訓練即建草稿列」
  /// (見 .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md)。
  Future<void> create(Workout workout) async {
    await _db.transaction(() async {
      await _db.into(_db.workouts).insert(workout.toCompanion());
      for (final exercise in workout.exercises) {
        await _db.into(_db.workoutExercises).insert(exercise.toCompanion());
        for (final set in exercise.sets) {
          await _db.into(_db.workoutSets).insert(set.toCompanion());
        }
      }
    });
  }

  // MARK: - Draft mutations(進行中訓練草稿寫穿,波 3 第二段新增)
  //
  // 每個方法對應使用者在進行中訓練畫面的一個原子操作,呼叫後即時落 Drift——
  // 不像 `create` 整包 transaction 一次寫完。[WorkoutController] 在每次
  // 呼叫後一律重新 `fetchById` 整包草稿,以 DB 內容為單一事實來源,不在
  // controller 端維護一份可能與 DB 失準的鏡像狀態。

  /// 新增一個動作到進行中的訓練([exercise.sets] 通常是空清單——「從模板
  /// 開始」的初始展開走 [create] 一次性建立,這裡只服務訓練途中新增動作)。
  Future<void> addExerciseToWorkout(WorkoutExercise exercise) async {
    await _db.transaction(() async {
      await _db.into(_db.workoutExercises).insert(exercise.toCompanion());
      for (final set in exercise.sets) {
        await _db.into(_db.workoutSets).insert(set.toCompanion());
      }
    });
  }

  /// 從進行中的訓練移除一個動作(其下 sets 透過 FK cascade 一併刪除)。
  Future<void> removeExercise(String workoutExerciseId) async {
    await (_db.delete(_db.workoutExercises)..where((t) => t.id.equals(workoutExerciseId))).go();
  }

  /// 標記動作完成/取消完成。
  Future<void> setExerciseCompleted(String workoutExerciseId, {required bool isCompleted}) async {
    final rowsAffected = await (_db.update(_db.workoutExercises)
          ..where((t) => t.id.equals(workoutExerciseId)))
        .write(db.WorkoutExercisesCompanion(
      isCompleted: Value(isCompleted),
      updatedAt: Value(DateTime.now()),
    ));
    if (rowsAffected == 0) {
      throw StateError('WorkoutExercise not found: $workoutExerciseId');
    }
  }

  /// 記一組新的組數。
  Future<void> addSet(WorkoutSet set) async {
    await _db.into(_db.workoutSets).insert(set.toCompanion());
  }

  /// 更新既有組數的內容(重量/次數/RPE/暖身/休息秒數)。[set.volume] 由
  /// [WorkoutSet] 建構子依 weight × reps 自動算好,這裡照抄寫入,呼叫端
  /// 不需要另外算。
  Future<void> updateSet(WorkoutSet set) async {
    final rowsAffected = await (_db.update(_db.workoutSets)..where((t) => t.id.equals(set.id)))
        .write(db.WorkoutSetsCompanion(
      weight: Value(set.weight),
      reps: Value(set.reps),
      volume: Value(set.volume),
      rpe: Value(set.rpe),
      restSeconds: Value(set.restSeconds),
      isWarmup: Value(set.isWarmup),
      updatedAt: Value(DateTime.now()),
    ));
    if (rowsAffected == 0) {
      throw StateError('WorkoutSet not found: ${set.id}');
    }
  }

  /// 刪除一組組數,並把同一動作下剩餘組數的 `setNumber` 重新編號成連續的
  /// 1..N(對照 iOS `WorkoutViewModel.deleteSet` 的 renumber 行為——不留
  /// 編號空洞)。單一 transaction,刪除與重編號要嘛都成功要嘛都不生效。
  Future<void> deleteSet(String setId, {required String workoutExerciseId}) async {
    await _db.transaction(() async {
      final rowsAffected =
          await (_db.delete(_db.workoutSets)..where((t) => t.id.equals(setId))).go();
      if (rowsAffected == 0) {
        throw StateError('WorkoutSet not found: $setId');
      }

      final remaining = await (_db.select(_db.workoutSets)
            ..where((t) => t.workoutExerciseId.equals(workoutExerciseId))
            ..orderBy([(t) => OrderingTerm(expression: t.setNumber)]))
          .get();
      for (var i = 0; i < remaining.length; i++) {
        final expectedNumber = i + 1;
        if (remaining[i].setNumber != expectedNumber) {
          await (_db.update(_db.workoutSets)..where((t) => t.id.equals(remaining[i].id)))
              .write(db.WorkoutSetsCompanion(setNumber: Value(expectedNumber)));
        }
      }
    });
  }

  /// 放棄訓練草稿:等同 [delete]——刪除 workout row,exercises/sets 透過
  /// FK cascade 一併清除。取獨立的名字是為了在呼叫端(controller/測試)
  /// 讀起來語意明確是「放棄草稿」而非「刪除一筆已完成訓練」,行為上兩者
  /// 完全相同。
  Future<void> discardDraft(String workoutId) => delete(workoutId);

  // MARK: - Read

  /// 只取「已完成」的訓練(`endedAt IS NOT NULL`)——進行中訓練草稿(波 3
  /// Drift 草稿寫穿,見 `.claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md`)
  /// 不得混進「已完成訓練」語意的查詢裡。[fetchAll]/[fetchByDateRange]/
  /// [fetchRecent]/[countWorkouts]/[calculateTotalVolume] 都套用這個過濾;
  /// [fetchById]/[fetchDraft]/[update]/[delete] 不套用(草稿本身也要能被
  /// 這些方法讀寫)。
  Expression<bool> get _isCompleted => _db.workouts.endedAt.isNotNull();

  Future<List<Workout>> fetchAll() async {
    final rows = await (_db.select(_db.workouts)
          ..where((t) => _isCompleted)
          ..orderBy([(t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)]))
        .get();
    return [for (final row in rows) await _hydrate(row)];
  }

  /// 獲取所有訓練記錄(別名方法,對照 Swift `getAllWorkouts`)。
  Future<List<Workout>> getAllWorkouts() => fetchAll();

  Future<Workout?> fetchById(String id) async {
    final row = await (_db.select(_db.workouts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return _hydrate(row);
  }

  /// 根據 ID 獲取訓練(別名方法,對照 Swift `getWorkout(by:)`)。
  Future<Workout?> getWorkout(String id) => fetchById(id);

  /// 查詢目前使用者「進行中」的訓練草稿(`endedAt IS NULL`)——重啟恢復流程
  /// 用這個判斷要不要彈「繼續上次訓練 / 放棄」對話框。理論上同一使用者
  /// 至多一筆草稿(UI 層 [WorkoutController] 會擋開始訓練連點/已有草稿時
  /// 再開始);萬一意外存在多筆,取 `startedAt` 最新的一筆。
  Future<Workout?> fetchDraft(String userId) async {
    final row = await (_db.select(_db.workouts)
          ..where((t) => t.userId.equals(userId) & t.endedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return _hydrate(row);
  }

  Future<List<Workout>> fetchByDateRange(DateTime from, DateTime to) async {
    final rows = await (_db.select(_db.workouts)
          ..where((t) => t.startedAt.isBetweenValues(from, to) & _isCompleted)
          ..orderBy([(t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)]))
        .get();
    return [for (final row in rows) await _hydrate(row)];
  }

  Future<List<Workout>> fetchRecent(int limit) async {
    final rows = await (_db.select(_db.workouts)
          ..where((t) => _isCompleted)
          ..orderBy([(t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)])
          ..limit(limit))
        .get();
    return [for (final row in rows) await _hydrate(row)];
  }

  // MARK: - Update

  /// 更新訓練記錄的基本屬性(對照 Swift `update`:只更新
  /// endedAt/duration/統計欄位/note,不重寫 exercises/sets)。
  Future<void> update(Workout workout) async {
    final rowsAffected = await (_db.update(_db.workouts)
          ..where((t) => t.id.equals(workout.id)))
        .write(
      db.WorkoutsCompanion(
        endedAt: Value(workout.endedAt),
        duration: Value(workout.duration),
        totalVolume: Value(workout.totalVolume),
        totalSets: Value(workout.totalSets),
        totalExercises: Value(workout.totalExercises),
        note: Value(workout.note),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
      ),
    );
    if (rowsAffected == 0) {
      throw StateError('Workout not found: ${workout.id}');
    }
  }

  // MARK: - Delete

  /// 刪除訓練記錄(exercises/sets 透過 FK cascade 一併刪除,見 tables.dart)。
  Future<void> delete(String id) async {
    await (_db.delete(_db.workouts)..where((t) => t.id.equals(id))).go();
  }

  /// 批量刪除舊訓練(清理數據)。
  Future<void> deleteOlderThan(DateTime date) async {
    await (_db.delete(_db.workouts)..where((t) => t.startedAt.isSmallerThanValue(date))).go();
  }

  // MARK: - Statistics

  /// 計算總容量(指定時間範圍)。草稿(`endedAt IS NULL`)不計入。
  Future<double> calculateTotalVolume({DateTime? from, DateTime? to}) async {
    final query = _db.selectOnly(_db.workouts)
      ..addColumns([_db.workouts.totalVolume.sum()])
      ..where(_isCompleted);
    if (from != null) {
      query.where(_db.workouts.startedAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where(_db.workouts.startedAt.isSmallerOrEqualValue(to));
    }
    final result = await query.getSingle();
    return result.read(_db.workouts.totalVolume.sum()) ?? 0;
  }

  /// 計算訓練次數。草稿(`endedAt IS NULL`)不計入。
  Future<int> countWorkouts({DateTime? from, DateTime? to}) async {
    final query = _db.selectOnly(_db.workouts)
      ..addColumns([_db.workouts.id.count()])
      ..where(_isCompleted);
    if (from != null) {
      query.where(_db.workouts.startedAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where(_db.workouts.startedAt.isSmallerOrEqualValue(to));
    }
    final result = await query.getSingle();
    return result.read(_db.workouts.id.count()) ?? 0;
  }

  /// 完成訓練:根據目前已記錄的 exercises/sets 重新計算 totalVolume/totalSets/
  /// totalExercises 與 duration 並寫回。對照 Swift ViewModel 完成訓練時
  /// 手動計算後呼叫 `update` 的流程,這裡收斂成 repository 的單一操作。
  Future<Workout> completeWorkout(String workoutId, {DateTime? endedAt}) async {
    final workoutRow = await (_db.select(_db.workouts)..where((t) => t.id.equals(workoutId)))
        .getSingleOrNull();
    if (workoutRow == null) {
      throw StateError('Workout not found: $workoutId');
    }

    final exercises = await _fetchExercisesForWorkout(workoutId);
    // totalVolume 從 sets 現算(weight × reps),不信任 WorkoutExercise.totalVolume
    // 欄位——該欄位沒有任何寫入路徑會即時維護,與 totalSets/totalExercises 的現算行為一致。
    // 暖身組(isWarmup)排除在外,對齊 iOS WorkoutViewModel.swift:294-366
    // (`updateTotals()`/`WorkoutExerciseViewModel.totalVolume` 皆先
    // `filter { !$0.isWarmup }` 才加總)——先前版本把全部組數(含暖身組)
    // 一併算進 totalVolume/totalSets,與 iOS 語意不一致,已修正。
    final totalVolume = exercises.fold<double>(
      0,
      (sum, e) => sum +
          e.sets
              .where((set) => !set.isWarmup)
              .fold<double>(0, (s, set) => s + set.weight * set.reps),
    );
    final totalSetsCount =
        exercises.fold<int>(0, (sum, e) => sum + e.sets.where((set) => !set.isWarmup).length);
    final resolvedEndedAt = endedAt ?? DateTime.now();
    final duration = resolvedEndedAt.difference(workoutRow.startedAt).inMinutes;

    await (_db.update(_db.workouts)..where((t) => t.id.equals(workoutId))).write(
      db.WorkoutsCompanion(
        endedAt: Value(resolvedEndedAt),
        duration: Value(duration),
        totalVolume: Value(totalVolume),
        totalSets: Value(totalSetsCount),
        totalExercises: Value(exercises.length),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
      ),
    );

    return (await fetchById(workoutId))!;
  }

  // MARK: - Conversion

  Future<List<WorkoutExercise>> _fetchExercisesForWorkout(String workoutId) async {
    final exerciseRows = await (_db.select(_db.workoutExercises)
          ..where((t) => t.workoutId.equals(workoutId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    final result = <WorkoutExercise>[];
    for (final exerciseRow in exerciseRows) {
      final setRows = await (_db.select(_db.workoutSets)
            ..where((t) => t.workoutExerciseId.equals(exerciseRow.id))
            ..orderBy([(t) => OrderingTerm(expression: t.setNumber)]))
          .get();
      final exercise = await _exerciseRepository.fetchById(exerciseRow.exerciseId);
      result.add(WorkoutExercise.fromRow(
        exerciseRow,
        exercise: exercise,
        sets: setRows.map(WorkoutSet.fromRow).toList(),
      ));
    }
    return result;
  }

  Future<Workout> _hydrate(db.Workout row) async {
    final exercises = await _fetchExercisesForWorkout(row.id);
    return Workout.fromRow(row, exercises: exercises);
  }
}
