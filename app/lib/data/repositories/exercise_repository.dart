import 'package:drift/drift.dart';

import '../db/app_database.dart' as db;
import '../models/exercise.dart';

/// 動作庫的資料存取層。對照 iOS 版
/// `ios/WorkoutRecord/WorkoutRecord/Sources/Repositories/ExerciseRepository.swift`。
class ExerciseRepository {
  ExerciseRepository(this._db);

  final db.AppDatabase _db;

  // MARK: - Create

  Future<void> create(Exercise exercise) async {
    await _db.into(_db.exercises).insert(exercise.toCompanion());
  }

  /// 批量創建(用於初始化系統動作)。
  Future<void> batchCreate(List<Exercise> exercises) async {
    await _db.batch((batch) {
      batch.insertAll(_db.exercises, exercises.map((e) => e.toCompanion()));
    });
  }

  // MARK: - Read

  Future<List<Exercise>> fetchAll({bool includeInactive = false}) async {
    final query = _db.select(_db.exercises)
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (!includeInactive) {
      query.where((t) => t.isActive.equals(true));
    }
    final rows = await query.get();
    return rows.map(Exercise.fromRow).toList();
  }

  Future<Exercise?> fetchById(String id) async {
    final row = await (_db.select(_db.exercises)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : Exercise.fromRow(row);
  }

  Future<List<Exercise>> fetchByCategory(String categoryId) async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.categoryId.equals(categoryId) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  Future<List<Exercise>> fetchByType(ExerciseType type) async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.type.equals(type.value) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  Future<List<Exercise>> fetchSystemExercises() async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.isSystem.equals(true) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  Future<List<Exercise>> fetchCustomExercises(String userId) async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) =>
              t.isSystem.equals(false) & t.userId.equals(userId) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  /// 獲取自定義動作(別名方法,不需要 userId,對照 Swift `getCustomExercises`)。
  Future<List<Exercise>> getCustomExercises() async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.isSystem.equals(false) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  /// 根據 ID 獲取動作(別名方法,對照 Swift `getExercise(by:)`)。
  Future<Exercise?> getExercise(String id) => fetchById(id);

  /// 搜索動作(依名稱或英文名稱)。
  Future<List<Exercise>> search(String keyword) async {
    final pattern = '%$keyword%';
    final rows = await (_db.select(_db.exercises)
          ..where((t) =>
              (t.name.like(pattern) | t.nameEn.like(pattern)) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  // MARK: - Update

  Future<void> update(Exercise exercise) async {
    final rowsAffected = await (_db.update(_db.exercises)
          ..where((t) => t.id.equals(exercise.id)))
        .write(
      db.ExercisesCompanion(
        name: Value(exercise.name),
        nameEn: Value(exercise.nameEn),
        categoryId: Value(exercise.categoryId),
        type: Value(exercise.type.value),
        movementPattern: Value(exercise.movementPattern?.value),
        primaryMuscleGroup: Value(exercise.primaryMuscleGroup?.value),
        descriptionText: Value(exercise.description),
        videoURL: Value(exercise.videoUrl),
        imageURL: Value(exercise.imageUrl),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (rowsAffected == 0) {
      throw StateError('Exercise not found: ${exercise.id}');
    }
  }

  // MARK: - Delete (Soft Delete)

  /// 軟刪除:只標記為不活躍(對照 Swift `delete`)。
  Future<void> delete(String id) async {
    await (_db.update(_db.exercises)..where((t) => t.id.equals(id))).write(
      db.ExercisesCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 永久刪除(僅用於自定義動作)。
  Future<void> permanentDelete(String id) async {
    await (_db.delete(_db.exercises)
          ..where((t) => t.id.equals(id) & t.isSystem.equals(false)))
        .go();
  }
}
