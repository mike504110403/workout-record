import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart' as db;
import 'exercise.dart';

/// 訓練模板,對應 Drift `Templates` 表。
class WorkoutTemplate {
  final String id;
  /// 擁有者。系統模板(見 [isSystem])沒有擁有者,是 null——對應 schemaVersion
  /// 2 起 `Templates.userId` 改 nullable(見 tables.dart 註解與
  /// `.claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md`)。
  final String? userId;
  final String name;
  final String? description;
  final bool isSystem;
  final List<TemplateExercise> exercises;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkoutTemplate({
    required this.id,
    this.userId,
    required this.name,
    this.description,
    this.isSystem = false,
    this.exercises = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkoutTemplate.fromRow(
    db.Template row, {
    List<TemplateExercise> exercises = const [],
  }) {
    return WorkoutTemplate(
      id: row.id,
      userId: row.userId,
      name: row.name,
      description: row.descriptionText,
      isSystem: row.isSystem,
      exercises: exercises,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  db.TemplatesCompanion toCompanion() {
    return db.TemplatesCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value(name),
      descriptionText: Value(description),
      isSystem: Value(isSystem),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  /// [description] 用 [Value] 哨兵區分「沒傳(維持原值)」與「傳入 null
  /// (清空描述)」——原本用 `description ?? this.description` 這種一般
  /// nullable 參數寫法,清空描述時傳進來的 null 會被 `??` 吃掉、自動退回
  /// 舊描述,存檔後畫面看起來成功但 DB 裡描述其實沒被清掉(code-reviewer
  /// 實測重現的真實 bug)。呼叫端要清空描述時必須明確傳
  /// `description: const Value(null)`,不傳這個參數就是「不動描述」。
  WorkoutTemplate copyWith({
    String? name,
    Value<String?> description = const Value.absent(),
    List<TemplateExercise>? exercises,
    DateTime? updatedAt,
  }) {
    return WorkoutTemplate(
      id: id,
      userId: userId,
      name: name ?? this.name,
      description: description.present ? description.value : this.description,
      isSystem: isSystem,
      exercises: exercises ?? this.exercises,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 模板中的單一動作,對應 Drift `TemplateExercises` 表。
///
/// 此表無 `createdAt`/`updatedAt` 欄位(見 tables.dart)。
class TemplateExercise {
  final String id;
  final String templateId;
  final String exerciseId;
  final Exercise? exercise;
  final int orderIndex;
  final int? suggestedSets;
  final int? suggestedReps;

  const TemplateExercise({
    required this.id,
    required this.templateId,
    required this.exerciseId,
    this.exercise,
    this.orderIndex = 0,
    this.suggestedSets,
    this.suggestedReps,
  });

  factory TemplateExercise.fromRow(db.TemplateExercise row, {Exercise? exercise}) {
    return TemplateExercise(
      id: row.id,
      templateId: row.templateId,
      exerciseId: row.exerciseId,
      exercise: exercise,
      orderIndex: row.orderIndex,
      suggestedSets: row.suggestedSets,
      suggestedReps: row.suggestedReps,
    );
  }

  db.TemplateExercisesCompanion toCompanion() {
    return db.TemplateExercisesCompanion(
      id: Value(id),
      templateId: Value(templateId),
      exerciseId: Value(exerciseId),
      orderIndex: Value(orderIndex),
      suggestedSets: Value(suggestedSets),
      suggestedReps: Value(suggestedReps),
    );
  }
}
