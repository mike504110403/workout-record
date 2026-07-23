import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart' as db;
import 'exercise.dart';

/// 訓練模板,對應 Drift `Templates` 表。
class WorkoutTemplate {
  final String id;
  final String userId;
  final String name;
  final String? description;
  final bool isSystem;
  final List<TemplateExercise> exercises;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkoutTemplate({
    required this.id,
    required this.userId,
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

  WorkoutTemplate copyWith({
    String? name,
    String? description,
    List<TemplateExercise>? exercises,
    DateTime? updatedAt,
  }) {
    return WorkoutTemplate(
      id: id,
      userId: userId,
      name: name ?? this.name,
      description: description ?? this.description,
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
