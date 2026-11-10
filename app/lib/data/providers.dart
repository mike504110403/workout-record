import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../features/auth/shared_preferences_provider.dart';

import 'db/app_database.dart';
import 'repositories/body_weight_repository.dart';
import 'repositories/exercise_repository.dart';
import 'repositories/offline/offline_cached_exercise_repository.dart';
import 'repositories/offline/offline_cached_user_repository.dart';
import 'repositories/offline/offline_draft_workout_repository.dart';
import 'repositories/personal_record_repository.dart';
import 'repositories/power_lift_record_repository.dart';
import 'repositories/supabase/supabase_body_weight_repository.dart';
import 'repositories/supabase/supabase_exercise_repository.dart';
import 'repositories/supabase/supabase_personal_record_repository.dart';
import 'repositories/supabase/supabase_power_lift_record_repository.dart';
import 'repositories/supabase/supabase_template_repository.dart';
import 'repositories/supabase/supabase_user_goal_repository.dart';
import 'repositories/supabase/supabase_user_repository.dart';
import 'repositories/supabase/supabase_workout_repository.dart';
import 'repositories/template_repository.dart';
import 'repositories/user_goal_repository.dart';
import 'repositories/user_repository.dart';
import 'repositories/workout_repository.dart';
import 'supabase_client.dart';

// 資料層切換:`supabaseClientProvider` 為 null(USE_MOCK、測試、未設定 Supabase)
// → Drift 實作;非 null(main.dart 初始化 Supabase 後 override)→ Supabase 實作。
// 見 data/supabase_client.dart。
//
// 雲端模式的離線支援(訓練進行中可離線):workout/exercise/user 三個 repository
// 外面各包一層本機裝飾器(data/repositories/offline/)——訓練草稿只存本機、
// 完成時才一次上傳;動作清單與登入者 users 列成功讀取時快取,網路失敗時回快取。
// 本機儲存用 SharedPreferences(main.dart 已 override [sharedPreferencesProvider])。

String? Function() _currentUid(SupabaseClient client) =>
    () => client.auth.currentUser?.id;

/// App 唯一的 Drift 資料庫實例。Supabase 模式下 repository 不再讀寫它,
/// 但舊 CoreData 匯入、帳號隔離清本機等流程仍照舊使用(見 main.dart)。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return OfflineCachedExerciseRepository(
      SupabaseExerciseRepository(client),
      ref.watch(sharedPreferencesProvider),
      _currentUid(client),
    );
  }
  return DriftExerciseRepository(ref.watch(appDatabaseProvider));
});

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return OfflineDraftWorkoutRepository(
      SupabaseWorkoutRepository(client),
      ref.watch(sharedPreferencesProvider),
    );
  }
  return DriftWorkoutRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(exerciseRepositoryProvider),
  );
});

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) return SupabaseTemplateRepository(client);
  return DriftTemplateRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(exerciseRepositoryProvider),
  );
});

final bodyWeightRepositoryProvider = Provider<BodyWeightRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) return SupabaseBodyWeightRepository(client);
  return DriftBodyWeightRepository(ref.watch(appDatabaseProvider));
});

final personalRecordRepositoryProvider = Provider<PersonalRecordRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return SupabasePersonalRecordRepository(client);
  }
  return DriftPersonalRecordRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(exerciseRepositoryProvider),
  );
});

final userGoalRepositoryProvider = Provider<UserGoalRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) return SupabaseUserGoalRepository(client);
  return DriftUserGoalRepository(ref.watch(appDatabaseProvider));
});

final powerLiftRecordRepositoryProvider = Provider<PowerLiftRecordRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) return SupabasePowerLiftRecordRepository(client);
  return DriftPowerLiftRecordRepository(ref.watch(appDatabaseProvider));
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return OfflineCachedUserRepository(
      SupabaseUserRepository(client),
      ref.watch(sharedPreferencesProvider),
      _currentUid(client),
    );
  }
  return DriftUserRepository(ref.watch(appDatabaseProvider));
});
