import 'package:drift/drift.dart';

import '../db/app_database.dart' as db;
import '../models/exercise.dart';
import '../models/workout_template.dart';
import 'exercise_repository.dart';

/// 訓練模板的資料存取層。對照 iOS 版
/// `ios/WorkoutRecord/WorkoutRecord/Sources/Repositories/TemplateRepository.swift`。
///
/// 呼叫端需自行為 [TemplateExercise.id] 產生唯一值(如同其他 repository,
/// id 產生不是 data 層的職責)。
class TemplateRepository {
  TemplateRepository(this._db, this._exerciseRepository);

  final db.AppDatabase _db;
  final ExerciseRepository _exerciseRepository;

  // MARK: - Create

  /// 建立模板,連同其下的 template exercises 一併寫入(單一 transaction)。
  Future<void> create(WorkoutTemplate template) async {
    await _db.transaction(() async {
      await _db.into(_db.templates).insert(template.toCompanion());
      for (var i = 0; i < template.exercises.length; i++) {
        final exercise = template.exercises[i];
        await _db.into(_db.templateExercises).insert(
              exercise.toCompanion().copyWith(
                    templateId: Value(template.id),
                    orderIndex: Value(i),
                  ),
            );
      }
    });
  }

  // MARK: - Read

  Future<List<WorkoutTemplate>> fetchAll(String userId) async {
    final rows = await (_db.select(_db.templates)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.isSystem, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.name),
          ]))
        .get();
    return [for (final row in rows) await _hydrate(row)];
  }

  Future<WorkoutTemplate?> fetchById(String id) async {
    final row = await (_db.select(_db.templates)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return _hydrate(row);
  }

  Future<List<WorkoutTemplate>> fetchSystemTemplates() async {
    final rows = await (_db.select(_db.templates)
          ..where((t) => t.isSystem.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return [for (final row in rows) await _hydrate(row)];
  }

  // MARK: - Update

  /// 更新模板基本資訊,並整批重建 template exercises(對照 Swift `update`:
  /// 刪除舊的動作關聯,再依 [template.exercises] 建立新的)。
  Future<void> update(WorkoutTemplate template) async {
    await _db.transaction(() async {
      final rowsAffected = await (_db.update(_db.templates)
            ..where((t) => t.id.equals(template.id)))
          .write(
        db.TemplatesCompanion(
          name: Value(template.name),
          descriptionText: Value(template.description),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (rowsAffected == 0) {
        throw StateError('Template not found: ${template.id}');
      }

      await (_db.delete(_db.templateExercises)
            ..where((t) => t.templateId.equals(template.id)))
          .go();

      for (var i = 0; i < template.exercises.length; i++) {
        final exercise = template.exercises[i];
        await _db.into(_db.templateExercises).insert(
              db.TemplateExercisesCompanion(
                id: Value(exercise.id),
                templateId: Value(template.id),
                exerciseId: Value(exercise.exerciseId),
                orderIndex: Value(i),
                suggestedSets: Value(exercise.suggestedSets),
                suggestedReps: Value(exercise.suggestedReps),
              ),
            );
      }
    });
  }

  // MARK: - Delete

  Future<void> delete(String id) async {
    await (_db.delete(_db.templates)
          ..where((t) => t.id.equals(id) & t.isSystem.equals(false)))
        .go();
  }

  // MARK: - Conversion

  Future<WorkoutTemplate> _hydrate(db.Template row) async {
    final exerciseRows = await (_db.select(_db.templateExercises)
          ..where((t) => t.templateId.equals(row.id))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    final exercises = <TemplateExercise>[];
    for (final exerciseRow in exerciseRows) {
      final Exercise? exercise = await _exerciseRepository.fetchById(exerciseRow.exerciseId);
      exercises.add(TemplateExercise.fromRow(exerciseRow, exercise: exercise));
    }

    return WorkoutTemplate.fromRow(row, exercises: exercises);
  }
}
