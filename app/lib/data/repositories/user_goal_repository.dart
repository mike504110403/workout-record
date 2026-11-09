import 'package:drift/drift.dart';

import '../db/app_database.dart' as db;
import '../models/user_goal.dart';

/// UserGoalRepository 的資料存取介面(公開方法簽名即原本 Drift 實作的公開 API)。
///
/// 實作:[DriftUserGoalRepository](本機 Drift,`USE_MOCK`/測試/未設定 Supabase 時使用)、
/// `SupabaseUserGoalRepository`(`supabase/supabase_user_goal_repository.dart`)。由
/// `data/providers.dart` 依 `supabaseClientProvider` 切換。各方法語義以
/// [DriftUserGoalRepository] 的文件為準,Supabase 版的差異寫在該實作的類別文件。
abstract interface class UserGoalRepository {
  Future<UserGoal> createOrUpdate(UserGoal userGoal);
  Future<UserGoal?> fetchByUser(String userId);
  Future<void> delete(String userId);
}

/// 使用者訓練目標的資料存取層。對照 iOS 版
/// `ios/WorkoutRecord/WorkoutRecord/Sources/Repositories/UserGoalRepository.swift`。
class DriftUserGoalRepository implements UserGoalRepository {
  DriftUserGoalRepository(this._db);

  final db.AppDatabase _db;

  // MARK: - Create or Update

  /// 創建或更新用戶目標(每個用戶只有一個目標記錄)。
  @override
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

  @override
  Future<UserGoal?> fetchByUser(String userId) async {
    final row = await (_db.select(_db.userGoals)..where((t) => t.userId.equals(userId)))
        .getSingleOrNull();
    return row == null ? null : UserGoal.fromRow(row);
  }

  // MARK: - Delete

  @override
  Future<void> delete(String userId) async {
    await (_db.delete(_db.userGoals)..where((t) => t.userId.equals(userId))).go();
  }
}
