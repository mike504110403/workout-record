// cloud_upload 測試共用:記憶體版 [CloudUploadSink] + 本機 Drift fixture。
//
// [FakeCloudUploadSink] 模擬雲端最小約束,讓「先父後子」「對應規則」「冪等」能被
// 真正驗出來:ON CONFLICT (id) DO NOTHING、user_goals unique(user_id)、子表 FK
// (workout_exercises→workouts/exercises、workout_sets→workout_exercises、
// template_exercises→templates/exercises、personal_records→exercises)、
// exercises/templates 不可寫 is_system = true、各表 user_id 必須是登入者(RLS)。
// 父列必須「是本人的」才能被子列引用(對應 RLS 的 exists(... user_id = auth.uid())
// 與 20261111000600 的動作引用限「系統或本人」);別的帳號佔用的父 id 會讓子列被拒。
import 'package:drift/drift.dart' show Value;
import 'package:workout_record/data/db/app_database.dart';
import 'package:workout_record/data/migration/cloud_upload.dart';

class FakeCloudUploadSink implements CloudUploadSink {
  FakeCloudUploadSink({
    this.uid = 'auth-uid-1',
    required this.systemExercises,
    required this.systemTemplates,
  });

  String? uid;
  final List<Map<String, dynamic>> systemExercises;
  final List<Map<String, dynamic>> systemTemplates;

  /// 雲端各表(id → row),不含系統動作/系統模板。
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  final ensured = <({String uid, CloudUserProfile profile})>[];
  final insertCalls = <({String table, int rows})>[];

  /// 非 null:對這張表的下一次 insert 拋錯(拋一次後清除)。
  String? failOnTable;

  /// [failOnTable] 命中時拋的例外;預設 StateError('injected failure ...')。
  Object? failWith;

  /// true:[fetchVisibleIds] 拋 [failCountWith](預設 StateError),模擬核對查詢失敗。
  bool failOnCount = false;
  Object? failCountWith;

  /// true:模擬 Postgres uuid 型別——存入與回查時 id 一律轉小寫(本機若有大寫 id,
  /// 伺服器回的是小寫)。
  bool lowercaseIds = false;

  String _norm(String id) => lowercaseIds ? id.toLowerCase() : id;

  /// 每次 [fetchVisibleIds] 呼叫的表與送查 id 數(驗證分批用)。
  final countCalls = <({String table, int ids})>[];

  Map<String, Map<String, dynamic>> table(String name) => tables.putIfAbsent(name, () => {});

  @override
  String? get currentUid => uid;

  @override
  Future<List<Map<String, dynamic>>> fetchSystemExercises() async => systemExercises;

  @override
  Future<List<Map<String, dynamic>>> fetchSystemTemplates() async => systemTemplates;

  @override
  Future<String?> fetchUserGoalId(String uid) async {
    for (final r in table('user_goals').values) {
      if (r['user_id'] == uid) return r['id'] as String;
    }
    return null;
  }

  @override
  Future<List<String>> fetchDraftWorkoutIds(String uid) async => [
        for (final r in table('workouts').values)
          if (r['user_id'] == uid && r['ended_at'] == null) r['id'] as String,
      ];

  @override
  Future<void> ensureUser(String uid, CloudUserProfile profile) async {
    ensured.add((uid: uid, profile: profile));
    table('users').putIfAbsent(uid, () => {'id': uid, 'name': profile.name});
  }

  /// 動作可被引用:系統動作,或本人的自建動作。
  bool _exerciseExists(Object? id) =>
      table('exercises')[id]?['user_id'] == uid || systemExercises.any((e) => e['id'] == id);

  /// 父列存在且屬於本人(RLS 的 exists 子查詢)。
  bool _ownParent(String parentTable, Object? id) => table(parentTable)[id]?['user_id'] == uid;

  @override
  Future<void> insertIgnoringDuplicates(String name, List<Map<String, dynamic>> rows) async {
    if (failOnTable == name) {
      failOnTable = null;
      throw failWith ?? StateError('injected failure on $name');
    }
    insertCalls.add((table: name, rows: rows.length));
    final t = table(name);
    for (final row in rows) {
      if (row['user_id'] != uid) throw StateError('RLS: $name.user_id = ${row['user_id']}');
      if ((name == 'exercises' || name == 'templates') && row['is_system'] == true) {
        throw StateError('RLS: $name is_system');
      }
      switch (name) {
        case 'workout_exercises':
          if (!_ownParent('workouts', row['workout_id'])) throw StateError('FK workout_id');
          if (!_exerciseExists(row['exercise_id'])) throw StateError('FK exercise_id');
        case 'workout_sets':
          if (!_ownParent('workout_exercises', row['workout_exercise_id'])) {
            throw StateError('FK workout_exercise_id');
          }
        case 'template_exercises':
          if (!_ownParent('templates', row['template_id'])) throw StateError('FK template_id');
          if (!_exerciseExists(row['exercise_id'])) throw StateError('FK exercise_id');
        case 'personal_records':
          if (!_exerciseExists(row['exercise_id'])) throw StateError('FK exercise_id');
        case 'user_goals':
          final clash = t.values.any((r) => r['user_id'] == row['user_id'] && r['id'] != row['id']);
          if (clash) throw StateError('unique user_goals.user_id');
      }
      // 與雲端系統動作/模板同 id:ON CONFLICT (id) DO NOTHING,不新增列。
      final isSystemId = (name == 'exercises' && systemExercises.any((e) => e['id'] == row['id'])) ||
          (name == 'templates' && systemTemplates.any((e) => e['id'] == row['id']));
      if (!isSystemId) t.putIfAbsent(_norm(row['id'] as String), () => Map.of(row));
    }
  }

  /// 模擬 RLS 可見性:本人的列、以及系統動作/模板(is_system 對所有人可讀)看得到;
  /// 別人的同 id 列看不到。
  @override
  Future<Set<String>> fetchVisibleIds(String name, List<String> ids) async {
    countCalls.add((table: name, ids: ids.length));
    if (failOnCount) throw failCountWith ?? StateError('injected count failure on $name');
    final t = table(name);
    final systemIds = switch (name) {
      'exercises' => {for (final e in systemExercises) e['id']},
      'templates' => {for (final e in systemTemplates) e['id']},
      _ => const <Object?>{},
    };
    return {
      for (final id in ids)
        if (t[_norm(id)]?['user_id'] == uid || systemIds.contains(_norm(id))) _norm(id),
    };
  }

  int count(String name) => table(name).length;
}

/// 雲端系統動作/模板:用本機種子的名稱 + 分類,但給不同的 id(模擬雲端 md5 id)。
Future<FakeCloudUploadSink> fakeSinkMirroringSeeds(AppDatabase db, {String uid = 'auth-uid-1'}) async {
  final sysEx = await (db.select(db.exercises)..where((e) => e.isSystem.equals(true))).get();
  final sysTpl = await (db.select(db.templates)..where((t) => t.isSystem.equals(true))).get();
  return FakeCloudUploadSink(
    uid: uid,
    systemExercises: [
      for (final e in sysEx) {'id': 'cloud-${e.id}', 'name': e.name, 'category_id': e.categoryId},
    ],
    systemTemplates: [
      for (final t in sysTpl) {'id': 'cloud-${t.id}', 'name': t.name},
    ],
  );
}

const legacyUserId = 'legacy-apple-user';

/// 一份典型的「舊用戶」本機資料。回傳用到的系統動作/模板,方便斷言。
Future<({Exercise systemExercise, Template systemTemplate})> seedLegacyData(AppDatabase db) async {
  final t0 = DateTime.utc(2025, 1, 1);
  final sysEx = await (db.select(db.exercises)..where((e) => e.isSystem.equals(true))).get();
  final bench = sysEx.first;
  final sysTpl = (await (db.select(db.templates)..where((t) => t.isSystem.equals(true))).get()).first;

  await db.into(db.users).insert(UsersCompanion.insert(
        id: legacyUserId, name: const Value('老用戶'), createdAt: t0, updatedAt: t0));
  await db.into(db.exercises).insert(ExercisesCompanion.insert(
        id: 'custom-ex-1',
        name: '自創動作',
        categoryId: '00000000-0000-0000-0000-000000000001',
        type: 'free_weight',
        userId: const Value(legacyUserId),
        createdAt: t0,
        updatedAt: t0,
      ));
  await db.into(db.templates).insert(TemplatesCompanion.insert(
        id: 'user-tpl-1', name: '我的模板', userId: const Value(legacyUserId), createdAt: t0, updatedAt: t0));
  await db.into(db.templateExercises).insert(TemplateExercisesCompanion.insert(
        id: 'user-te-1', templateId: 'user-tpl-1', exerciseId: bench.id));
  await db.into(db.templateExercises).insert(TemplateExercisesCompanion.insert(
        id: 'user-te-2', templateId: 'user-tpl-1', exerciseId: 'custom-ex-1', orderIndex: const Value(1)));

  await db.into(db.workouts).insert(WorkoutsCompanion.insert(
        id: 'w-1',
        userId: legacyUserId,
        startedAt: t0,
        endedAt: Value(t0.add(const Duration(hours: 1))),
        templateId: Value(sysTpl.id),
        createdAt: t0,
        updatedAt: t0,
      ));
  await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
        id: 'we-1', workoutId: 'w-1', exerciseId: bench.id, createdAt: t0, updatedAt: t0));
  await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
        id: 'we-2', workoutId: 'w-1', exerciseId: 'custom-ex-1', createdAt: t0, updatedAt: t0));
  for (var i = 1; i <= 3; i++) {
    await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
          id: 'ws-$i',
          workoutExerciseId: i == 3 ? 'we-2' : 'we-1',
          setNumber: Value(i),
          weight: const Value(60),
          reps: const Value(5),
          createdAt: t0,
          updatedAt: t0,
        ));
  }
  await db.into(db.bodyWeights).insert(BodyWeightsCompanion.insert(
        id: 'bw-1', userId: legacyUserId, weight: const Value(70), measuredAt: t0, createdAt: t0, updatedAt: t0));
  await db.into(db.personalRecords).insert(PersonalRecordsCompanion.insert(
        id: 'pr-1',
        userId: legacyUserId,
        exerciseId: bench.id,
        oneRepMax: const Value(80),
        achievedAt: t0,
        workoutId: const Value('w-1'),
        createdAt: t0,
        updatedAt: t0,
      ));
  await db.into(db.userGoals).insert(UserGoalsCompanion.insert(
        id: 'goal-old', userId: legacyUserId, weeklyWorkoutGoal: const Value(2), createdAt: t0, updatedAt: t0));
  await db.into(db.userGoals).insert(UserGoalsCompanion.insert(
        id: 'goal-new',
        userId: legacyUserId,
        weeklyWorkoutGoal: const Value(4),
        createdAt: t0,
        updatedAt: t0.add(const Duration(days: 30)),
      ));
  await db.into(db.powerLiftRecords).insert(PowerLiftRecordsCompanion.insert(
        id: 'pl-1', userId: legacyUserId, lift: 'squat', achievedAt: t0, createdAt: t0, updatedAt: t0));
  return (systemExercise: bench, systemTemplate: sysTpl);
}
