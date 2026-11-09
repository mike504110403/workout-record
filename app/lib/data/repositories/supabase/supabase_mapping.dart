// Supabase 版 repository 的共用轉換層。
//
// 讀:PostgREST 回傳的 JSON(snake_case 欄名、timestamptz 為 ISO 字串)→ Drift
// 的 data class(`db.Workout` 等),再交給各 model 既有的 `fromRow` 轉成 domain
// model——讓 Supabase 版與 Drift 版走同一條 row → model 轉換,不重寫兩份。
//
// 寫:各 model 既有的 `toCompanion()` → [companionToJson](Drift companion 的
// `toColumns` 本來就是以 SQL 欄名為 key,Postgres schema 刻意沿用同一套欄名,
// 只有 [kDriftToPgColumn] 列出的兩個例外要改名)。
import 'package:drift/drift.dart' show UpdateCompanion, Variable;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../db/app_database.dart' as db;

/// Drift 產生的 SQL 欄名 → Postgres 欄名的例外清單(其餘同名)。
/// Drift 把 `videoURL` 轉成 `video_u_r_l`,Postgres 這邊用可讀的 `video_url`。
const kDriftToPgColumn = <String, String>{
  'video_u_r_l': 'video_url',
  'image_u_r_l': 'image_url',
};

/// Drift companion → PostgREST 可送出的 JSON(只含 companion 裡 present 的欄位)。
/// DateTime 一律轉 UTC ISO 8601,交給 timestamptz。
Map<String, dynamic> companionToJson(UpdateCompanion<dynamic> companion) {
  final out = <String, dynamic>{};
  companion.toColumns(false).forEach((column, expression) {
    final value = (expression as Variable<Object>).value;
    out[kDriftToPgColumn[column] ?? column] = encodeValue(value);
  });
  return out;
}

/// 單一值轉 JSON:DateTime → UTC ISO 8601,其餘原樣。
Object? encodeValue(Object? value) => value is DateTime ? value.toUtc().toIso8601String() : value;

/// 目前登入者的 auth uid。Supabase 版一律以它為資料擁有者(RLS 也以它判斷),
/// 未登入直接拋錯。
String requireUid(SupabaseClient client) {
  final id = client.auth.currentUser?.id;
  if (id == null) {
    throw StateError('Supabase 資料層需要登入(auth.currentUser 為 null)');
  }
  return id;
}

/// RPC 約定錯誤碼 → StateError,對齊 Drift 版「找不到列/狀態不允許就拋
/// StateError」的語義(錯誤碼定義見 supabase/migrations/20261110000300_rpc.sql 檔頭)。
Future<T> rethrowAsStateError<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PostgrestException catch (e) {
    if (e.code == 'P0002' || e.code == 'WR001') {
      throw StateError(e.message);
    }
    rethrow;
  }
}

// ---------- 值解析 ----------

DateTime _dt(Object? v) => DateTime.parse(v! as String).toLocal();
DateTime? _dtn(Object? v) => v == null ? null : _dt(v);
double _d(Object? v) => (v! as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
int _i(Object? v) => (v! as num).toInt();
int? _in(Object? v) => v == null ? null : (v as num).toInt();
String _s(Object? v) => v! as String;
String? _sn(Object? v) => v as String?;
bool _b(Object? v) => v! as bool;

// ---------- JSON → Drift row ----------

db.User userRowFromJson(Map<String, dynamic> j) => db.User(
      id: _s(j['id']),
      name: _sn(j['name']),
      email: _sn(j['email']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

db.BodyWeight bodyWeightRowFromJson(Map<String, dynamic> j) => db.BodyWeight(
      id: _s(j['id']),
      userId: _s(j['user_id']),
      weight: _d(j['weight']),
      measuredAt: _dt(j['measured_at']),
      note: _sn(j['note']),
      isSynced: _b(j['is_synced']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

db.Workout workoutRowFromJson(Map<String, dynamic> j) => db.Workout(
      id: _s(j['id']),
      userId: _s(j['user_id']),
      startedAt: _dt(j['started_at']),
      endedAt: _dtn(j['ended_at']),
      duration: _in(j['duration']),
      totalVolume: _d(j['total_volume']),
      totalSets: _i(j['total_sets']),
      totalExercises: _i(j['total_exercises']),
      note: _sn(j['note']),
      templateId: _sn(j['template_id']),
      isSynced: _b(j['is_synced']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

db.WorkoutExercise workoutExerciseRowFromJson(Map<String, dynamic> j) => db.WorkoutExercise(
      id: _s(j['id']),
      workoutId: _s(j['workout_id']),
      exerciseId: _s(j['exercise_id']),
      exerciseName: _sn(j['exercise_name']),
      orderIndex: _i(j['order_index']),
      totalVolume: _d(j['total_volume']),
      totalSets: _i(j['total_sets']),
      isCompleted: _b(j['is_completed']),
      isCustomExercise: _b(j['is_custom_exercise']),
      note: _sn(j['note']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

db.WorkoutSet workoutSetRowFromJson(Map<String, dynamic> j) => db.WorkoutSet(
      id: _s(j['id']),
      workoutExerciseId: _s(j['workout_exercise_id']),
      setNumber: _i(j['set_number']),
      weight: _d(j['weight']),
      reps: _i(j['reps']),
      volume: _d(j['volume']),
      rpe: _dn(j['rpe']),
      restSeconds: _in(j['rest_seconds']),
      isWarmup: _b(j['is_warmup']),
      note: _sn(j['note']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

db.Exercise exerciseRowFromJson(Map<String, dynamic> j) => db.Exercise(
      id: _s(j['id']),
      name: _s(j['name']),
      nameEn: _sn(j['name_en']),
      categoryId: _s(j['category_id']),
      type: _s(j['type']),
      movementPattern: _sn(j['movement_pattern']),
      primaryMuscleGroup: _sn(j['primary_muscle_group']),
      descriptionText: _sn(j['description_text']),
      videoURL: _sn(j['video_url']),
      imageURL: _sn(j['image_url']),
      isSystem: _b(j['is_system']),
      isActive: _b(j['is_active']),
      userId: _sn(j['user_id']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

db.Template templateRowFromJson(Map<String, dynamic> j) => db.Template(
      id: _s(j['id']),
      userId: _sn(j['user_id']),
      name: _s(j['name']),
      descriptionText: _sn(j['description_text']),
      isSystem: _b(j['is_system']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

db.TemplateExercise templateExerciseRowFromJson(Map<String, dynamic> j) => db.TemplateExercise(
      id: _s(j['id']),
      templateId: _s(j['template_id']),
      exerciseId: _s(j['exercise_id']),
      orderIndex: _i(j['order_index']),
      suggestedSets: _in(j['suggested_sets']),
      suggestedReps: _in(j['suggested_reps']),
    );

db.PersonalRecord personalRecordRowFromJson(Map<String, dynamic> j) => db.PersonalRecord(
      id: _s(j['id']),
      userId: _s(j['user_id']),
      exerciseId: _s(j['exercise_id']),
      oneRepMax: _d(j['one_rep_max']),
      weight: _d(j['weight']),
      reps: _i(j['reps']),
      achievedAt: _dt(j['achieved_at']),
      workoutId: _sn(j['workout_id']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

db.UserGoal userGoalRowFromJson(Map<String, dynamic> j) => db.UserGoal(
      id: _s(j['id']),
      userId: _s(j['user_id']),
      targetWeight: _dn(j['target_weight']),
      weeklyWorkoutGoal: _i(j['weekly_workout_goal']),
      chestVolumeGoal: _dn(j['chest_volume_goal']),
      backVolumeGoal: _dn(j['back_volume_goal']),
      legsVolumeGoal: _dn(j['legs_volume_goal']),
      shouldersVolumeGoal: _dn(j['shoulders_volume_goal']),
      armsVolumeGoal: _dn(j['arms_volume_goal']),
      coreVolumeGoal: _dn(j['core_volume_goal']),
      restDayReminder: _b(j['rest_day_reminder']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

db.PowerLiftRecord powerLiftRecordRowFromJson(Map<String, dynamic> j) => db.PowerLiftRecord(
      id: _s(j['id']),
      userId: _s(j['user_id']),
      lift: _s(j['lift']),
      oneRepMax: _d(j['one_rep_max']),
      weight: _d(j['weight']),
      reps: _i(j['reps']),
      achievedAt: _dt(j['achieved_at']),
      note: _sn(j['note']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );
