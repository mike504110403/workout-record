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

/// 多一筆引用自建動作 custom-ex-1 的 PR(seedLegacyData 的 pr-1 引用系統動作)。
/// [workoutId] 是 PR 的軟引用(沒有 FK)。
Future<void> _addCustomExercisePr(AppDatabase db, {String? workoutId}) async {
  final t0 = DateTime.utc(2025, 1, 1);
  await db.into(db.personalRecords).insert(PersonalRecordsCompanion.insert(
        id: 'pr-2',
        userId: legacyUserId,
        exerciseId: 'custom-ex-1',
        oneRepMax: const Value(50),
        achievedAt: t0,
        workoutId: Value(workoutId),
        createdAt: t0,
        updatedAt: t0,
      ));
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
      // pr-1 的 workout_id(軟引用)指向被佔用的 w-1:PR 也屬於對方,同樣剔除。
      expect(result.unownedCounts,
          {'workouts': 1, 'workout_exercises': 2, 'workout_sets': 3, 'personal_records': 1});
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

    test('自建動作不可見 → 建本人複本(確定性 id),引用它的子列改指複本且全部送出,略過數 0', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      await _addCustomExercisePr(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': other};
      final copyId = cloudUploadExerciseCopyId(uid, 'custom-ex-1');

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, isEmpty);
      // 複本:欄位照舊列、本人擁有、非系統動作。
      final copy = sink.table('exercises')[copyId]!;
      expect(copy['user_id'], uid);
      expect(copy['is_system'], isFalse);
      expect(copy['name'], '自創動作');
      expect(copy['category_id'], '00000000-0000-0000-0000-000000000001');
      expect(sink.table('exercises')['custom-ex-1']!['user_id'], other, reason: '別人的列不動');
      // 子列全部送出、exercise_id 改指複本。
      expect(sink.table('workout_exercises').keys.toSet(), {'we-1', 'we-2'});
      expect(sink.table('workout_exercises')['we-2']!['exercise_id'], copyId);
      expect(sink.table('workout_sets').keys.toSet(), {'ws-1', 'ws-2', 'ws-3'});
      expect(sink.table('template_exercises')['user-te-2']!['exercise_id'], copyId);
      expect(sink.table('personal_records')['pr-2']!['exercise_id'], copyId);
      expect(result.tableCounts['exercises'], 1);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
      expect(prefs.getBool(cloudUploadLegacyCompletedKey(uid)), isTrue, reason: 'v1 旗標同時寫(防降版整份重傳)');
      expect(sink.recomputeCalls, isEmpty, reason: '主路徑本機總量已含,不重算');
      // 本機 Drift 不改(只改送出的 payload)。
      final localWe2 = await (db.select(db.workoutExercises)..where((t) => t.id.equals('we-2'))).getSingle();
      expect(localWe2.exerciseId, 'custom-ex-1');
    });

    test('自建動作不可見但雲端有同名同分類系統動作 → 改指系統動作,不建複本', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': other};
      sink.systemExercises
          .add({'id': 'cloud-sys-same', 'name': '自創動作', 'category_id': '00000000-0000-0000-0000-000000000001'});

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('exercises').containsKey(cloudUploadExerciseCopyId(uid, 'custom-ex-1')), isFalse);
      expect(sink.table('workout_exercises')['we-2']!['exercise_id'], 'cloud-sys-same');
      expect(sink.table('template_exercises')['user-te-2']!['exercise_id'], 'cloud-sys-same');
      expect(sink.count('workout_sets'), 3);
      expect(result.unownedCounts, isEmpty);
      expect(result.tableCounts['exercises'], 0);
    });

    test('複本建好後子表失敗(不寫旗標)再重試:複本 id 相同、雲端不多建', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': other};
      // template_exercises 送出前已建好複本,workout_exercises 才失敗。
      sink.failOnTable = 'workout_exercises';
      final uploader = DriftToSupabaseUploader(prefs: prefs);

      final first = await uploader.uploadIfNeeded(db, sink);
      expect(first.success, isFalse);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isNull);
      expect(sink.table('exercises').keys.toSet(), {'custom-ex-1', cloudUploadExerciseCopyId(uid, 'custom-ex-1')},
          reason: '第一次已建好複本');
      final second = await uploader.uploadIfNeeded(db, sink);

      expect(second.success, isTrue, reason: second.errorMessage);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
      final copyId = cloudUploadExerciseCopyId(uid, 'custom-ex-1');
      expect(sink.table('exercises').keys.toSet(), {'custom-ex-1', copyId});
      expect(sink.table('workout_exercises')['we-2']!['exercise_id'], copyId);
      expect(second.unownedCounts, isEmpty);
    });

    test('複本送出後仍不可見 → 引用它的子列全部剔除計入略過,上傳照常完成、寫旗標', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': other};
      final copyId = cloudUploadExerciseCopyId(uid, 'custom-ex-1');
      sink.table('exercises')[copyId] = {'id': copyId, 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
      expect(result.unownedCounts,
          {'exercises': 1, 'template_exercises': 1, 'workout_exercises': 1, 'workout_sets': 1});
      // 引用 custom-ex-1 的子列不送(不撞 FK),其餘照送。
      expect(sink.table('workout_exercises').keys.toSet(), {'we-1'});
      expect(sink.table('workout_sets').keys.toSet(), {'ws-1', 'ws-2'});
      expect(sink.table('template_exercises').keys.toSet(), {'user-te-1'});
      expect(result.tableCounts['exercises'], 0, reason: '看不見的複本不算本人可用');
      expect(sink.table('exercises')[copyId]!['user_id'], other, reason: '別人的列不動');
    });

    test('引用不可見自建動作的子列全因父列不可見而剔除 → 不建複本(不把對方的動作複製進本人帳號)', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      // 整份歷史屬於別人:動作、模板、訓練都被對方佔用。
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': other};
      sink.table('templates')['user-tpl-1'] = {'id': 'user-tpl-1', 'user_id': other};
      sink.table('workouts')['w-1'] = {'id': 'w-1', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('exercises').keys.toSet(), {'custom-ex-1'}, reason: '不建複本');
      expect(result.unownedCounts, {
        'exercises': 1,
        'templates': 1,
        'template_exercises': 2,
        'workouts': 1,
        'workout_exercises': 2,
        'workout_sets': 3,
        'personal_records': 1,
      });
      expect(result.tableCounts['exercises'], 0);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('多張子表引用同一不可見自建動作 → 複本只建一次', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      await _addCustomExercisePr(db);
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      // exercises 只有兩次 insert:原始自建動作一批、複本一批。
      expect(sink.insertCalls.where((c) => c.table == 'exercises').map((c) => c.rows), [1, 1]);
      expect(result.tableCounts['exercises'], 1);
    });

    test('不可見且沒被任何子列引用的自建動作 → 照舊計入略過,不建複本', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final t0 = DateTime.utc(2025, 1, 1);
      await db.into(db.exercises).insert(ExercisesCompanion.insert(
            id: 'custom-ex-unused',
            name: '沒用到的動作',
            categoryId: '00000000-0000-0000-0000-000000000001',
            type: 'free_weight',
            userId: const Value(legacyUserId),
            createdAt: t0,
            updatedAt: t0,
          ));
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('exercises')['custom-ex-unused'] = {'id': 'custom-ex-unused', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.unownedCounts, {'exercises': 1});
      expect(sink.table('exercises').keys.toSet(), {'custom-ex-1', 'custom-ex-unused'});
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

    test('PR 的 workout_id 指向被他帳號佔用的 workout → 先剔除該 PR,不為它建複本', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      await _addCustomExercisePr(db, workoutId: 'w-1');
      final sink = await fakeSinkMirroringSeeds(db);
      // 動作、模板、訓練都被對方佔用;只剩 pr-2 會引用不可見的自建動作。
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': other};
      sink.table('templates')['user-tpl-1'] = {'id': 'user-tpl-1', 'user_id': other};
      sink.table('workouts')['w-1'] = {'id': 'w-1', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('exercises').keys.toSet(), {'custom-ex-1'}, reason: '不為對方的 PR 建複本');
      expect(sink.count('personal_records'), 0);
      expect(sink.insertCalls.map((c) => c.table), isNot(contains('personal_records')));
      expect(result.unownedCounts['personal_records'], 2);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('PR 的 workout_id 指向本人可見的 workout 或為 null → 照常送(引用不可見自建動作仍建複本)', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      await _addCustomExercisePr(db, workoutId: 'w-1');
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('personal_records').keys.toSet(), {'pr-1', 'pr-2'});
      expect(sink.table('personal_records')['pr-2']!['exercise_id'], cloudUploadExerciseCopyId(uid, 'custom-ex-1'));
      expect(result.unownedCounts, isEmpty);
    });

    test('本機自建動作 id 大寫、伺服器 uuid 回小寫:被佔用時照樣建複本並改指', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final t0 = DateTime.utc(2025, 1, 1);
      await db.into(db.exercises).insert(ExercisesCompanion.insert(
            id: 'CUSTOM-EX-UP',
            name: '大寫動作',
            categoryId: '00000000-0000-0000-0000-000000000001',
            type: 'free_weight',
            userId: const Value(legacyUserId),
            createdAt: t0,
            updatedAt: t0,
          ));
      await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
          id: 'WE-UP', workoutId: 'w-1', exerciseId: 'CUSTOM-EX-UP', createdAt: t0, updatedAt: t0));
      await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
          id: 'WS-UP', workoutExerciseId: 'WE-UP', createdAt: t0, updatedAt: t0));
      final sink = (await fakeSinkMirroringSeeds(db))..lowercaseIds = true;
      sink.table('exercises')['custom-ex-up'] = {'id': 'custom-ex-up', 'user_id': other};
      final copyId = cloudUploadExerciseCopyId(uid, 'custom-ex-up');

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(cloudUploadExerciseCopyId(uid, 'CUSTOM-EX-UP'), copyId);
      expect(sink.table('exercises')[copyId]!['user_id'], uid);
      expect(sink.table('workout_exercises')['we-up']!['exercise_id'], copyId);
      expect(sink.table('workout_sets').containsKey('ws-up'), isTrue);
      expect(result.unownedCounts, isEmpty);
      expect(result.tableCounts['exercises'], 2, reason: 'custom-ex-1 + 複本');
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

  group('cloudUploadExerciseCopyId', () {
    test('UUID v5(命名空間 6f1d3c2a-…,名稱「uid:舊 id」)對上獨立算出的字面值', () {
      // python3 -c "import uuid;print(uuid.uuid5(uuid.UUID('6f1d3c2a-8b4e-4f7a-9d21-3e5b7c9a0f48'),'u-1:ex-1'))"
      expect(cloudUploadExerciseCopyId('u-1', 'ex-1'), 'a6e87919-515f-50a7-9ced-b41702596cc9');
      expect(cloudUploadExerciseCopyId('u-1', 'EX-1'), 'a6e87919-515f-50a7-9ced-b41702596cc9',
          reason: '舊 id 先正規化成小寫');
    });

    test('不同 uid、同舊 id → 不同 id', () {
      expect(cloudUploadExerciseCopyId('u-2', 'ex-1'), isNot('a6e87919-515f-50a7-9ced-b41702596cc9'));
      expect(cloudUploadExerciseCopyId('u-2', 'ex-1'), isNot(cloudUploadExerciseCopyId('u-1', 'ex-1')));
    });

    test('確定性 UUID:同 uid 同舊 id 相同(舊 id 不分大小寫),換 uid 或舊 id 就不同', () {
      final a = cloudUploadExerciseCopyId(uid, 'custom-ex-1');
      expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(cloudUploadExerciseCopyId(uid, 'custom-ex-1'), a);
      expect(cloudUploadExerciseCopyId(uid, 'CUSTOM-EX-1'), a);
      expect(cloudUploadExerciseCopyId('auth-uid-2', 'custom-ex-1'), isNot(a));
      expect(cloudUploadExerciseCopyId(uid, 'custom-ex-2'), isNot(a));
    });
  });

  group('v1 旗標使用者(已上傳過)→ 只補缺,不整份重傳', () {
    const other = 'someone-else';

    /// 模擬 v1 上傳完成後的雲端:自建動作被別的帳號佔用,引用它的子列當時被略過;
    /// 其餘本人資料都在雲端。
    Future<FakeCloudUploadSink> v1CloudState(AppDatabase db, {required bool exerciseOccupied}) async {
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('exercises')['custom-ex-1'] = {
        'id': 'custom-ex-1',
        'user_id': exerciseOccupied ? other : uid,
      };
      sink.table('templates')['user-tpl-1'] = {'id': 'user-tpl-1', 'user_id': uid};
      sink.table('workouts')['w-1'] = {'id': 'w-1', 'user_id': uid, 'ended_at': 'x'};
      return sink;
    }

    test('引用的自建動作都可見 → 不送任何資料、只寫 v2 旗標', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final sink = await v1CloudState(db, exerciseOccupied: false);
      final before = {for (final e in sink.tables.entries) if (e.value.isNotEmpty) e.key: Map.of(e.value)};

      final result = await DriftToSupabaseUploader(prefs: prefs)
          .uploadIfNeeded(db, sink, ensureUser: const CloudUserProfile(name: 'Mike'));

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.insertCalls, isEmpty);
      expect(sink.ensured, isEmpty);
      expect({for (final e in sink.tables.entries) if (e.value.isNotEmpty) e.key: Map.of(e.value)}, before);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
      expect(prefs.getBool(cloudUploadLegacyCompletedKey(uid)), isTrue, reason: 'v1 旗標保留(防降版整份重傳)');
      expect(sink.recomputeCalls, isEmpty);
      // 第二次:v2 已寫 → 直接略過。
      final again = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);
      expect(again.skipped, isTrue);
    });

    test('有不可見的自建動作 → 只補送引用它的子列(改指複本),父 workout 已刪的跳過,其他表一筆不送', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      await _addCustomExercisePr(db);
      // w-2 也引用自建動作,但使用者上傳後在雲端把 w-2 刪了(雲端沒有)。
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
          id: 'we-3', workoutId: 'w-2', exerciseId: 'custom-ex-1', createdAt: t0, updatedAt: t0));
      await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
          id: 'ws-4', workoutExerciseId: 'we-3', createdAt: t0, updatedAt: t0));
      final sink = await v1CloudState(db, exerciseOccupied: true);
      final copyId = cloudUploadExerciseCopyId(uid, 'custom-ex-1');

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('exercises')[copyId]!['user_id'], uid);
      expect(sink.table('workout_exercises').keys, ['we-2']);
      expect(sink.table('workout_exercises')['we-2']!['exercise_id'], copyId);
      expect(sink.table('workout_sets').keys, ['ws-3']);
      expect(sink.table('template_exercises').keys, ['user-te-2']);
      expect(sink.table('template_exercises')['user-te-2']!['exercise_id'], copyId);
      expect(sink.table('personal_records').keys, ['pr-2']);
      expect(sink.table('personal_records')['pr-2']!['exercise_id'], copyId);
      // 只有複本與受影響子表有送出;其他表(含 workouts 與不引用該動作的子列)一筆不送。
      expect(sink.insertCalls.map((c) => c.table).toSet(),
          {'exercises', 'template_exercises', 'workout_exercises', 'workout_sets', 'personal_records'});
      expect(sink.table('workouts').keys, ['w-1'], reason: '已刪的 w-2 不補回');
      expect(sink.count('body_weights'), 0);
      expect(sink.count('user_goals'), 0);
      expect(result.skippedCounts, {'workout_exercises': 1, 'workout_sets': 1});
      expect(result.unownedCounts, isEmpty);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
      expect(prefs.getBool(cloudUploadLegacyCompletedKey(uid)), isTrue);
      // 有補送子列的已完成訓練只有 w-1(we-2 + ws-3),重算一次;w-2 已刪不補也不重算。
      expect(sink.recomputeCalls, ['w-1']);
      // 「送出筆數」只算子表實際送出列:te-2、we-2、ws-3、pr-2(不含複本)。
      expect(result.uploadedRows, 4);
    });

    test('補送的複本仍不可見 → 引用它的子列剔除計入略過,照常完成、寫 v2', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final sink = await v1CloudState(db, exerciseOccupied: true);
      final copyId = cloudUploadExerciseCopyId(uid, 'custom-ex-1');
      sink.table('exercises')[copyId] = {'id': copyId, 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
      expect(sink.count('workout_exercises'), 0);
      expect(sink.count('template_exercises'), 0);
      expect(result.unownedCounts, {'template_exercises': 1, 'workout_exercises': 1, 'workout_sets': 1});
      expect(result.uploadedRows, 0);
    });

    test('引用不可見自建動作的子列,父列都已在雲端刪除 → 不建複本、不送任何列,寫 v2', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final sink = await v1CloudState(db, exerciseOccupied: true);
      // 使用者上傳後在雲端刪了 w-1 與 user-tpl-1。
      sink.table('workouts').remove('w-1');
      sink.table('templates').remove('user-tpl-1');

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('exercises').keys.toSet(), {'custom-ex-1'}, reason: '不建複本');
      expect(sink.insertCalls, isEmpty);
      expect(result.uploadedRows, 0);
      expect(result.skippedCounts, {'template_exercises': 1, 'workout_exercises': 1, 'workout_sets': 1});
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('候選子列取自上傳計畫:被略過的舊草稿引用不可見自建動作 → 不建複本', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final t0 = DateTime.utc(2025, 1, 3);
      // 兩筆草稿:較舊那筆依規則不上傳,它引用另一個被佔用的自建動作。
      await db.into(db.exercises).insert(ExercisesCompanion.insert(
            id: 'custom-ex-draft',
            name: '草稿用動作',
            categoryId: '00000000-0000-0000-0000-000000000001',
            type: 'free_weight',
            userId: const Value(legacyUserId),
            createdAt: t0,
            updatedAt: t0,
          ));
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          id: 'draft-old', userId: legacyUserId, startedAt: t0, createdAt: t0, updatedAt: t0));
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          id: 'draft-new',
          userId: legacyUserId,
          startedAt: t0.add(const Duration(hours: 1)),
          createdAt: t0,
          updatedAt: t0));
      await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
          id: 'we-draft', workoutId: 'draft-old', exerciseId: 'custom-ex-draft', createdAt: t0, updatedAt: t0));
      final sink = await v1CloudState(db, exerciseOccupied: false);
      sink.table('exercises')['custom-ex-draft'] = {'id': 'custom-ex-draft', 'user_id': other};
      sink.table('workouts')['draft-old'] = {'id': 'draft-old', 'user_id': uid, 'ended_at': 'x'};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.insertCalls, isEmpty);
      expect(sink.table('exercises').containsKey(cloudUploadExerciseCopyId(uid, 'custom-ex-draft')), isFalse);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });
  });

  group('v1 補送(修正輪 2)', () {
    const other = 'someone-else';

    Future<FakeCloudUploadSink> v1CloudState(AppDatabase db) async {
      final sink = await fakeSinkMirroringSeeds(db);
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': other};
      sink.table('templates')['user-tpl-1'] = {'id': 'user-tpl-1', 'user_id': uid};
      sink.table('workouts')['w-1'] = {'id': 'w-1', 'user_id': uid, 'ended_at': 'x'};
      return sink;
    }

    test('系統動作(雲端對不到名稱、以本機種子 id 上傳)被他帳號佔用 → 本人可見父列下引用它的子列補送(建複本)',
        () async {
      // 系統動作種子 id 每台裝置隨機產生(CoreData 匯入對不到名稱的系統動作也沿用原 id),
      // 看不見 = 被別的帳號佔用,v1 時引用它的子列被略過,要補。
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      final seeded = await seedLegacyData(db);
      final bench = seeded.systemExercise;
      final sink = await v1CloudState(db);
      sink.table('exercises')['custom-ex-1'] = {'id': 'custom-ex-1', 'user_id': uid};
      // 引用可見自建動作的子列 v1 時已送出。
      sink.table('workout_exercises')['we-2'] = {'id': 'we-2', 'user_id': uid};
      sink.table('template_exercises')['user-te-2'] = {'id': 'user-te-2', 'user_id': uid};
      // 雲端系統動作沒有同名同分類的 → 計畫裡 bench 以本機種子 id 當使用者動作;該 id 被別人佔用。
      sink.systemExercises.removeWhere((e) => e['name'] == bench.name && e['category_id'] == bench.categoryId);
      sink.table('exercises')[bench.id] = {'id': bench.id, 'user_id': other};
      final copyId = cloudUploadExerciseCopyId(uid, bench.id);

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('exercises')[copyId]!['user_id'], uid);
      expect(sink.table('exercises')[copyId]!['name'], bench.name);
      expect(sink.table('workout_exercises')['we-1']!['exercise_id'], copyId);
      expect(sink.table('workout_sets').keys.toSet(), {'ws-1', 'ws-2'});
      expect(sink.table('template_exercises')['user-te-1']!['exercise_id'], copyId);
      expect(sink.table('personal_records')['pr-1']!['exercise_id'], copyId);
      expect(sink.recomputeCalls, ['w-1']);
      expect(result.uploadedRows, 5, reason: 'te-1、we-1、ws-1、ws-2、pr-1');
      expect(result.unownedCounts, isEmpty);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('子列已在雲端可見(v1 已送出)→ 不重送、不建複本', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      await _addCustomExercisePr(db, workoutId: 'w-1');
      final sink = await v1CloudState(db);
      // custom-ex-1 被他帳號佔用,但引用它的子列都已是本人可見的雲端列
      // (例如當時動作可見、之後才變得不可見)。
      sink.table('workout_exercises')['we-2'] = {'id': 'we-2', 'user_id': uid};
      sink.table('template_exercises')['user-te-2'] = {'id': 'user-te-2', 'user_id': uid};
      sink.table('personal_records')['pr-2'] = {'id': 'pr-2', 'user_id': uid};
      sink.table('workout_sets')['ws-3'] = {'id': 'ws-3', 'user_id': uid};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.insertCalls, isEmpty);
      expect(sink.table('exercises').containsKey(cloudUploadExerciseCopyId(uid, 'custom-ex-1')), isFalse);
      expect(sink.table('workout_sets').keys, ['ws-3'], reason: 'ws-3 已可見,不重送');
      expect(sink.recomputeAttempts, isEmpty);
      expect(result.uploadedRows, 0);
      expect(result.skipped, isTrue);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('部分子列已可見 → 只補不可見的那幾列,複本照建', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final sink = await v1CloudState(db);
      sink.table('workout_exercises')['we-2'] = {'id': 'we-2', 'user_id': uid};
      sink.table('workout_sets')['ws-3'] = {'id': 'ws-3', 'user_id': uid};
      final copyId = cloudUploadExerciseCopyId(uid, 'custom-ex-1');

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('exercises')[copyId]!['user_id'], uid);
      expect(sink.table('template_exercises')['user-te-2']!['exercise_id'], copyId);
      expect(sink.table('workout_exercises')['we-2']!.containsKey('exercise_id'), isFalse, reason: '可見的 we-2 不重送');
      expect(sink.insertCalls.map((c) => c.table).toSet(), {'exercises', 'template_exercises'});
      expect(sink.recomputeAttempts, isEmpty);
      expect(result.uploadedRows, 1);
    });

    test('只建了複本、子列送出後全不可見 → 送出筆數 0(不計複本)、skipped', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final sink = await v1CloudState(db);
      sink.table('template_exercises')['user-te-2'] = {'id': 'user-te-2', 'user_id': other};
      sink.table('workout_exercises')['we-2'] = {'id': 'we-2', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('exercises').containsKey(cloudUploadExerciseCopyId(uid, 'custom-ex-1')), isTrue,
          reason: '複本已建');
      expect(result.uploadedRows, 0);
      expect(result.skipped, isTrue);
      expect(result.unownedCounts, {'template_exercises': 1, 'workout_exercises': 1, 'workout_sets': 1});
      expect(sink.recomputeCalls, isEmpty, reason: '補送的子列不可見 = 沒有本人子列落地');
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('補送套用 PR 的 workout 軟引用:PR 指向雲端不可見的 workout → 剔除,不為它建複本', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
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
          id: 'we-3', workoutId: 'w-2', exerciseId: 'custom-ex-1', createdAt: t0, updatedAt: t0));
      await _addCustomExercisePr(db, workoutId: 'w-2');
      // 只被指向 w-2 的 PR 引用的另一個被佔用自建動作:PR 剔除後不該為它建複本。
      await db.into(db.exercises).insert(ExercisesCompanion.insert(
            id: 'custom-ex-pr',
            name: 'PR 用動作',
            categoryId: '00000000-0000-0000-0000-000000000001',
            type: 'free_weight',
            userId: const Value(legacyUserId),
            createdAt: t0,
            updatedAt: t0,
          ));
      await db.into(db.personalRecords).insert(PersonalRecordsCompanion.insert(
            id: 'pr-3',
            userId: legacyUserId,
            exerciseId: 'custom-ex-pr',
            achievedAt: t0,
            workoutId: const Value('w-2'),
            createdAt: t0,
            updatedAt: t0,
          ));
      // workout_id 為 null 的 PR 不受軟引用影響,照常補送。
      await db.into(db.personalRecords).insert(PersonalRecordsCompanion.insert(
            id: 'pr-4',
            userId: legacyUserId,
            exerciseId: 'custom-ex-1',
            achievedAt: t0,
            createdAt: t0,
            updatedAt: t0,
          ));
      final sink = await v1CloudState(db);
      sink.table('exercises')['custom-ex-pr'] = {'id': 'custom-ex-pr', 'user_id': other};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('workout_exercises').keys, ['we-2'], reason: 'w-2 不可見,we-3 不補');
      expect(sink.table('personal_records').keys, ['pr-4'], reason: '指向不可見 w-2 的 pr-2、pr-3 剔除');
      expect(sink.table('exercises').containsKey(cloudUploadExerciseCopyId(uid, 'custom-ex-pr')), isFalse);
      expect(sink.table('exercises').containsKey(cloudUploadExerciseCopyId(uid, 'custom-ex-1')), isTrue);
      expect(result.skippedCounts, {'workout_exercises': 1, 'personal_records': 2});
      expect(result.unownedCounts, isEmpty);
    });

    test('補送後對有補送子列的訓練各重算一次總量;雲端仍是草稿(WR001)→ 略過該筆、補送照常完成', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final t0 = DateTime.utc(2025, 2, 1);
      // 本機唯一草稿(雲端也有同一筆草稿 → 計畫照常帶上),它也引用被佔用的自建動作。
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          id: 'draft-1', userId: legacyUserId, startedAt: t0, createdAt: t0, updatedAt: t0));
      await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
          id: 'we-d', workoutId: 'draft-1', exerciseId: 'custom-ex-1', createdAt: t0, updatedAt: t0));
      await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
          id: 'ws-d', workoutExerciseId: 'we-d', createdAt: t0, updatedAt: t0));
      // w-1 再多一個引用自建動作的 workout_exercise:同一訓練仍只重算一次。
      await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
          id: 'we-4', workoutId: 'w-1', exerciseId: 'custom-ex-1', createdAt: t0, updatedAt: t0));
      final sink = await v1CloudState(db);
      sink.table('workouts')['draft-1'] = {'id': 'draft-1', 'user_id': uid, 'ended_at': null};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.table('workout_exercises').keys.toSet(), {'we-2', 'we-4', 'we-d'});
      expect(sink.table('workout_sets').keys.toSet(), {'ws-3', 'ws-d'});
      expect(sink.recomputeAttempts.toSet(), {'w-1', 'draft-1'}, reason: '不看本機 ended_at,每筆各試一次');
      expect(sink.recomputeAttempts, hasLength(2));
      expect(sink.recomputeCalls, ['w-1']);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('本機是草稿、雲端已完成(別台裝置完成)→ 照樣重算', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final t0 = DateTime.utc(2025, 2, 1);
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          id: 'draft-1', userId: legacyUserId, startedAt: t0, createdAt: t0, updatedAt: t0));
      await db.into(db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
          id: 'we-d', workoutId: 'draft-1', exerciseId: 'custom-ex-1', createdAt: t0, updatedAt: t0));
      final sink = await v1CloudState(db);
      sink.table('workouts')['draft-1'] = {'id': 'draft-1', 'user_id': uid, 'ended_at': 'y'};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.recomputeCalls.toSet(), {'w-1', 'draft-1'});
    });

    test('重算時 workout 已在雲端刪除(P0002)→ 略過該筆、補送照常完成、寫 v2', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final sink = await v1CloudState(db);
      // 子列送完、重算之前,使用者在別台裝置刪了 w-1。
      sink.afterInsert = (table) {
        if (table == 'workout_sets') sink.table('workouts').remove('w-1');
      };

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(sink.recomputeAttempts, ['w-1']);
      expect(sink.recomputeCalls, isEmpty);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });

    test('重算遇到其他錯誤 → 補送失敗、不寫 v2(下次重試)', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final sink = await v1CloudState(db);
      sink.recomputeFailWith = const PostgrestException(message: 'permission denied', code: '42501');

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isFalse);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isNull);
      expect(prefs.getBool(cloudUploadLegacyCompletedKey(uid)), isTrue);
    });

    test('完成旗標先寫 v1 再寫 v2(兩次寫入間中斷只留 v1,新版走補送、降版也不整份重傳)', () async {
      final (db, _) = await _setUp();
      await seedLegacyData(db);
      final sink = await fakeSinkMirroringSeeds(db);
      final prefs = _RecordingPrefs();

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(prefs.writes, [cloudUploadLegacyCompletedKey(uid), cloudUploadCompletedKey(uid)]);
    });

    test('補送中途 workout_sets 失敗 → v2 未寫、v1 仍在;重試 → 複本只一筆、子列不重複', () async {
      final (db, prefs) = await _setUp({cloudUploadLegacyCompletedKey(uid): true});
      await seedLegacyData(db);
      final sink = await v1CloudState(db);
      sink.failOnTable = 'workout_sets';
      final uploader = DriftToSupabaseUploader(prefs: prefs);
      final copyId = cloudUploadExerciseCopyId(uid, 'custom-ex-1');

      final first = await uploader.uploadIfNeeded(db, sink);

      expect(first.success, isFalse);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isNull);
      expect(prefs.getBool(cloudUploadLegacyCompletedKey(uid)), isTrue);
      expect(uploader.isLegacyCompleted(uid), isTrue, reason: '下次仍走補送,不整份重傳');
      expect(sink.table('exercises').keys.toSet(), {'custom-ex-1', copyId}, reason: '第一次已建好複本');
      expect(sink.table('workout_exercises').keys, ['we-2']);
      expect(sink.count('workout_sets'), 0);
      expect(sink.recomputeCalls, isEmpty);

      final second = await uploader.uploadIfNeeded(db, sink);

      expect(second.success, isTrue, reason: second.errorMessage);
      expect(sink.table('exercises').keys.toSet(), {'custom-ex-1', copyId});
      expect(
          sink.table('exercises').values.where((r) => r['user_id'] == uid && r['name'] == '自創動作'), hasLength(1));
      expect(sink.table('workout_exercises').keys, ['we-2']);
      expect(sink.table('workout_sets').keys, ['ws-3']);
      expect(sink.table('template_exercises').keys, ['user-te-2']);
      expect(sink.recomputeCalls, ['w-1']);
      expect(prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
      expect(prefs.getBool(cloudUploadLegacyCompletedKey(uid)), isTrue);
    });
  });

  group('id 比對大小寫正規化', () {
    test('本機草稿 id 大寫、雲端回同一筆的小寫 → 視為同一筆,照常上傳', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final t = DateTime.utc(2025, 3);
      await db.into(db.workouts).insert(WorkoutsCompanion.insert(
            id: 'DRAFT-UP', userId: legacyUserId, startedAt: t, createdAt: t, updatedAt: t));
      final sink = (await fakeSinkMirroringSeeds(db))..lowercaseIds = true;
      sink.table('workouts')['draft-up'] = {'id': 'draft-up', 'user_id': uid, 'ended_at': null};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.skippedCounts['drafts'], isNull);
    });

    test('本機最新目標 id 大寫、雲端目標是同一筆的小寫 → 照常上傳', () async {
      final (db, prefs) = await _setUp();
      await seedLegacyData(db);
      final t = DateTime.utc(2025, 6);
      await db.into(db.userGoals).insert(UserGoalsCompanion.insert(
            id: 'GOAL-UP', userId: legacyUserId, weeklyWorkoutGoal: const Value(5), createdAt: t, updatedAt: t));
      final sink = (await fakeSinkMirroringSeeds(db))..lowercaseIds = true;
      sink.table('user_goals')['goal-up'] = {'id': 'goal-up', 'user_id': uid};

      final result = await DriftToSupabaseUploader(prefs: prefs).uploadIfNeeded(db, sink);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.skippedCounts['user_goals'], 2, reason: '只略過較舊的兩筆,最新那筆照送');
    });
  });

  group('FakeCloudUploadSink', () {
    test('父列檢查先正規化 id(雲端 uuid 小寫,子列帶大寫引用)', () async {
      final sink = FakeCloudUploadSink(systemExercises: const [], systemTemplates: const [])..lowercaseIds = true;
      await sink.insertIgnoringDuplicates('workouts', [
        {'id': 'W-UP', 'user_id': 'auth-uid-1'},
      ]);
      await sink.insertIgnoringDuplicates('exercises', [
        {'id': 'EX-UP', 'user_id': 'auth-uid-1', 'is_system': false},
      ]);

      await sink.insertIgnoringDuplicates('workout_exercises', [
        {'id': 'we-up', 'user_id': 'auth-uid-1', 'workout_id': 'W-UP', 'exercise_id': 'EX-UP'},
      ]);

      expect(sink.table('workout_exercises').keys, ['we-up']);
    });

    test('與系統動作同 id 判斷先正規化(大寫本機 id 對上小寫系統 id → 不新增列)', () async {
      final sink = FakeCloudUploadSink(
        systemExercises: [
          {'id': 'sys-ex', 'name': 'x', 'category_id': 'c'},
        ],
        systemTemplates: const [],
      )..lowercaseIds = true;

      await sink.insertIgnoringDuplicates('exercises', [
        {'id': 'SYS-EX', 'user_id': 'auth-uid-1', 'is_system': false},
      ]);

      expect(sink.count('exercises'), 0);
      expect(await sink.fetchVisibleIds('exercises', ['SYS-EX']), {'sys-ex'});
    });

    test('批次先驗整批再寫:整批有一列被拒 → 一列都不寫(單一 statement 原子性)', () async {
      final sink = FakeCloudUploadSink(systemExercises: const [], systemTemplates: const []);

      await expectLater(
        sink.insertIgnoringDuplicates('body_weights', [
          {'id': 'bw-ok', 'user_id': 'auth-uid-1'},
          {'id': 'bw-bad', 'user_id': 'someone-else'},
        ]),
        throwsStateError,
      );
      expect(sink.count('body_weights'), 0);
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

/// 只記錄 setBool 順序的 [SharedPreferences](uploader 只用 getBool/setBool)。
class _RecordingPrefs implements SharedPreferences {
  final _values = <String, bool>{};
  final writes = <String>[];

  @override
  bool? getBool(String key) => _values[key];

  @override
  Future<bool> setBool(String key, bool value) async {
    writes.add(key);
    _values[key] = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
