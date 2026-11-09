// DriftToSupabaseUploader:對應規則、冪等(跑兩次不重複)、失敗後重試、分批與
// 先父後子、草稿與 user_goals 規則。Supabase 端走 [FakeCloudUploadSink](見
// cloud_upload_fakes.dart),本機走 in-memory Drift(含 66 筆系統動作種子)。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/db/app_database.dart';
import 'package:workout_record/data/migration/cloud_upload.dart';

import '../data/test_helpers.dart';
import 'cloud_upload_fakes.dart';

const uid = 'auth-uid-1';

Future<(AppDatabase, SharedPreferences)> _setUp([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  return (db, p);
}

void main() {
  test('對應規則:user_id 改寫 auth uid、系統動作/模板對到雲端 id 不上傳、自建照搬、goal 取最新', () async {
    final (db, prefs) = await _setUp();
    final seeded = await seedLegacyData(db);
    final sink = await fakeSinkMirroringSeeds(db);

    final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

    expect(result.success, isTrue, reason: result.errorMessage);
    final cloudBench = 'cloud-${seeded.systemExercise.id}';
    // 每張表的 user_id 都是 auth uid(fake sink 也會擋,這裡再明確斷言一次)。
    for (final t in sink.tables.entries.where((e) => e.key != 'users')) {
      for (final row in t.value.values) {
        expect(row['user_id'], uid, reason: '${t.key} ${row['id']}');
      }
    }
    // 只上傳自建動作,保留本機 id,is_system = false。
    expect(sink.table('exercises').keys, ['custom-ex-1']);
    expect(sink.table('exercises')['custom-ex-1']!['is_system'], isFalse);
    // 系統模板不上傳;使用者模板照搬。
    expect(sink.table('templates').keys, ['user-tpl-1']);
    expect(sink.table('template_exercises')['user-te-1']!['exercise_id'], cloudBench);
    expect(sink.table('template_exercises')['user-te-2']!['exercise_id'], 'custom-ex-1');
    // 訓練:template_id 改寫成雲端系統模板 id;子表 exercise_id 對應。
    expect(sink.table('workouts')['w-1']!['template_id'], 'cloud-${seeded.systemTemplate.id}');
    expect(sink.table('workout_exercises')['we-1']!['exercise_id'], cloudBench);
    expect(sink.table('workout_exercises')['we-2']!['exercise_id'], 'custom-ex-1');
    expect(sink.count('workout_sets'), 3);
    expect(sink.table('personal_records')['pr-1']!['exercise_id'], cloudBench);
    expect(sink.table('personal_records')['pr-1']!['workout_id'], 'w-1');
    // user_goals:多筆取 updatedAt 最新一筆。
    expect(sink.table('user_goals').keys, ['goal-new']);
    expect(sink.table('user_goals')['goal-new']!['weekly_workout_goal'], 4);
    expect(result.skippedCounts['user_goals'], 1);
    expect(sink.count('body_weights'), 1);
    expect(sink.count('power_lift_records'), 1);
    // DateTime 轉 UTC ISO 字串。
    expect(sink.table('workouts')['w-1']!['started_at'], '2025-01-01T00:00:00.000Z');
    expect(result.uploadedRows, 1 + 1 + 2 + 1 + 2 + 3 + 1 + 1 + 1 + 1);
    expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
  });

  test('先父後子:表順序固定,且依 batchSize 分批', () async {
    final (db, prefs) = await _setUp();
    await seedLegacyData(db);
    final sink = await fakeSinkMirroringSeeds(db);

    final result = await DriftToSupabaseUploader(prefs: prefs, batchSize: 2).uploadIfNeeded(db, sink);

    expect(result.success, isTrue, reason: result.errorMessage);
    final order = <String>[];
    for (final c in sink.insertCalls) {
      if (order.isEmpty || order.last != c.table) order.add(c.table);
    }
    expect(order, [
      'exercises', 'templates', 'template_exercises', 'workouts', 'workout_exercises',
      'workout_sets', 'body_weights', 'personal_records', 'user_goals', 'power_lift_records',
    ]);
    // workout_sets 3 列 → 2 + 1 兩批。
    expect(sink.insertCalls.where((c) => c.table == 'workout_sets').map((c) => c.rows), [2, 1]);
    expect(sink.insertCalls.every((c) => c.rows <= 2), isTrue);
  });

  test('冪等:旗標已寫 → 不碰雲端;清掉旗標重跑 → 雲端列數不變', () async {
    final (db, prefs) = await _setUp();
    await seedLegacyData(db);
    final sink = await fakeSinkMirroringSeeds(db);
    final uploader = DriftToSupabaseUploader(prefs: prefs);

    await uploader.uploadIfNeeded(db, sink);
    final snapshot = {for (final e in sink.tables.entries) e.key: e.value.length};
    final callsAfterFirst = sink.insertCalls.length;

    final second = await uploader.uploadIfNeeded(db, sink);
    expect(second.success, isTrue);
    expect(second.skipped, isTrue);
    expect(sink.insertCalls.length, callsAfterFirst);

    await prefs.remove(cloudUploadCompletedKey(uid));
    final third = await uploader.uploadIfNeeded(db, sink);
    expect(third.success, isTrue, reason: third.errorMessage);
    expect({for (final e in sink.tables.entries) e.key: e.value.length}, snapshot);
  });

  test('旗標依 auth uid 區分:別的 uid 不受已上傳旗標影響', () async {
    final (db, prefs) = await _setUp({'cloud_upload_completed_someone-else': true});
    await seedLegacyData(db);
    final sink = await fakeSinkMirroringSeeds(db);

    final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

    expect(result.skipped, isFalse);
    expect(sink.count('workouts'), 1);
  });

  test('中途失敗:不寫旗標、回 failure;重試後補齊且不重複', () async {
    final (db, prefs) = await _setUp();
    await seedLegacyData(db);
    final sink = await fakeSinkMirroringSeeds(db)..failOnTable = 'workout_sets';
    final uploader = DriftToSupabaseUploader(prefs: prefs);

    final failed = await uploader.uploadIfNeeded(db, sink);
    expect(failed.success, isFalse);
    expect(failed.errorMessage, contains('injected failure'));
    expect(prefs.getBool(cloudUploadCompletedKey(uid)), isNull);
    expect(sink.count('workouts'), 1, reason: '父表已在失敗前送出');
    expect(sink.count('workout_sets'), 0);

    final retried = await uploader.uploadIfNeeded(db, sink);
    expect(retried.success, isTrue, reason: retried.errorMessage);
    expect(sink.count('workouts'), 1);
    expect(sink.count('workout_exercises'), 2);
    expect(sink.count('workout_sets'), 3);
    expect(sink.count('user_goals'), 1);
    expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
  });

  test('未登入(sink 無 uid)→ failure,不寫旗標', () async {
    final (db, prefs) = await _setUp();
    await seedLegacyData(db);
    final sink = await fakeSinkMirroringSeeds(db)..uid = null;

    final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

    expect(result.success, isFalse);
    expect(sink.insertCalls, isEmpty);
  });

  test('只有種子(無使用者資料)→ hasUploadableData false、skipped、不寫旗標', () async {
    final (db, prefs) = await _setUp();
    final sink = await fakeSinkMirroringSeeds(db);
    final uploader = DriftToSupabaseUploader(prefs: prefs);

    expect(await uploader.hasUploadableData(db), isFalse);
    final result = await uploader.uploadIfNeeded(db, sink);
    expect(result.skipped, isTrue);
    expect(sink.insertCalls, isEmpty);
    expect(prefs.getBool(cloudUploadCompletedKey(uid)), isNull);
  });

  test('ensureUser:有給 profile 才 ensure users 列(auth uid)', () async {
    final (db, prefs) = await _setUp();
    await seedLegacyData(db);
    final sink = await fakeSinkMirroringSeeds(db);

    await DriftToSupabaseUploader(prefs: prefs)
        .uploadIfNeeded(db, sink, ensureUser: const CloudUserProfile(name: 'Mike'));

    expect(sink.ensured.single.uid, uid);
    expect(sink.ensured.single.profile.name, 'Mike');
  });

  test('對不到雲端的系統動作:被引用 → 改為自建動作上傳;未引用 → 略過', () async {
    final (db, prefs) = await _setUp();
    await seedLegacyData(db);
    final t0 = DateTime.utc(2025);
    for (final id in ['orphan-sys-used', 'orphan-sys-unused']) {
      await db.into(db.exercises).insert(ExercisesCompanion.insert(
            id: id, name: id, categoryId: 'cat-x', type: 'free_weight',
            isSystem: const Value(true), createdAt: t0, updatedAt: t0));
    }
    await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
          id: 'we-3', workoutId: 'w-1', exerciseId: 'orphan-sys-used', createdAt: t0, updatedAt: t0));
    final sink = await fakeSinkMirroringSeeds(db);
    // 雲端系統動作只鏡像原 66 筆種子(移除剛插入的兩筆)。
    sink.systemExercises.removeWhere((e) => (e['name'] as String).startsWith('orphan'));

    final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(sink.table('exercises').keys.toSet(), {'custom-ex-1', 'orphan-sys-used'});
    expect(sink.table('exercises')['orphan-sys-used']!['is_system'], isFalse);
    expect(result.skippedCounts['system_exercises'], 1);
  });

  test('草稿:多筆只上傳 startedAt 最新一筆(含子列),其餘連子列略過', () async {
    final (db, prefs) = await _setUp();
    await seedLegacyData(db);
    final bench = (await (db.select(db.exercises)..where((e) => e.isSystem.equals(true))).get()).first;
    for (final (id, day) in [('draft-old', 1), ('draft-new', 2)]) {
      final t = DateTime.utc(2025, 2, day);
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
            id: id, userId: legacyUserId, startedAt: t, createdAt: t, updatedAt: t));
      await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
            id: '$id-we', workoutId: id, exerciseId: bench.id, createdAt: t, updatedAt: t));
    }
    final sink = await fakeSinkMirroringSeeds(db);

    final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(sink.table('workouts').keys.toSet(), {'w-1', 'draft-new'});
    expect(sink.table('workouts')['draft-new']!['ended_at'], isNull);
    expect(sink.table('workout_exercises').containsKey('draft-new-we'), isTrue);
    expect(sink.table('workout_exercises').containsKey('draft-old-we'), isFalse);
    expect(result.skippedCounts['drafts'], 1);
  });

  test('草稿:雲端已有別的草稿 → 本機草稿全部略過;已是同一筆(重試)→ 照常', () async {
    final (db, prefs) = await _setUp();
    await seedLegacyData(db);
    final t = DateTime.utc(2025, 3);
    await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          id: 'draft-local', userId: legacyUserId, startedAt: t, createdAt: t, updatedAt: t));
    final sink = await fakeSinkMirroringSeeds(db);
    sink.table('workouts')['draft-cloud'] = {'id': 'draft-cloud', 'user_id': uid, 'ended_at': null};

    final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);
    expect(result.success, isTrue, reason: result.errorMessage);
    expect(sink.table('workouts').containsKey('draft-local'), isFalse);
    expect(result.skippedCounts['drafts'], 1);

    // 重試情境:雲端的草稿就是本機那筆 → 不算衝突。
    final (db2, prefs2) = await _setUp();
    await seedLegacyData(db2);
    await db2.into(db2.workouts).insert(WorkoutsCompanion.insert(
          id: 'draft-local', userId: legacyUserId, startedAt: t, createdAt: t, updatedAt: t));
    final sink2 = await fakeSinkMirroringSeeds(db2);
    sink2.table('workouts')['draft-local'] = {'id': 'draft-local', 'user_id': uid, 'ended_at': null};
    final r2 = await DriftToSupabaseUploader(prefs: prefs2).uploadIfNeeded(db2, sink2);
    expect(r2.success, isTrue, reason: r2.errorMessage);
    expect(r2.skippedCounts['drafts'], isNull);
  });

  test('user_goals:雲端已有別筆目標 → 本機目標略過(雲端優先,不撞 unique)', () async {
    final (db, prefs) = await _setUp();
    await seedLegacyData(db);
    final sink = await fakeSinkMirroringSeeds(db);
    sink.table('user_goals')['goal-cloud'] = {'id': 'goal-cloud', 'user_id': uid};

    final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(sink.table('user_goals').keys, ['goal-cloud']);
    expect(result.skippedCounts['user_goals'], 2);
  });
}
