import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart' as db;
import 'exercise.dart';

/// 個人紀錄(PR),對應 Drift `PersonalRecords` 表。
///
/// [exercise] 為選填的關聯動作資料(由 repository join `Exercises` 表填入)。
class PersonalRecord {
  final String id;
  final String userId;
  final String exerciseId;
  final Exercise? exercise;
  final double weight;
  final int reps;
  final double oneRepMax;
  final DateTime achievedAt;
  final String? workoutId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PersonalRecord({
    required this.id,
    required this.userId,
    required this.exerciseId,
    this.exercise,
    required this.weight,
    required this.reps,
    required this.oneRepMax,
    required this.achievedAt,
    this.workoutId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PersonalRecord.fromRow(db.PersonalRecord row, {Exercise? exercise}) {
    return PersonalRecord(
      id: row.id,
      userId: row.userId,
      exerciseId: row.exerciseId,
      exercise: exercise,
      weight: row.weight,
      reps: row.reps,
      oneRepMax: row.oneRepMax,
      achievedAt: row.achievedAt,
      workoutId: row.workoutId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  db.PersonalRecordsCompanion toCompanion() {
    return db.PersonalRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      exerciseId: Value(exerciseId),
      weight: Value(weight),
      reps: Value(reps),
      oneRepMax: Value(oneRepMax),
      achievedAt: Value(achievedAt),
      workoutId: Value(workoutId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  PersonalRecord copyWith({
    double? weight,
    int? reps,
    double? oneRepMax,
    DateTime? achievedAt,
    String? workoutId,
    DateTime? updatedAt,
  }) {
    return PersonalRecord(
      id: id,
      userId: userId,
      exerciseId: exerciseId,
      exercise: exercise,
      weight: weight ?? this.weight,
      reps: reps ?? this.reps,
      oneRepMax: oneRepMax ?? this.oneRepMax,
      achievedAt: achievedAt ?? this.achievedAt,
      workoutId: workoutId ?? this.workoutId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 依動作分組的 PR 總結(非資料表,由 [PersonalRecord] 聚合而成)。
/// 對照 iOS `PersonalRecordRepository.getPRSummary`。
class PRSummary {
  final String exerciseId;
  final String exerciseName;
  final PrimaryMuscleGroup? primaryMuscleGroup;
  final PersonalRecord? currentPR;
  final List<PersonalRecord> prHistory;

  const PRSummary({
    required this.exerciseId,
    required this.exerciseName,
    this.primaryMuscleGroup,
    this.currentPR,
    this.prHistory = const [],
  });

  double? get weight => currentPR?.weight;
  int? get reps => currentPR?.reps;
  double? get oneRepMax => currentPR?.oneRepMax;
  DateTime? get achievedAt => currentPR?.achievedAt;
}
