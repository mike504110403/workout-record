import 'package:drift/drift.dart';

import '../db/app_database.dart' as db;
import '../models/user_goal.dart';

/// 使用者訓練目標的資料存取層。對照 iOS 版
/// `ios/WorkoutRecord/WorkoutRecord/Sources/Repositories/UserGoalRepository.swift`。
class UserGoalRepository {
  UserGoalRepository(this._db);

  final db.AppDatabase _db;

  // MARK: - Create or Update

  /// 創建或更新用戶目標(每個用戶只有一個目標記錄)。
  Future<UserGoal> createOrUpdate(UserGoal userGoal) async {
    final existing =
        await (_db.select(_db.userGoals)..where((t) => t.userId.equals(userGoal.userId)))
            .getSingleOrNull();

    final now = DateTime.now();
    if (existing == null) {
      await _db.into(_db.userGoals).insert(userGoal.toCompanion());
    } else {
      await (_db.update(_db.userGoals)..where((t) => t.userId.equals(userGoal.userId))).write(
        db.UserGoalsCompanion(
          weeklyWorkoutGoal: Value(userGoal.weeklyWorkoutGoal),
          targetWeight: Value(userGoal.targetWeight),
          chestVolumeGoal: Value(userGoal.volumeGoals.chest),
          backVolumeGoal: Value(userGoal.volumeGoals.back),
          legsVolumeGoal: Value(userGoal.volumeGoals.legs),
          shouldersVolumeGoal: Value(userGoal.volumeGoals.shoulders),
          armsVolumeGoal: Value(userGoal.volumeGoals.arms),
          coreVolumeGoal: Value(userGoal.volumeGoals.core),
          restDayReminder: Value(userGoal.restDayReminder),
          updatedAt: Value(now),
        ),
      );
    }

    return userGoal;
  }

  // MARK: - Fetch

  Future<UserGoal?> fetchByUser(String userId) async {
    final row = await (_db.select(_db.userGoals)..where((t) => t.userId.equals(userId)))
        .getSingleOrNull();
    return row == null ? null : UserGoal.fromRow(row);
  }

  // MARK: - Delete

  Future<void> delete(String userId) async {
    await (_db.delete(_db.userGoals)..where((t) => t.userId.equals(userId))).go();
  }
}
