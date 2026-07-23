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

  // MARK: - Read

  Future<List<Workout>> fetchAll() async {
    final rows = await (_db.select(_db.workouts)
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

  Future<List<Workout>> fetchByDateRange(DateTime from, DateTime to) async {
    final rows = await (_db.select(_db.workouts)
          ..where((t) => t.startedAt.isBetweenValues(from, to))
          ..orderBy([(t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)]))
        .get();
    return [for (final row in rows) await _hydrate(row)];
  }

  Future<List<Workout>> fetchRecent(int limit) async {
    final rows = await (_db.select(_db.workouts)
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

  /// 計算總容量(指定時間範圍)。
  Future<double> calculateTotalVolume({DateTime? from, DateTime? to}) async {
    final query = _db.selectOnly(_db.workouts)
      ..addColumns([_db.workouts.totalVolume.sum()]);
    if (from != null) {
      query.where(_db.workouts.startedAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where(_db.workouts.startedAt.isSmallerOrEqualValue(to));
    }
    final result = await query.getSingle();
    return result.read(_db.workouts.totalVolume.sum()) ?? 0;
  }

  /// 計算訓練次數。
  Future<int> countWorkouts({DateTime? from, DateTime? to}) async {
    final query = _db.selectOnly(_db.workouts)..addColumns([_db.workouts.id.count()]);
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
    final totalVolume = exercises.fold<double>(0, (sum, e) => sum + e.totalVolume);
    final totalSetsCount = exercises.fold<int>(0, (sum, e) => sum + e.sets.length);
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
