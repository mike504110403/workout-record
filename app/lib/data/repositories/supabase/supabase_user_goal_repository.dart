import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_goal.dart';
import '../user_goal_repository.dart';
import 'supabase_mapping.dart';

/// [UserGoalRepository] 的 Supabase 實作。
///
/// 與 [DriftUserGoalRepository] 的差異:
/// - 擁有者一律是登入者 auth uid;[fetchByUser]/[delete] 的 userId 參數與
///   model 的 userId 不參與查詢(RLS 已限定本人)。
/// - DB 有 `unique (user_id)` 約束(Drift 版沒有):[createOrUpdate] 照 Drift 版
///   「先查再寫」,兩台裝置同時首次建立時,慢的那台會撞 unique 拋
///   PostgrestException(23505),不會產生兩筆。
class SupabaseUserGoalRepository implements UserGoalRepository {
  SupabaseUserGoalRepository(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('user_goals');

  @override
  Future<UserGoal> createOrUpdate(UserGoal userGoal) async {
    final uid = requireUid(_client);
    final existing = await _table.select('id').eq('user_id', uid).maybeSingle();

    if (existing == null) {
      await _table.insert({
        ...companionToJson(userGoal.toCompanion()),
        'user_id': uid,
      });
    } else {
      await _table.update({
        'weekly_workout_goal': userGoal.weeklyWorkoutGoal,
        'target_weight': userGoal.targetWeight,
        'chest_volume_goal': userGoal.volumeGoals.chest,
        'back_volume_goal': userGoal.volumeGoals.back,
        'legs_volume_goal': userGoal.volumeGoals.legs,
        'shoulders_volume_goal': userGoal.volumeGoals.shoulders,
        'arms_volume_goal': userGoal.volumeGoals.arms,
        'core_volume_goal': userGoal.volumeGoals.core,
        'rest_day_reminder': userGoal.restDayReminder,
        'updated_at': encodeValue(DateTime.now()),
      }).eq('user_id', uid);
    }

    return userGoal;
  }

  @override
  Future<UserGoal?> fetchByUser(String userId) async {
    final row = await _table.select().eq('user_id', requireUid(_client)).maybeSingle();
    return row == null ? null : UserGoal.fromRow(userGoalRowFromJson(row));
  }

  @override
  Future<void> delete(String userId) async {
    await _table.delete().eq('user_id', requireUid(_client));
  }
}
