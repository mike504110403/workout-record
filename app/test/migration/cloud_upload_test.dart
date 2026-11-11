// DriftToSupabaseUploader:對應規則、冪等(跑兩次不重複)、失敗後重試、分批與
// 先父後子、草稿與 user_goals 規則。Supabase 端走 [FakeCloudUploadSink](見
// cloud_upload_fakes.dart),本機走 in-memory Drift(含 66 筆系統動作種子)。
import 'dart:async' show TimeoutException;
import 'dart:io' show HandshakeException, SocketException;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
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

  group('上傳後核對', () {
    test('某表有 id 已被別的帳號佔用(本人看不到)→ 仍成功、寫旗標,略過筆數記在該表', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      // 雲端已有同 id 但屬於別的使用者的列:insert 被忽略,本人身分又看不到它。
      sink.table('body_weights')['bw-1'] = {'id': 'bw-1', 'user_id': 'someone-else'};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, {'body_weights': 1});
      expect(result.unownedTotal, 1);
      // 送出後才發現不可見的列,不能同時算進「共 N 筆」。
      expect(result.tableCounts['body_weights'], 0);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
      // 其他表照常送完(後面的表不因略過而中斷)。
      expect(sink.count('power_lift_records'), 1);
    });

    test('多張表各自短少 → 各表略過筆數分開計,總數相加', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('body_weights')['bw-1'] = {'id': 'bw-1', 'user_id': 'someone-else'};
      sink.table('workout_sets')['ws-3'] = {'id': 'ws-3', 'user_id': 'someone-else'};
      sink.table('workout_sets')['ws-1'] = {'id': 'ws-1', 'user_id': 'someone-else'};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, {'body_weights': 1, 'workout_sets': 2});
      expect(result.unownedTotal, 3);
    });

    test('tableCounts/uploadedRows 扣掉回查不可見的列(「共 N 筆」與「略過」不重疊)', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('body_weights')['bw-1'] = {'id': 'bw-1', 'user_id': 'someone-else'};
      sink.table('workout_sets')['ws-3'] = {'id': 'ws-3', 'user_id': 'someone-else'};
      sink.table('workout_sets')['ws-1'] = {'id': 'ws-1', 'user_id': 'someone-else'};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.tableCounts['body_weights'], 0);
      expect(result.tableCounts['workout_sets'], 1); // 3 筆送出、2 筆不可見
      expect(result.tableCounts['workouts'], 1);
      // 全數本人可用時的總和是 1+1+2+1+2+3+1+1+1+1(見第一條測試),扣掉 3 筆不可見。
      expect(result.uploadedRows, (1 + 1 + 2 + 1 + 2 + 3 + 1 + 1 + 1 + 1) - result.unownedTotal);
    });

    test('本機 id 含大寫、伺服器(uuid 型別)回小寫 → 仍判為可見,不算略過', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final t0 = DateTime.utc(2025, 1, 5);
      await db.into(db.bodyWeights).insert(BodyWeightsCompanion.insert(
          id: 'BW-UPPER', userId: legacyUserId, weight: const Value(71), measuredAt: t0, createdAt: t0, updatedAt: t0));
      final sink = (await fakeSinkMirroringSeeds(db))..lowercaseIds = true;

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('body_weights').keys, containsAll(['bw-1', 'bw-upper']));
      expect(result.unownedCounts, isEmpty);
      expect(result.tableCounts['body_weights'], 2);
    });

    test('大寫本機 id 對到別人佔用的小寫 id → 仍判為不可見', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final t0 = DateTime.utc(2025, 1, 5);
      await db.into(db.bodyWeights).insert(BodyWeightsCompanion.insert(
          id: 'BW-UPPER', userId: legacyUserId, weight: const Value(71), measuredAt: t0, createdAt: t0, updatedAt: t0));
      final sink = (await fakeSinkMirroringSeeds(db))..lowercaseIds = true;
      sink.table('body_weights')['bw-upper'] = {'id': 'bw-upper', 'user_id': 'someone-else'};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, {'body_weights': 1});
      expect(result.tableCounts['body_weights'], 1);
    });

    test('沒有撞 id → unownedCounts 為空', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, isEmpty);
      expect(result.unownedTotal, 0);
    });

    test('與雲端系統動作 id 相同的列(RLS 可見)不被算成略過', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      // 雲端系統動作剛好用了本機自建動作的 id:ON CONFLICT 略過 insert,但系統列
      // 對所有人可見,核對時算存在。
      sink.systemExercises.add({'id': 'custom-ex-1', 'name': '雲端系統動作', 'category_id': 'x'});

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('exercises'), isEmpty, reason: '確認這筆確實被 ON CONFLICT 略過');
      expect(result.unownedCounts, isEmpty);
    });

    test('核對查詢失敗(網路等)→ 失敗、不寫旗標', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db)
        ..failOnCount = true
        ..failCountWith = const SocketException('Connection reset');

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isFalse);
      expect(result.failureKind, CloudUploadFailureKind.network);
      expect(result.errorMessage, contains('Connection reset'));
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isNull);
    });

    test('核對依 verifyBatchSize 分批查詢(避免 URL 過長)', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);

      final result = await DriftToSupabaseUploader(prefs: prefs, verifyBatchSize: 2)
          .uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.countCalls.where((c) => c.table == 'workout_sets').map((c) => c.ids), [2, 1]);
      expect(sink.countCalls.every((c) => c.ids <= 2), isTrue);
    });

    test('重試從頭再送(不做檢查點):失敗後重試會重送所有表', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db)..failOnTable = 'workout_sets';
      final uploader = DriftToSupabaseUploader(prefs: prefs);
      await uploader.uploadIfNeeded(db, sink);
      sink.insertCalls.clear();

      final retried = await uploader.uploadIfNeeded(db, sink);

      expect(retried.success, isTrue, reason: retried.errorMessage);
      expect(sink.insertCalls.map((c) => c.table).toSet(), contains('exercises'));
      expect(prefs.getKeys().where((k) => k.contains('table_done')), isEmpty);
    });
  });

  group('父列被別的帳號佔用 → 子列略過不失敗', () {
    const other = 'someone-else';

    test('整批 workouts 不可見 → workout_exercises/workout_sets 全略過,上傳成功、寫旗標', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('workouts')['w-1'] = {'id': 'w-1', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, {'workouts': 1, 'workout_exercises': 2, 'workout_sets': 3});
      expect(sink.insertCalls.map((c) => c.table), isNot(contains('workout_exercises')));
      expect(sink.insertCalls.map((c) => c.table), isNot(contains('workout_sets')));
      expect(sink.count('workout_exercises'), 0);
      expect(sink.count('workout_sets'), 0);
      // 其他表照常送完。
      expect(sink.count('body_weights'), 1);
      expect(sink.count('power_lift_records'), 1);
      expect(result.tableCounts['workout_exercises'], 0);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('自建動作不可見 → 引用它的 workout_exercises/template_exercises/personal_records 略過', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final t0 = DateTime.utc(2025, 1, 1);
      await db.into(db.personalRecords).insert(PersonalRecordsCompanion.insert(
            id: 'pr-2',
            userId: legacyUserId,
            exerciseId: 'custom-ex-1',
            oneRepMax: const Value(50),
            achievedAt: t0,
            createdAt: t0,
            updatedAt: t0,
          ));
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      // we-2 引用不可見動作 → 略過;它的 ws-3 跟著略過(父列沒送)。
      expect(result.unownedCounts, {
        'exercises': 1,
        'template_exercises': 1,
        'workout_exercises': 1,
        'workout_sets': 1,
        'personal_records': 1,
      });
      expect(sink.table('workout_exercises').keys, ['we-1']);
      expect(sink.table('workout_sets').keys.toSet(), {'ws-1', 'ws-2'});
      expect(sink.table('template_exercises').keys, ['user-te-1']);
      expect(sink.table('personal_records').keys, ['pr-1']);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('自建動作與雲端系統動作同 id(RLS 可見)→ 引用它的子列照常送', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.systemExercises.add({'id': 'custom-ex-1', 'name': '雲端系統動作', 'category_id': 'x'});

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, isEmpty);
      expect(sink.table('workout_exercises').keys.toSet(), {'we-1', 'we-2'});
      expect(sink.table('workout_sets').keys.toSet(), {'ws-1', 'ws-2', 'ws-3'});
      expect(sink.table('template_exercises').keys.toSet(), {'user-te-1', 'user-te-2'});
    });

    test('模板不可見 → 其 template_exercises 略過', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('templates')['user-tpl-1'] = {'id': 'user-tpl-1', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, {'templates': 1, 'template_exercises': 2});
      expect(sink.count('template_exercises'), 0);
      expect(sink.count('workouts'), 1);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('部分 workouts 不可見 → 只剔除對應子列', () async {
      final (db, prefs) = await _setUp();
      final seeded = await seedLegacyData(db);
      final t0 = DateTime.utc(2025, 1, 2);
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
            id: 'w-2',
            userId: legacyUserId,
            startedAt: t0,
            endedAt: Value(t0.add(const Duration(hours: 1))),
            createdAt: t0,
            updatedAt: t0,
          ));
      await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
          id: 'we-3', workoutId: 'w-2', exerciseId: seeded.systemExercise.id, createdAt: t0, updatedAt: t0));
      await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
          id: 'ws-4', workoutExerciseId: 'we-3', createdAt: t0, updatedAt: t0));
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('workouts')['w-2'] = {'id': 'w-2', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, {'workouts': 1, 'workout_exercises': 1, 'workout_sets': 1});
      expect(sink.table('workout_exercises').keys.toSet(), {'we-1', 'we-2'});
      expect(sink.table('workout_sets').keys.toSet(), {'ws-1', 'ws-2', 'ws-3'});
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('子列自己的 id 被佔用且父列正常 → 仍照舊核對計入略過', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('workout_exercises')['we-2'] = {'id': 'we-2', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      // we-2 送出被忽略且不可見;它的 ws-3 屬於「父列不可見」→ 剔除而不是撞 FK。
      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, {'workout_exercises': 1, 'workout_sets': 1});
      expect(sink.table('workout_sets').keys.toSet(), {'ws-1', 'ws-2'});
    });
  });

  group('classifyCloudUploadError', () {
    test('網路類', () {
      expect(classifyCloudUploadError(const SocketException('no route')), CloudUploadFailureKind.network);
      expect(classifyCloudUploadError(TimeoutException('slow')), CloudUploadFailureKind.network);
      expect(classifyCloudUploadError(const HandshakeException('tls')), CloudUploadFailureKind.network);
      expect(classifyCloudUploadError(const PostgrestException(message: 'bad gw', code: '502')),
          CloudUploadFailureKind.network);
    });

    test('其他', () {
      expect(classifyCloudUploadError(StateError('boom')), CloudUploadFailureKind.other);
      expect(classifyCloudUploadError(const PostgrestException(message: 'x', code: '22P02')),
          CloudUploadFailureKind.other);
    });

    test('uploadIfNeeded 失敗結果帶 failureKind,原始訊息留在 errorMessage', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db)
        ..failOnTable = 'workouts'
        ..failWith = const SocketException('Failed host lookup');

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.failureKind, CloudUploadFailureKind.network);
      expect(result.errorMessage, contains('Failed host lookup'));
    });
  });
}
