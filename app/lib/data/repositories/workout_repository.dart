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

  /// 從進行中的訓練移除一個動作(其下 sets 透過 FK cascade 一併刪除),並把
  /// 同一訓練([workoutId])下剩餘動作的 `orderIndex` 重新編號成連續的
  /// 0..N-1(對照 [deleteSet] 的 renumber 手法——不留編號空洞,避免
  /// controller `addExercise` 用 `draft.exercises.length` 算下一個
  /// orderIndex 時撞號)。單一 transaction,刪除與重編號要嘛都成功要嘛都
  /// 不生效。DELETE 的 where 子句多帶 `t.workoutId.equals(workoutId)` 這道
  /// 結構守衛(code review r2 db minor):[workoutExerciseId] 若剛好存在、但
  /// 屬於別筆訓練,不會被這裡誤刪——連帶讓「動作不存在,或不屬於這筆
  /// 訓練」統一落在 rowsAffected 0 → 拋 StateError 這條路徑,與同批方法
  /// 一致。
  Future<void> removeExercise(String workoutExerciseId, {required String workoutId}) async {
    await _db.transaction(() async {
      final rowsAffected = await (_db.delete(_db.workoutExercises)
            ..where((t) => t.id.equals(workoutExerciseId) & t.workoutId.equals(workoutId)))
          .go();
      if (rowsAffected == 0) {
        throw StateError('WorkoutExercise not found: $workoutExerciseId');
      }

      final remaining = await (_db.select(_db.workoutExercises)
            ..where((t) => t.workoutId.equals(workoutId))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      for (var i = 0; i < remaining.length; i++) {
        if (remaining[i].orderIndex != i) {
          await (_db.update(_db.workoutExercises)..where((t) => t.id.equals(remaining[i].id)))
              .write(db.WorkoutExercisesCompanion(orderIndex: Value(i)));
        }
      }
    });
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

  /// 放棄訓練草稿:刪除 workout row(exercises/sets 透過 FK cascade 一併
  /// 清除),但**只刪還在進行中的草稿**(`endedAt IS NULL`)——與 [delete]
  /// 的差異就在這道結構守衛:呼叫端傳入的 id 若剛好是一筆已完成的訓練,
  /// 這裡不會誤刪任何東西。找不到符合條件的列(id 不存在,或該列
  /// `endedAt` 已非 null)時 rowsAffected 為 0,靜默視為冪等 no-op,不拋錯
  /// ——對照 [WorkoutController.abandonWorkout]/`discardRecoverableDraft`
  /// 的冪等呼叫慣例(連續呼叫兩次都必須安全)。
  Future<void> discardDraft(String workoutId) async {
    await (_db.delete(_db.workouts)
          ..where((t) => t.id.equals(workoutId) & t.endedAt.isNull()))
        .go();
  }

  // MARK: - Read

  /// 只取「已完成」的訓練(`endedAt IS NOT NULL`)——進行中訓練草稿(波 3
  /// Drift 草稿寫穿,見 `.claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md`)
  /// 不得混進「已完成訓練」語意的查詢裡。[fetchAll]/[fetchByDateRange]/
  /// [fetchRecent]/[countWorkouts]/[calculateTotalVolume] 都套用這個過濾;
  /// [fetchById]/[fetchDraft]/[update]/[delete] 不套用(草稿本身也要能被
  /// 這些方法讀寫)。吃明確的 [table] 參數而非隱含捕捉外層 `_db.workouts`
  /// ——`_db.select`/`_db.selectOnly` 的呼叫端一律把自己查詢用的 table
  /// 參照(callback 的 `t`,或 `_db.workouts` 本身)傳進來,依賴關係看得到。
  Expression<bool> _isCompleted(db.$WorkoutsTable table) => table.endedAt.isNotNull();

  Future<List<Workout>> fetchAll() async {
    final rows = await (_db.select(_db.workouts)
          ..where((t) => _isCompleted(t))
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
          ..where((t) => t.startedAt.isBetweenValues(from, to) & _isCompleted(t))
          ..orderBy([(t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)]))
        .get();
    return [for (final row in rows) await _hydrate(row)];
  }

  Future<List<Workout>> fetchRecent(int limit) async {
    final rows = await (_db.select(_db.workouts)
          ..where((t) => _isCompleted(t))
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

  /// 批量刪除舊訓練(清理數據)。只清「已完成」的訓練——進行中草稿
  /// (`endedAt IS NULL`)不管 `startedAt` 多舊都不在清理範圍內,理由同
  /// [_isCompleted] 文件:草稿不該被「已完成訓練」語意的批次操作誤傷。
  Future<void> deleteOlderThan(DateTime date) async {
    await (_db.delete(_db.workouts)
          ..where((t) => t.startedAt.isSmallerThanValue(date) & _isCompleted(t)))
        .go();
  }

  // MARK: - Statistics

  /// 計算總容量(指定時間範圍)。草稿(`endedAt IS NULL`)不計入。
  Future<double> calculateTotalVolume({DateTime? from, DateTime? to}) async {
    final query = _db.selectOnly(_db.workouts)
      ..addColumns([_db.workouts.totalVolume.sum()])
      ..where(_isCompleted(_db.workouts));
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
      ..where(_isCompleted(_db.workouts));
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
  ///
  /// **DB 級冪等**:UPDATE 的 where 子句多帶一道 `endedAt IS NULL`——對已經
  /// 完成過的訓練再呼叫一次,不會用這次現算的統計/`endedAt` 覆蓋掉第一次
  /// 完成時寫入的內容,直接回傳目前已完成的內容。與
  /// [WorkoutController.completeWorkout] 的記憶體 state 檢查互為兩道防線
  /// (呼叫端序列化鎖擋住同一個 controller instance 的連續呼叫;這裡擋住
  /// 繞過 controller 直接呼叫 repository,或 state 已經失準的情境)。
  /// 整個計算與寫入包在單一 transaction 內,讀到的 exercises/sets 與最終
  /// 寫入的統計欄位一致,不會被同時發生的其他寫入插隊。
  Future<Workout> completeWorkout(String workoutId, {DateTime? endedAt}) {
    return _db.transaction(() async {
      final workoutRow = await (_db.select(_db.workouts)..where((t) => t.id.equals(workoutId)))
          .getSingleOrNull();
      if (workoutRow == null) {
        throw StateError('Workout not found: $workoutId');
      }

      final exercises = await _fetchExercisesForWorkout(workoutId);
      // totalVolume 從 sets 現算(weight × reps),不信任 WorkoutExercise.totalVolume
      // 欄位——該欄位沒有任何寫入路徑會即時維護,與 totalSets/totalExercises 的現算行為一致。
      // 暖身組(isWarmup)排除在外,對齊 iOS WorkoutViewModel.swift:232-235
      // (`updateTotals()`)與 :402-405(`WorkoutExerciseViewModel.totalVolume`)
      // ——兩處皆先 `filter { !$0.isWarmup }` 才加總。與
      // `workout_in_progress_view.dart` 的即時統計列共用同一份加總邏輯
      // ([nonWarmupTotalVolume]/[nonWarmupTotalSets]),曾經各自重寫一份、
      // 兩處一度不同步,已收斂。
      final totalVolume = nonWarmupTotalVolume(exercises);
      final totalSetsCount = nonWarmupTotalSets(exercises);
      final resolvedEndedAt = endedAt ?? DateTime.now();
      final duration = resolvedEndedAt.difference(workoutRow.startedAt).inMinutes;

      await (_db.update(_db.workouts)
            ..where((t) => t.id.equals(workoutId) & t.endedAt.isNull()))
          .write(
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
    });
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
