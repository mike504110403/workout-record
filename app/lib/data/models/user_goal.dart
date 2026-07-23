import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart' as db;
import 'exercise.dart';

/// 各肌群的週容量目標(kg)。對應 Drift `UserGoals` 表中的 `*VolumeGoal` 欄位。
class VolumeGoals {
  final double? chest;
  final double? back;
  final double? legs;
  final double? shoulders;
  final double? arms;
  final double? core;

  const VolumeGoals({
    this.chest,
    this.back,
    this.legs,
    this.shoulders,
    this.arms,
    this.core,
  });

  /// 依肌群取得目標值。
  double? goalFor(PrimaryMuscleGroup muscleGroup) {
    switch (muscleGroup) {
      case PrimaryMuscleGroup.chest:
        return chest;
      case PrimaryMuscleGroup.back:
        return back;
      case PrimaryMuscleGroup.legs:
        return legs;
      case PrimaryMuscleGroup.shoulders:
        return shoulders;
      case PrimaryMuscleGroup.arms:
        return arms;
      case PrimaryMuscleGroup.core:
        return core;
      case PrimaryMuscleGroup.glutes:
      case PrimaryMuscleGroup.fullBody:
        return null;
    }
  }

  VolumeGoals copyWith({
    double? chest,
    double? back,
    double? legs,
    double? shoulders,
    double? arms,
    double? core,
  }) {
    return VolumeGoals(
      chest: chest ?? this.chest,
      back: back ?? this.back,
      legs: legs ?? this.legs,
      shoulders: shoulders ?? this.shoulders,
      arms: arms ?? this.arms,
      core: core ?? this.core,
    );
  }
}

/// 使用者訓練目標,對應 Drift `UserGoals` 表(每位使用者一筆)。
class UserGoal {
  final String id;
  final String userId;
  final int weeklyWorkoutGoal;
  final double? targetWeight;
  final VolumeGoals volumeGoals;
  final bool restDayReminder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserGoal({
    required this.id,
    required this.userId,
    this.weeklyWorkoutGoal = 3,
    this.targetWeight,
    this.volumeGoals = const VolumeGoals(),
    this.restDayReminder = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserGoal.fromRow(db.UserGoal row) {
    return UserGoal(
      id: row.id,
      userId: row.userId,
      weeklyWorkoutGoal: row.weeklyWorkoutGoal,
      targetWeight: row.targetWeight,
      volumeGoals: VolumeGoals(
        chest: row.chestVolumeGoal,
        back: row.backVolumeGoal,
        legs: row.legsVolumeGoal,
        shoulders: row.shouldersVolumeGoal,
        arms: row.armsVolumeGoal,
        core: row.coreVolumeGoal,
      ),
      restDayReminder: row.restDayReminder,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  db.UserGoalsCompanion toCompanion() {
    return db.UserGoalsCompanion(
      id: Value(id),
      userId: Value(userId),
      weeklyWorkoutGoal: Value(weeklyWorkoutGoal),
      targetWeight: Value(targetWeight),
      chestVolumeGoal: Value(volumeGoals.chest),
      backVolumeGoal: Value(volumeGoals.back),
      legsVolumeGoal: Value(volumeGoals.legs),
      shouldersVolumeGoal: Value(volumeGoals.shoulders),
      armsVolumeGoal: Value(volumeGoals.arms),
      coreVolumeGoal: Value(volumeGoals.core),
      restDayReminder: Value(restDayReminder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  UserGoal copyWith({
    int? weeklyWorkoutGoal,
    double? targetWeight,
    VolumeGoals? volumeGoals,
    bool? restDayReminder,
    DateTime? updatedAt,
  }) {
    return UserGoal(
      id: id,
      userId: userId,
      weeklyWorkoutGoal: weeklyWorkoutGoal ?? this.weeklyWorkoutGoal,
      targetWeight: targetWeight ?? this.targetWeight,
      volumeGoals: volumeGoals ?? this.volumeGoals,
      restDayReminder: restDayReminder ?? this.restDayReminder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
