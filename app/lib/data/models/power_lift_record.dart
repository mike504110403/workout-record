import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart' as db;

/// 三大項力量動作。rawValue 沿用 iOS 版(見 Models/PowerLift.swift)以維持
/// CoreData 匯入資料時的字串一致性。
enum PowerLift {
  squat('深蹲'),
  benchPress('槓鈴臥推'),
  deadlift('硬舉');

  const PowerLift(this.value);

  final String value;

  static PowerLift fromValue(String value) {
    return PowerLift.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError('Unknown PowerLift value: $value'),
    );
  }
}

/// 三項力量紀錄,對應 Drift `PowerLiftRecords` 表。
class PowerLiftRecord {
  final String id;
  final String userId;
  final PowerLift lift;
  final double weight;
  final int reps;
  final double oneRepMax;
  final DateTime achievedAt;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PowerLiftRecord({
    required this.id,
    required this.userId,
    required this.lift,
    required this.weight,
    this.reps = 1,
    required this.oneRepMax,
    required this.achievedAt,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PowerLiftRecord.fromRow(db.PowerLiftRecord row) {
    return PowerLiftRecord(
      id: row.id,
      userId: row.userId,
      lift: PowerLift.fromValue(row.lift),
      weight: row.weight,
      reps: row.reps,
      oneRepMax: row.oneRepMax,
      achievedAt: row.achievedAt,
      note: row.note,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  db.PowerLiftRecordsCompanion toCompanion() {
    return db.PowerLiftRecordsCompanion(
      id: Value(id),
      userId: Value(userId),
      lift: Value(lift.value),
      weight: Value(weight),
      reps: Value(reps),
      oneRepMax: Value(oneRepMax),
      achievedAt: Value(achievedAt),
      note: Value(note),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  PowerLiftRecord copyWith({
    double? weight,
    int? reps,
    double? oneRepMax,
    DateTime? achievedAt,
    String? note,
    DateTime? updatedAt,
  }) {
    return PowerLiftRecord(
      id: id,
      userId: userId,
      lift: lift,
      weight: weight ?? this.weight,
      reps: reps ?? this.reps,
      oneRepMax: oneRepMax ?? this.oneRepMax,
      achievedAt: achievedAt ?? this.achievedAt,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
