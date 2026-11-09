import 'package:drift/drift.dart';

import '../db/app_database.dart' as db;
import '../models/exercise.dart';

/// ExerciseRepository 的資料存取介面(公開方法簽名即原本 Drift 實作的公開 API)。
///
/// 實作:[DriftExerciseRepository](本機 Drift,`USE_MOCK`/測試/未設定 Supabase 時使用)、
/// `SupabaseExerciseRepository`(`supabase/supabase_exercise_repository.dart`)。由
/// `data/providers.dart` 依 `supabaseClientProvider` 切換。各方法語義以
/// [DriftExerciseRepository] 的文件為準,Supabase 版的差異寫在該實作的類別文件。
abstract interface class ExerciseRepository {
  Future<void> create(Exercise exercise);
  Future<void> batchCreate(List<Exercise> exercises);
  Future<List<Exercise>> fetchAll({bool includeInactive = false});
  Future<Exercise?> fetchById(String id);
  Future<List<Exercise>> fetchByCategory(String categoryId);
  Future<List<Exercise>> fetchByType(ExerciseType type);
  Future<List<Exercise>> fetchSystemExercises();
  Future<List<Exercise>> fetchCustomExercises(String userId);
  Future<List<Exercise>> getCustomExercises();
  Future<Exercise?> getExercise(String id);
  Future<List<Exercise>> search(String keyword);
  Future<void> update(Exercise exercise);
  Future<void> delete(String id);
  Future<void> permanentDelete(String id);
}

/// 動作庫的資料存取層。對照 iOS 版
/// `ios/WorkoutRecord/WorkoutRecord/Sources/Repositories/ExerciseRepository.swift`。
class DriftExerciseRepository implements ExerciseRepository {
  DriftExerciseRepository(this._db);

  final db.AppDatabase _db;

  // MARK: - Create

  @override
  Future<void> create(Exercise exercise) async {
    await _db.into(_db.exercises).insert(exercise.toCompanion());
  }

  /// 批量創建(用於初始化系統動作)。
  @override
  Future<void> batchCreate(List<Exercise> exercises) async {
    await _db.batch((batch) {
      batch.insertAll(_db.exercises, exercises.map((e) => e.toCompanion()));
    });
  }

  // MARK: - Read

  @override
  Future<List<Exercise>> fetchAll({bool includeInactive = false}) async {
    final query = _db.select(_db.exercises)
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (!includeInactive) {
      query.where((t) => t.isActive.equals(true));
    }
    final rows = await query.get();
    return rows.map(Exercise.fromRow).toList();
  }

  @override
  Future<Exercise?> fetchById(String id) async {
    final row = await (_db.select(_db.exercises)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : Exercise.fromRow(row);
  }

  @override
  Future<List<Exercise>> fetchByCategory(String categoryId) async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.categoryId.equals(categoryId) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  @override
  Future<List<Exercise>> fetchByType(ExerciseType type) async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.type.equals(type.value) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  @override
  Future<List<Exercise>> fetchSystemExercises() async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.isSystem.equals(true) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  @override
  Future<List<Exercise>> fetchCustomExercises(String userId) async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) =>
              t.isSystem.equals(false) & t.userId.equals(userId) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  /// 獲取自定義動作(別名方法,不需要 userId,對照 Swift `getCustomExercises`)。
  @override
  Future<List<Exercise>> getCustomExercises() async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.isSystem.equals(false) & t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(Exercise.fromRow).toList();
  }

  /// 根據 ID 獲取動作(別名方法,對照 Swift `getExercise(by:)`)。
  @override
  Future<Exercise?> getExercise(String id) => fetchById(id);

  /// 搜索動作(依名稱或英文名稱)。
  @override
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

  @override
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
  @override
  Future<void> delete(String id) async {
    await (_db.update(_db.exercises)..where((t) => t.id.equals(id))).write(
      db.ExercisesCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 永久刪除(僅用於自定義動作)。
  @override
  Future<void> permanentDelete(String id) async {
    await (_db.delete(_db.exercises)
          ..where((t) => t.id.equals(id) & t.isSystem.equals(false)))
        .go();
  }
}
