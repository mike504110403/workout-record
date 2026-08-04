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

  /// minor 修改(大腦核准的既有方法一行變更,回報中單獨列出):WHERE 補
  /// `isSystem = false`。防呆——CoreData 匯入的個人模板理論上不該是
  /// isSystem = true,但來源資料就是「使用者裝置上真實存在過什麼就是
  /// 什麼」,沒有結構性保證;萬一某筆匯入列的 userId 剛好等於某個真實
  /// 使用者、ZISSYSTEM 又剛好是 1,原本這裡會把它撈進「個人模板」清單,
  /// 跟 fetchSystemTemplates() 撈到的同一筆重複列出兩次。加這個條件讓
  /// fetchAll 名副其實只回傳個人模板,系統模板一律只從 fetchSystemTemplates()
  /// 出現一次。
  Future<List<WorkoutTemplate>> fetchAll(String userId) async {
    final rows = await (_db.select(_db.templates)
          ..where((t) => t.userId.equals(userId) & t.isSystem.equals(false))
          ..orderBy([
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
