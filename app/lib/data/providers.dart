import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/app_database.dart';
import 'repositories/body_weight_repository.dart';
import 'repositories/exercise_repository.dart';
import 'repositories/personal_record_repository.dart';
import 'repositories/power_lift_record_repository.dart';
import 'repositories/template_repository.dart';
import 'repositories/user_goal_repository.dart';
import 'repositories/user_repository.dart';
import 'repositories/workout_repository.dart';

/// App 唯一的 Drift 資料庫實例。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  return ExerciseRepository(ref.watch(appDatabaseProvider));
});

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(exerciseRepositoryProvider),
  );
});

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(exerciseRepositoryProvider),
  );
});

final bodyWeightRepositoryProvider = Provider<BodyWeightRepository>((ref) {
  return BodyWeightRepository(ref.watch(appDatabaseProvider));
});

final personalRecordRepositoryProvider = Provider<PersonalRecordRepository>((ref) {
  return PersonalRecordRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(exerciseRepositoryProvider),
  );
});

final userGoalRepositoryProvider = Provider<UserGoalRepository>((ref) {
  return UserGoalRepository(ref.watch(appDatabaseProvider));
});

final powerLiftRecordRepositoryProvider = Provider<PowerLiftRecordRepository>((ref) {
  return PowerLiftRecordRepository(ref.watch(appDatabaseProvider));
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(appDatabaseProvider));
});
