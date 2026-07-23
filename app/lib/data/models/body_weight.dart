import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart' as db;

/// 體重紀錄,對應 Drift `BodyWeights` 表。
class BodyWeight {
  final String id;
  final String userId;
  final double weight;
  final DateTime measuredAt;
  final String? note;
  final bool isSynced;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BodyWeight({
    required this.id,
    required this.userId,
    required this.weight,
    required this.measuredAt,
    this.note,
    this.isSynced = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BodyWeight.fromRow(db.BodyWeight row) {
    return BodyWeight(
      id: row.id,
      userId: row.userId,
      weight: row.weight,
      measuredAt: row.measuredAt,
      note: row.note,
      isSynced: row.isSynced,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  db.BodyWeightsCompanion toCompanion() {
    return db.BodyWeightsCompanion(
      id: Value(id),
      userId: Value(userId),
      weight: Value(weight),
      measuredAt: Value(measuredAt),
      note: Value(note),
      isSynced: Value(isSynced),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  BodyWeight copyWith({
    double? weight,
    DateTime? measuredAt,
    String? note,
    bool? isSynced,
    DateTime? updatedAt,
  }) {
    return BodyWeight(
      id: id,
      userId: userId,
      weight: weight ?? this.weight,
      measuredAt: measuredAt ?? this.measuredAt,
      note: note ?? this.note,
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
