// OfflineDraftWorkoutRepository:雲端模式下訓練草稿只存本機、完成時一次上傳。
// 假雲端(FakeCloudWorkoutRepository)不連網並記錄每次呼叫;SharedPreferences
// 用 mock 實例,重建 repository(同一個 prefs)= 模擬 App 重啟。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' as db;
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/offline/offline_draft_workout_repository.dart';
import 'package:workout_record/data/repositories/supabase/supabase_mapping.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';

import '../test_helpers.dart';
import 'fake_cloud_workout_repository.dart';

const _workoutId = 'w-1';
const _we1 = 'we-1';
const _we2 = 'we-2';
const _we3 = 'we-3';
final _t0 = DateTime(2026, 11, 10, 9, 0);
final _endedAt = DateTime(2026, 11, 10, 10, 7, 30);

WorkoutSet _set(
  String id,
  String weId,
  int n,
  double weight,
  int reps, {
  bool warmup = false,
}) => WorkoutSet(
  id: id,
  workoutExerciseId: weId,
  setNumber: n,
  weight: weight,
  reps: reps,
  rpe: 8,
  restSeconds: 90,
  isWarmup: warmup,
  createdAt: _t0,
  updatedAt: _t0,
);

WorkoutExercise _exercise(String id, String exerciseId, int order) =>
    WorkoutExercise(
      id: id,
      workoutId: _workoutId,
      exerciseId: exerciseId,
      exerciseName: 'exercise-$id',
      orderIndex: order,
      createdAt: _t0,
      updatedAt: _t0,
    );

/// 同一份「開始→加動作→加組→改組→刪組→標記完成→刪動作」操作序列,
/// 分別跑在 Drift 版與離線草稿版上比對。exerciseIds 需是 Drift DB 存在的動作。
Future<void> _runScript(
  WorkoutRepository repo,
  List<String> exerciseIds,
) async {
  await repo.create(
    Workout(
      id: _workoutId,
      userId: testUserId,
      startedAt: _t0,
      createdAt: _t0,
      updatedAt: _t0,
    ),
  );
  await repo.addExerciseToWorkout(_exercise(_we1, exerciseIds[0], 0));
  await repo.addExerciseToWorkout(_exercise(_we2, exerciseIds[1], 1));
  await repo.addExerciseToWorkout(_exercise(_we3, exerciseIds[2], 2));

  await repo.addSet(_set('s-1', _we1, 1, 20, 10, warmup: true)); // 暖身,不計
  await repo.addSet(_set('s-2', _we1, 2, 60, 8));
  await repo.addSet(_set('s-3', _we1, 3, 70, 6));
  await repo.addSet(_set('s-4', _we1, 4, 80, 3));
  await repo.addSet(_set('s-5', _we2, 1, 40, 12));
  await repo.addSet(_set('s-6', _we3, 1, 10, 10));

  // 改組:重量/次數改、rpe 清成 null。
  await repo.updateSet(
    WorkoutSet(
      id: 's-3',
      workoutExerciseId: _we1,
      setNumber: 3,
      weight: 72.5,
      reps: 5,
      restSeconds: 120,
      createdAt: _t0,
      updatedAt: _t0,
    ),
  );
  // 刪組:刪中間那組 → 剩餘 setNumber 重編 1..N。
  await repo.deleteSet('s-2', workoutExerciseId: _we1);
  await repo.setExerciseCompleted(_we2, isCompleted: true);
  // 刪動作:刪中間的 we-2 → orderIndex 重編 0..N-1。
  await repo.removeExercise(_we2, workoutId: _workoutId);
}

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  late SharedPreferences prefs;
  late FakeCloudWorkoutRepository cloud;
  late OfflineDraftWorkoutRepository repo;
  const exerciseIds = ['ex-a', 'ex-b', 'ex-c'];

  setUp(() async {
    prefs = await _freshPrefs();
    cloud = FakeCloudWorkoutRepository()..offline = true;
    repo = OfflineDraftWorkoutRepository(cloud, prefs, clock: () => _endedAt);
  });

  group('訓練進行中全程離線', () {
    test('開始→加動作→加組→改組→刪組→標記完成→刪動作:零雲端呼叫,讀回內容正確', () async {
      await _runScript(repo, exerciseIds);

      final draft = await repo.fetchById(_workoutId);
      final viaDraft = await repo.fetchDraft(testUserId);
      expect(cloud.calls, isEmpty);

      expect(draft, isNotNull);
      expect(draft!.endedAt, isNull);
      expect(viaDraft!.id, _workoutId);
      expect(draft.exercises.map((e) => e.id), [_we1, _we3]);
      expect(draft.exercises.map((e) => e.orderIndex), [0, 1]);

      final sets = draft.exercises.first.sets;
      expect(sets.map((s) => s.id), ['s-1', 's-3', 's-4']);
      expect(sets.map((s) => s.setNumber), [1, 2, 3]);
      final edited = sets[1];
      expect(edited.weight, 72.5);
      expect(edited.reps, 5);
      expect(edited.volume, 72.5 * 5);
      expect(edited.rpe, isNull);
      expect(edited.restSeconds, 120);
      expect(edited.updatedAt, _endedAt);
      expect(sets.first.isWarmup, isTrue);
    });

    test('放棄草稿:不打雲端,草稿消失', () async {
      await _runScript(repo, exerciseIds);
      await repo.discardDraft(_workoutId);
      expect(cloud.calls, isEmpty);
      expect(await repo.fetchDraft(testUserId), isNull);
      expect(
        prefs.getKeys().where(
          (k) => k.startsWith(OfflineDraftWorkoutRepository.keyPrefix),
        ),
        isEmpty,
      );
    });

    test('草稿操作的錯誤語義同 Drift:找不到動作/組拋 StateError', () async {
      await _runScript(repo, exerciseIds);
      expect(
        () => repo.removeExercise('nope', workoutId: _workoutId),
        throwsStateError,
      );
      expect(
        () => repo.deleteSet('nope', workoutExerciseId: _we1),
        throwsStateError,
      );
      expect(() => repo.recomputeSummary(_workoutId), throwsStateError);
      expect(cloud.calls, isEmpty);
    });
  });

  group('重啟恢復', () {
    test('重建 repository(同一份本機儲存)後 fetchDraft 拿回完整草稿', () async {
      await _runScript(repo, exerciseIds);
      final before = await repo.fetchById(_workoutId);

      final restarted = OfflineDraftWorkoutRepository(cloud, prefs);
      final recovered = await restarted.fetchDraft(testUserId);

      expect(recovered, isNotNull);
      expect(
        jsonEncode(workoutToNestedJson(recovered!)),
        jsonEncode(workoutToNestedJson(before!)),
      );
      expect(cloud.calls, isEmpty);
    });

    test('草稿依 userId 區隔:別的使用者 fetchDraft 拿不到', () async {
      await _runScript(repo, exerciseIds);
      expect(await repo.fetchDraft('another-user'), isNull);
    });
  });

  group('完成訓練:一次上傳', () {
    test('離線完成 → 拋錯、草稿完整保留;恢復網路後重試成功、只建一筆、本機草稿刪除', () async {
      await _runScript(repo, exerciseIds);
      final before = jsonEncode(
        workoutToNestedJson((await repo.fetchById(_workoutId))!),
      );

      await expectLater(
        repo.completeWorkout(_workoutId),
        throwsA(isA<FakeOfflineException>()),
      );
      expect(cloud.insertCount, 0);
      final kept = await OfflineDraftWorkoutRepository(
        cloud,
        prefs,
      ).fetchDraft(testUserId);
      expect(jsonEncode(workoutToNestedJson(kept!)), before);

      cloud.offline = false;
      final completed = await repo.completeWorkout(_workoutId);

      expect(cloud.insertCount, 1);
      expect(
        cloud.calls.where((c) => c == 'create'),
        hasLength(2),
      ); // 離線那次 + 成功那次
      final uploaded = cloud.rows[_workoutId]!;
      expect(uploaded.endedAt, _endedAt);
      expect(uploaded.exercises.map((e) => e.id), [_we1, _we3]);
      expect(uploaded.exercises.first.sets.map((s) => s.setNumber), [1, 2, 3]);
      expect(completed.endedAt, _endedAt);
      expect(await repo.fetchDraft(testUserId), isNull);
      expect(
        prefs.getKeys().where(
          (k) => k.startsWith(OfflineDraftWorkoutRepository.keyPrefix),
        ),
        isEmpty,
      );
    });

    test('上傳成功但回應遺失(同時斷網)→ 拋錯保留草稿;重試時主鍵衝突、回查已完成 → 視為成功,不重複建立', () async {
      await _runScript(repo, exerciseIds);
      cloud.offline = false;
      cloud.loseNextCreateResponse = true;

      // 回應遺失後網路斷掉,回查也失敗 → 拋錯,草稿保留。
      await expectLater(
        repo.completeWorkout(_workoutId),
        throwsA(isA<FakeOfflineException>()),
      );
      expect(cloud.insertCount, 1);
      expect(await repo.fetchDraft(testUserId), isNotNull);

      cloud.offline = false;

      final retried = await repo.completeWorkout(_workoutId);
      expect(cloud.insertCount, 1);
      expect(retried.id, _workoutId);
      expect(retried.endedAt, isNotNull);
      expect(await repo.fetchDraft(testUserId), isNull);
    });

    test('本機草稿已上傳刪除後再完成同一筆 → 委派雲端 completeWorkout(冪等),不再 create', () async {
      await _runScript(repo, exerciseIds);
      cloud.offline = false;
      final first = await repo.completeWorkout(_workoutId);

      final again = await repo.completeWorkout(_workoutId);

      expect(cloud.insertCount, 1);
      expect(cloud.calls.last, 'completeWorkout');
      expect(again.endedAt, first.endedAt);
      expect(again.totalVolume, first.totalVolume);
    });

    test('統計與 Drift 版一致(總量、組數、動作數、時長;暖身不計)', () async {
      final database = openTestDatabase();
      addTearDown(database.close);
      await seedTestUser(database);
      final exerciseRepo = DriftExerciseRepository(database);
      final systemIds = (await exerciseRepo.fetchSystemExercises())
          .take(3)
          .map((e) => e.id)
          .toList();
      final drift = DriftWorkoutRepository(database, exerciseRepo);

      await _runScript(drift, systemIds);
      await _runScript(repo, systemIds);
      cloud.offline = false;

      final driftDone = await drift.completeWorkout(
        _workoutId,
        endedAt: _endedAt,
      );
      final offlineDone = await repo.completeWorkout(
        _workoutId,
        endedAt: _endedAt,
      );
      final uploaded = cloud.rows[_workoutId]!;

      // we-1:非暖身 72.5×5 + 80×3 = 602.5(暖身 20×10 不計);we-3:10×10 = 100。
      expect(driftDone.totalVolume, 702.5);
      expect(driftDone.totalSets, 3);
      expect(driftDone.totalExercises, 2);
      expect(driftDone.duration, 67);
      for (final w in [offlineDone, uploaded]) {
        expect(w.totalVolume, driftDone.totalVolume);
        expect(w.totalSets, driftDone.totalSets);
        expect(w.totalExercises, driftDone.totalExercises);
        expect(w.duration, driftDone.duration);
        expect(w.endedAt, driftDone.endedAt);
      }
      expect(
        [
          for (final e in uploaded.exercises)
            for (final s in e.sets)
              (s.id, s.setNumber, s.weight, s.reps, s.isWarmup),
        ],
        [
          for (final e in driftDone.exercises)
            for (final s in e.sets)
              (s.id, s.setNumber, s.weight, s.reps, s.isWarmup),
        ],
      );
    });
  });

  group('非本機草稿一律委派雲端', () {
    test('fetchById 不在本機的 id → 問雲端;已完成訓練的 create → 直接上雲端', () async {
      cloud.offline = false;
      expect(await repo.fetchById('remote-only'), isNull);
      await repo.create(
        Workout(
          id: 'done-1',
          userId: testUserId,
          startedAt: _t0,
          endedAt: _endedAt,
          createdAt: _t0,
          updatedAt: _t0,
        ),
      );
      expect(cloud.calls, ['fetchById', 'create']);
      expect(cloud.rows.keys, ['done-1']);
      expect(await repo.fetchDraft(testUserId), isNull);
    });
  });

  test('本機草稿 JSON 與雲端 row 形狀相同(可直接讀回成 Drift row)', () async {
    await _runScript(repo, exerciseIds);
    final raw = prefs.getString(
      '${OfflineDraftWorkoutRepository.keyPrefix}$_workoutId',
    )!;
    final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    expect(workoutRowFromJson(json), isA<db.Workout>());
    expect(json['ended_at'], isNull);
    expect(json['user_id'], testUserId);
  });
}
