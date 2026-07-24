import 'package:drift/drift.dart';

/// 11 張表對應 CoreData 的 11 個 entity。
/// 對照表見 docs/COREDATA_MIGRATION_SPEC.md 第 2 節 + 附錄 B(schema_dump.sql 實測)。
/// 命名慣例:UUID -> TEXT(標準 8-4-4-4-12 格式)、Date -> INTEGER(Unix epoch 毫秒)、Bool -> BOOLEAN。

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get email => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_body_weights_user_id', columns: {#userId})
class BodyWeights extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  RealColumn get weight => real().withDefault(const Constant(0.0))();
  DateTimeColumn get measuredAt => dateTime()();
  TextColumn get note => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_workouts_user_id', columns: {#userId})
class Workouts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get duration => integer().withDefault(const Constant(0)).nullable()();
  RealColumn get totalVolume => real().withDefault(const Constant(0.0))();
  IntColumn get totalSets => integer().withDefault(const Constant(0))();
  IntColumn get totalExercises => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  // 故意不加 FK——舊資料的 denormalized UUID 會懸空(fixture 已實證),照抄保留原值。
  TextColumn get templateId => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_workout_exercises_workout_id', columns: {#workoutId})
@TableIndex(name: 'idx_workout_exercises_exercise_id', columns: {#exerciseId})
class WorkoutExercises extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId =>
      text().references(Workouts, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  TextColumn get exerciseName => text().nullable()();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  RealColumn get totalVolume => real().withDefault(const Constant(0.0))();
  IntColumn get totalSets => integer().withDefault(const Constant(0))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isCustomExercise =>
      boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_workout_sets_workout_exercise_id', columns: {#workoutExerciseId})
class WorkoutSets extends Table {
  TextColumn get id => text()();
  TextColumn get workoutExerciseId =>
      text().references(WorkoutExercises, #id, onDelete: KeyAction.cascade)();
  IntColumn get setNumber => integer().withDefault(const Constant(0))();
  RealColumn get weight => real().withDefault(const Constant(0.0))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  RealColumn get volume => real().withDefault(const Constant(0.0))();
  RealColumn get rpe => real().withDefault(const Constant(0.0)).nullable()();
  IntColumn get restSeconds => integer().withDefault(const Constant(0)).nullable()();
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_exercises_user_id', columns: {#userId})
class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get nameEn => text().nullable()();
  TextColumn get categoryId => text()();
  TextColumn get type => text()();
  TextColumn get movementPattern => text().nullable()();
  TextColumn get primaryMuscleGroup => text().nullable()();
  TextColumn get descriptionText => text().nullable()();
  TextColumn get videoURL => text().nullable()();
  TextColumn get imageURL => text().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get userId => text().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_templates_user_id', columns: {#userId})
class Templates extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get name => text()();
  TextColumn get descriptionText => text().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_template_exercises_template_id', columns: {#templateId})
class TemplateExercises extends Table {
  TextColumn get id => text()();
  TextColumn get templateId =>
      text().references(Templates, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  IntColumn get suggestedSets => integer().withDefault(const Constant(0)).nullable()();
  IntColumn get suggestedReps => integer().withDefault(const Constant(0)).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PersonalRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  RealColumn get oneRepMax => real().withDefault(const Constant(0.0))();
  RealColumn get weight => real().withDefault(const Constant(0.0))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  DateTimeColumn get achievedAt => dateTime()();
  // 故意不加 FK——舊資料的 denormalized UUID 會懸空(fixture 已實證),照抄保留原值。
  TextColumn get workoutId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class UserGoals extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  RealColumn get targetWeight => real().withDefault(const Constant(0.0)).nullable()();
  IntColumn get weeklyWorkoutGoal => integer().withDefault(const Constant(0))();
  RealColumn get chestVolumeGoal => real().withDefault(const Constant(0.0)).nullable()();
  RealColumn get backVolumeGoal => real().withDefault(const Constant(0.0)).nullable()();
  RealColumn get legsVolumeGoal => real().withDefault(const Constant(0.0)).nullable()();
  RealColumn get shouldersVolumeGoal => real().withDefault(const Constant(0.0)).nullable()();
  RealColumn get armsVolumeGoal => real().withDefault(const Constant(0.0)).nullable()();
  RealColumn get coreVolumeGoal => real().withDefault(const Constant(0.0)).nullable()();
  BoolColumn get restDayReminder => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class PowerLiftRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().references(Users, #id)();
  TextColumn get lift => text()();
  RealColumn get oneRepMax => real().withDefault(const Constant(0.0))();
  RealColumn get weight => real().withDefault(const Constant(0.0))();
  IntColumn get reps => integer().withDefault(const Constant(1))();
  DateTimeColumn get achievedAt => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
