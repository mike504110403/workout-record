// 計畫組(Mike 2026-11-11 裁示 2)與完成規則(裁示 3)的 controller 層測試。
// 真 in-memory DB + 真 repositories + mock SharedPreferences(計畫組附屬儲存)。
// 覆蓋:模板開始後 WorkoutSet 為 0、打勾 +1;重開讀回;完成成功才清、失敗保留;
// 放棄/對話框放棄清掉;GC(換使用者、草稿檢查);完成時 0 組動作被丟棄、草稿
// 0 組不能完成;歷史查詢(fetchRecent)拋錯時開訓與記組照常。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 慢速 remove 的假 store 要直接實作平台介面;它是 shared_preferences 的傳遞
// 依賴(理由同 exercise_picker_controller_test.dart 的同一行)。
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, Exercise;
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/exercise_history.dart';
import 'package:workout_record/features/workout/planned_sets_store.dart';
import 'package:workout_record/features/workout/templates/applied_template.dart';
import 'package:workout_record/features/workout/workout_controller.dart';

import '../../data/test_helpers.dart';

class _ThrowingCompleteRepository extends DriftWorkoutRepository {
  _ThrowingCompleteRepository(super.db, super.exerciseRepository);

  @override
  Future<Workout> completeWorkout(String workoutId, {DateTime? endedAt}) async {
    throw Exception('模擬完成訓練寫入失敗');
  }
}

class _ThrowingFetchRecentRepository extends DriftWorkoutRepository {
  _ThrowingFetchRecentRepository(super.db, super.exerciseRepository, {this.failuresLeft = 1 << 30});

  var fetchRecentCalls = 0;
  int? lastLimit;

  /// 前幾次呼叫拋錯(預設一直拋),之後照常查 DB(模擬恢復網路)。
  int failuresLeft;

  @override
  Future<List<Workout>> fetchRecent(int limit) async {
    fetchRecentCalls += 1;
    lastLimit = limit;
    if (failuresLeft > 0) {
      failuresLeft -= 1;
      throw Exception('模擬離線:fetchRecent 走網路失敗');
    }
    return super.fetchRecent(limit);
  }
}

/// 模擬真機:SharedPreferences.remove 走 platform channel,比一個 frame 慢。
/// [completedRemoves] 記下已真正寫完的 key。
class _SlowRemoveStore extends InMemorySharedPreferencesStore {
  _SlowRemoveStore(super.data) : super.withData();

  final completedRemoves = <String>[];

  @override
  Future<bool> remove(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final result = await super.remove(key);
    completedRemoves.add(key);
    return result;
  }
}

typedef _Harness = ({AppDatabase db, SharedPreferences prefs, ProviderContainer container});

Future<_Harness> _setUp({WorkoutRepository Function(AppDatabase db)? repo}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);
  final container = _container(db, prefs, repo: repo);
  addTearDown(db.close);
  return (db: db, prefs: prefs, container: container);
}

ProviderContainer _container(
  AppDatabase db,
  SharedPreferences prefs, {
  WorkoutRepository Function(AppDatabase db)? repo,
}) {
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (repo != null) workoutRepositoryProvider.overrideWithValue(repo(db)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<List<Exercise>> _systemExercises(AppDatabase db) => DriftExerciseRepository(db).fetchSystemExercises();

AppliedTemplate _template(List<Exercise> exercises, {int sets = 3}) => AppliedTemplate(
  templateId: 'template-1',
  templateName: '測試模板',
  exercises: [
    for (final e in exercises)
      AppliedTemplateExercise(
        exerciseId: e.id,
        exerciseName: e.name,
        sets: [for (var i = 0; i < sets; i++) const AppliedTemplateSet(weight: 0, reps: 10)],
      ),
  ],
);

/// 直接寫一場已完成訓練(單一動作)。
Future<void> _seedCompleted(AppDatabase db, String id, DateTime at, Exercise ex, List<(double, int, bool)> sets) =>
    DriftWorkoutRepository(db, DriftExerciseRepository(db)).create(
      Workout(
        id: id,
        userId: testUserId,
        startedAt: at,
        endedAt: at.add(const Duration(minutes: 30)),
        createdAt: at,
        updatedAt: at,
        exercises: [
          WorkoutExercise(
            id: '$id-we',
            workoutId: id,
            exerciseId: ex.id,
            exerciseName: ex.name,
            createdAt: at,
            updatedAt: at,
            sets: [
              for (var i = 0; i < sets.length; i++)
                WorkoutSet(
                  id: '$id-s$i',
                  workoutExerciseId: '$id-we',
                  setNumber: i + 1,
                  weight: sets[i].$1,
                  reps: sets[i].$2,
                  isWarmup: sets[i].$3,
                  createdAt: at,
                  updatedAt: at,
                ),
            ],
          ),
        ],
      ),
    );

Future<int> _countDbSets(AppDatabase db) async => (await db.select(db.workoutSets).get()).length;

WorkoutFlowState _flow(ProviderContainer c) => c.read(workoutControllerProvider).value!;

/// 等 controller 序列化鎖裡排在前面的工作(build 時的 GC)跑完:放棄在沒有
/// 草稿時是 no-op,但一樣要排隊。
Future<void> _drain(ProviderContainer c) => c.read(workoutControllerProvider.notifier).abandonWorkout();

void main() {
  group('計畫組', () {
    test('模板開始 → WorkoutSet 為 0、計畫組在 state 與附屬儲存;打勾一組 → 真實組 +1、計畫組 -1', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(2).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);

      await notifier.startFromTemplate(_template(exercises));

      expect(await _countDbSets(h.db), 0);
      final flow = _flow(h.container);
      final draftId = flow.draft!.id;
      final firstWe = flow.draft!.exercises.first.id;
      expect(flow.plannedSets[firstWe], hasLength(3));
      expect(PlannedSetsStore(h.prefs).read(draftId)[firstWe], hasLength(3));

      final plannedId = flow.plannedSets[firstWe]!.first.id;
      await notifier.confirmPlannedSet(
        workoutExerciseId: firstWe,
        plannedSetId: plannedId,
        weight: 60,
        reps: 8,
      );

      expect(await _countDbSets(h.db), 1);
      final after = _flow(h.container);
      final realSet = after.draft!.exercises.first.sets.single;
      expect((realSet.weight, realSet.reps, realSet.setNumber), (60.0, 8, 1));
      expect(after.plannedSets[firstWe], hasLength(2));
      expect(after.plannedSets[firstWe]!.any((p) => p.id == plannedId), isFalse);
      expect(PlannedSetsStore(h.prefs).read(draftId)[firstWe], hasLength(2));
    });

    test('左滑移除計畫組:不碰 DB,state 與附屬儲存都少一筆', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(1).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await notifier.startFromTemplate(_template(exercises, sets: 2));
      final flow = _flow(h.container);
      final we = flow.draft!.exercises.single.id;

      await notifier.removePlannedSet(workoutExerciseId: we, plannedSetId: flow.plannedSets[we]!.first.id);

      expect(_flow(h.container).plannedSets[we], hasLength(1));
      expect(PlannedSetsStore(h.prefs).read(flow.draft!.id)[we], hasLength(1));
      expect(await _countDbSets(h.db), 0);
    });

    test('重開(新 container 讀附屬儲存)→ 接手草稿時計畫組還在', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(2).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await notifier.startFromTemplate(_template(exercises));
      final flow = _flow(h.container);
      final we = flow.draft!.exercises.first.id;
      await notifier.confirmPlannedSet(
        workoutExerciseId: we,
        plannedSetId: flow.plannedSets[we]!.first.id,
        weight: 50,
        reps: 5,
      );

      // 模擬 App 重開:同一份 DB 與 prefs、全新的 container/controller。
      final reopened = _container(h.db, h.prefs);
      await reopened.read(workoutControllerProvider.future);
      final reNotifier = reopened.read(workoutControllerProvider.notifier);
      final recoverable = await reNotifier.checkForRecoverableDraft();
      expect(recoverable?.id, flow.draft!.id);
      await reNotifier.resumeDraft(recoverable!.id);

      final restored = _flow(reopened);
      expect(restored.plannedSets[we], hasLength(2));
      expect(restored.plannedSets[flow.draft!.exercises.last.id], hasLength(3));
      expect(restored.draft!.exercises.first.sets, hasLength(1));
    });

    test('完成成功 → 附屬儲存清空;沒打勾的計畫組不存成真實組', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(2).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await notifier.startFromTemplate(_template(exercises));
      final flow = _flow(h.container);
      final we = flow.draft!.exercises.first.id;
      await notifier.confirmPlannedSet(
        workoutExerciseId: we,
        plannedSetId: flow.plannedSets[we]!.first.id,
        weight: 50,
        reps: 5,
      );

      final outcome = await notifier.completeWorkout();

      expect(outcome, isA<WorkoutCompleted>());
      final completed = (outcome as WorkoutCompleted).workout;
      expect(completed.totalSets, 1);
      expect(await _countDbSets(h.db), 1);
      expect(h.prefs.getKeys().where((k) => k.startsWith(PlannedSetsStore.keyPrefix)), isEmpty);
    });

    test('完成失敗 → 計畫組仍在(state 與附屬儲存),草稿保留可重試', () async {
      final h = await _setUp(repo: (db) => _ThrowingCompleteRepository(db, DriftExerciseRepository(db)));
      final exercises = (await _systemExercises(h.db)).take(1).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await notifier.startFromTemplate(_template(exercises));
      final flow = _flow(h.container);
      final we = flow.draft!.exercises.single.id;
      await notifier.confirmPlannedSet(
        workoutExerciseId: we,
        plannedSetId: flow.plannedSets[we]!.first.id,
        weight: 50,
        reps: 5,
      );

      await expectLater(notifier.completeWorkout(), throwsA(isA<Exception>()));

      final after = _flow(h.container);
      expect(after.isCompleting, isFalse);
      expect(after.draft?.id, flow.draft!.id);
      expect(after.plannedSets[we], hasLength(2));
      expect(PlannedSetsStore(h.prefs).read(flow.draft!.id)[we], hasLength(2));
    });

    test('放棄訓練 → 附屬儲存清空', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(1).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await notifier.startFromTemplate(_template(exercises));
      final draftId = _flow(h.container).draft!.id;
      expect(h.prefs.containsKey(PlannedSetsStore.keyFor(draftId)), isTrue);

      await notifier.abandonWorkout();

      expect(h.prefs.containsKey(PlannedSetsStore.keyFor(draftId)), isFalse);
    });

    test('啟動對話框選放棄(discardRecoverableDraft)→ 附屬儲存清空', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(1).toList();
      await h.container.read(workoutControllerProvider.future);
      await h.container.read(workoutControllerProvider.notifier).startFromTemplate(_template(exercises));
      final draftId = _flow(h.container).draft!.id;

      // 重開後由對話框放棄。
      final reopened = _container(h.db, h.prefs);
      await reopened.read(workoutControllerProvider.future);
      final reNotifier = reopened.read(workoutControllerProvider.notifier);
      final recoverable = await reNotifier.checkForRecoverableDraft();
      expect(h.prefs.containsKey(PlannedSetsStore.keyFor(draftId)), isTrue, reason: '檢查時草稿還在,不該被 GC');
      await reNotifier.discardRecoverableDraft(recoverable!.id);

      expect(h.prefs.containsKey(PlannedSetsStore.keyFor(draftId)), isFalse);
    });

    test('removeExercise → 該動作的計畫組一併移除', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(2).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await notifier.startFromTemplate(_template(exercises));
      final flow = _flow(h.container);
      final we = flow.draft!.exercises.first.id;

      await notifier.removeExercise(we);

      expect(_flow(h.container).plannedSets.containsKey(we), isFalse);
      expect(PlannedSetsStore(h.prefs).read(flow.draft!.id).containsKey(we), isFalse);
    });
  });

  group('計畫組 GC', () {
    test('換成沒有草稿的使用者 → controller build 的 GC 清掉舊使用者的計畫組 key', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(1).toList();
      await h.container.read(workoutControllerProvider.future);
      await h.container.read(workoutControllerProvider.notifier).startFromTemplate(_template(exercises));
      final draftId = _flow(h.container).draft!.id;
      expect(h.prefs.containsKey(PlannedSetsStore.keyFor(draftId)), isTrue);

      // 換帳號:另一個沒有任何草稿的使用者登入(新 container 模擬重新建立)。
      await seedTestUser(h.db, id: 'other-user');
      await h.prefs.setString(kAppleUserIdKey, 'other-user');
      final other = _container(h.db, h.prefs);
      await other.read(workoutControllerProvider.future);
      await _drain(other);

      expect(h.prefs.containsKey(PlannedSetsStore.keyFor(draftId)), isFalse);
    });

    test('build 的 GC 保留目前使用者草稿的 key、清掉其他殘留 key', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(1).toList();
      await h.container.read(workoutControllerProvider.future);
      await h.container.read(workoutControllerProvider.notifier).startFromTemplate(_template(exercises));
      final draftId = _flow(h.container).draft!.id;
      await h.prefs.setString(PlannedSetsStore.keyFor('stale-workout'), '{}');

      final reopened = _container(h.db, h.prefs);
      await reopened.read(workoutControllerProvider.future);
      await _drain(reopened);

      expect(h.prefs.containsKey(PlannedSetsStore.keyFor(draftId)), isTrue);
      expect(h.prefs.containsKey(PlannedSetsStore.keyFor('stale-workout')), isFalse);
    });

    test('草稿檢查(checkForRecoverableDraft)也會 GC 殘留 key', () async {
      final h = await _setUp();
      await h.container.read(workoutControllerProvider.future);
      await _drain(h.container);
      await h.prefs.setString(PlannedSetsStore.keyFor('stale-workout'), '{}');

      await h.container.read(workoutControllerProvider.notifier).checkForRecoverableDraft();

      expect(h.prefs.containsKey(PlannedSetsStore.keyFor('stale-workout')), isFalse);
    });
  });

  group('完成規則(有組就算完成)', () {
    test('完成時沒有任何組的動作被丟棄,不計入動作數', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(2).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercises[0]);
      await notifier.addExercise(exercises[1]);
      final withSet = _flow(h.container).draft!.exercises.first.id;
      final empty = _flow(h.container).draft!.exercises.last.id;
      await notifier.addSet(workoutExerciseId: withSet, weight: 30, reps: 10);

      final outcome = await notifier.completeWorkout() as WorkoutCompleted;

      expect(outcome.workout.exercises.map((e) => e.id), [withSet]);
      expect(outcome.workout.totalExercises, 1);
      final rows = await (h.db.select(h.db.workoutExercises)..where((t) => t.id.equals(empty))).get();
      expect(rows, isEmpty);
    });

    test('草稿 0 組 → completeWorkout 拋 StateError,草稿不動', () async {
      final h = await _setUp();
      final exercises = await _systemExercises(h.db);
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercises.first);

      await expectLater(notifier.completeWorkout(), throwsA(isA<StateError>()));

      final flow = _flow(h.container);
      expect(flow.draft, isNotNull);
      expect(flow.draft!.exercises, hasLength(1));
      expect(flow.draft!.endedAt, isNull);
    });
  });

  group('完成/放棄:附屬儲存清完才收回 idle(flow-fix 1)', () {
    // 先 idle 再清除時,真機在 await 清除的空檔會畫一幀把進行中畫面拆掉,UI
    // 還沒拿到結果就失去 context。這裡在 state 變 idle 的當下檢查清除已寫完。
    Future<({ProviderContainer container, _SlowRemoveStore store, AppDatabase db})> slowSetUp() async {
      SharedPreferences.setMockInitialValues({});
      final store = _SlowRemoveStore({'flutter.$kAppleUserIdKey': testUserId});
      SharedPreferencesStorePlatform.instance = store;
      final prefs = await SharedPreferences.getInstance();
      final db = openTestDatabase();
      await seedTestUser(db);
      addTearDown(db.close);
      return (container: _container(db, prefs), store: store, db: db);
    }

    Future<List<bool>> clearedWhenIdle(ProviderContainer c, _SlowRemoveStore store, String draftId) async {
      final seen = <bool>[];
      c.listen(workoutControllerProvider, (prev, next) {
        if (prev?.value?.draft != null && next.value?.draft == null) {
          seen.add(store.completedRemoves.contains('flutter.${PlannedSetsStore.keyFor(draftId)}'));
        }
      });
      return seen;
    }

    test('完成', () async {
      final h = await slowSetUp();
      final exercises = (await _systemExercises(h.db)).take(1).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await notifier.startFromTemplate(_template(exercises));
      final flow = _flow(h.container);
      final we = flow.draft!.exercises.single.id;
      await notifier.confirmPlannedSet(
        workoutExerciseId: we,
        plannedSetId: flow.plannedSets[we]!.first.id,
        weight: 20,
        reps: 10,
      );
      final seen = await clearedWhenIdle(h.container, h.store, flow.draft!.id);

      await notifier.completeWorkout();

      expect(seen, [true]);
    });

    test('放棄', () async {
      final h = await slowSetUp();
      final exercises = (await _systemExercises(h.db)).take(1).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      await notifier.startFromTemplate(_template(exercises));
      final seen = await clearedWhenIdle(h.container, h.store, _flow(h.container).draft!.id);

      await notifier.abandonWorkout();

      expect(seen, [true]);
    });
  });

  group('歷史預填 best-effort', () {
    test('fetchRecent 拋錯 → exerciseHistory 回空白,模板開訓與記組照常成功', () async {
      late _ThrowingFetchRecentRepository repo;
      final h = await _setUp(
        repo: (db) => repo = _ThrowingFetchRecentRepository(db, DriftExerciseRepository(db)),
      );
      final exercises = (await _systemExercises(h.db)).take(1).toList();
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);

      // 畫面會在開訓同時讀歷史;這裡先讀,確認錯誤被吞掉成空白。
      final history = await h.container.read(exerciseHistoryProvider.future);
      expect(history.recentExerciseIds, isEmpty);
      expect(history.isUnavailable, isTrue);
      expect(await h.container.read(recentExercisesProvider.future), isEmpty);

      await notifier.startFromTemplate(_template(exercises));
      // 訓練畫面整場都在 watch 歷史;這裡用 listen 模擬,並記下開訓後的查詢數。
      h.container.listen(exerciseHistoryProvider, (_, _) {});
      await h.container.read(exerciseHistoryProvider.future);
      final callsAfterStart = repo.fetchRecentCalls;
      final flow = _flow(h.container);
      final we = flow.draft!.exercises.single.id;
      await notifier.confirmPlannedSet(
        workoutExerciseId: we,
        plannedSetId: flow.plannedSets[we]!.first.id,
        weight: 0,
        reps: 10,
      );
      await notifier.addSet(workoutExerciseId: we, weight: 20, reps: 8);

      expect(_flow(h.container).draft!.exercises.single.sets, hasLength(2));
      // 記組(打勾、新增組)不會觸發歷史查詢。原本斷言「整場只查 1 次」的前提
      // 是失敗也快取;flow-fix 第 2 條改成失敗不快取、新建草稿重查後,改成
      // 斷言記組前後查詢數不變(成功結果只查一次見下一則測試)。
      await h.container.read(exerciseHistoryProvider.future);
      expect(repo.fetchRecentCalls, callsAfterStart);
      expect(repo.lastLimit, 20, reason: '固定 fetchRecent(20),不准 fetchAll');
    });

    test('成功結果只查一次:沒人在聽、重複讀也不重查', () async {
      late _ThrowingFetchRecentRepository repo;
      final h = await _setUp(
        repo: (db) => repo = _ThrowingFetchRecentRepository(db, DriftExerciseRepository(db), failuresLeft: 0),
      );
      await h.container.read(workoutControllerProvider.future);

      final first = await h.container.read(exerciseHistoryProvider.future);
      expect(first.isUnavailable, isFalse);
      // 中間讓 autoDispose 的清理排程有機會跑(沒人在聽):成功結果仍留著。
      await Future<void>.delayed(Duration.zero);
      await h.container.read(recentExercisesProvider.future);
      await Future<void>.delayed(Duration.zero);
      await h.container.read(exerciseHistoryProvider.future);
      await h.container.read(recentExercisesProvider.future);
      expect(repo.fetchRecentCalls, 1);
    });

    test('失敗結果不快取:第一次拋錯 → 空白;第二次查成功 → 有資料', () async {
      late _ThrowingFetchRecentRepository repo;
      final h = await _setUp(
        repo: (db) => repo = _ThrowingFetchRecentRepository(db, DriftExerciseRepository(db), failuresLeft: 1),
      );
      final exercise = (await _systemExercises(h.db)).first;
      await h.container.read(workoutControllerProvider.future);
      await _seedCompleted(h.db, 'done-1', DateTime(2026, 11, 1, 9), exercise, [(50, 5, false)]);

      // 畫面在聽 → 查詢失敗 → 畫面離開(取消監聽,清理排程跑完)。
      final sub = h.container.listen(exerciseHistoryProvider, (_, _) {});
      final failed = await h.container.read(exerciseHistoryProvider.future);
      expect(failed.isUnavailable, isTrue);
      expect(failed.lastSetFor(exercise.id), isNull);
      sub.close();
      await Future<void>.delayed(Duration.zero);

      final retried = await h.container.read(exerciseHistoryProvider.future);
      expect(repo.fetchRecentCalls, 2);
      expect(retried.isUnavailable, isFalse);
      expect(retried.lastSetFor(exercise.id)?.weight, 50);
      expect((await h.container.read(recentExercisesProvider.future)).map((e) => e.id), [exercise.id]);
    });

    test('建新草稿時重查歷史:開始自由訓練與從模板開始各觸發一次', () async {
      late _ThrowingFetchRecentRepository repo;
      final h = await _setUp(
        repo: (db) => repo = _ThrowingFetchRecentRepository(db, DriftExerciseRepository(db), failuresLeft: 0),
      );
      final exercise = (await _systemExercises(h.db)).first;
      await h.container.read(workoutControllerProvider.future);
      final notifier = h.container.read(workoutControllerProvider.notifier);
      h.container.listen(exerciseHistoryProvider, (_, _) {});
      expect((await h.container.read(exerciseHistoryProvider.future)).lastSetFor(exercise.id), isNull);
      expect(repo.fetchRecentCalls, 1);

      // 別台裝置完成了一場(快取不知道),這台開始新訓練 → 要看得到。
      await _seedCompleted(h.db, 'elsewhere', DateTime(2026, 11, 2, 9), exercise, [(60, 5, false)]);
      await notifier.startFreeWorkout();
      expect((await h.container.read(exerciseHistoryProvider.future)).lastSetFor(exercise.id)?.weight, 60);
      expect(repo.fetchRecentCalls, 2);

      await notifier.abandonWorkout();
      await _seedCompleted(h.db, 'elsewhere-2', DateTime(2026, 11, 3, 9), exercise, [(65, 5, false)]);
      await notifier.startFromTemplate(_template([exercise]));
      expect((await h.container.read(exerciseHistoryProvider.future)).lastSetFor(exercise.id)?.weight, 65);
      expect(repo.fetchRecentCalls, 3);

      // 已有草稿時再按開始(接手既有草稿、不建新的)不重查。
      await notifier.startFreeWorkout();
      await h.container.read(exerciseHistoryProvider.future);
      expect(repo.fetchRecentCalls, 3);
    });

    test('有歷史時:最近用過依時間排序、最後一組取正式組', () async {
      final h = await _setUp();
      final exercises = (await _systemExercises(h.db)).take(2).toList();
      await h.container.read(workoutControllerProvider.future);
      // 直接寫兩場已完成訓練(startedAt 錯開,DB 時間精度到秒,同秒排序不定)。
      final repo = DriftWorkoutRepository(h.db, DriftExerciseRepository(h.db));
      Future<void> seed(String id, DateTime at, Exercise ex, List<(double, int, bool)> sets) => repo.create(
        Workout(
          id: id,
          userId: testUserId,
          startedAt: at,
          endedAt: at.add(const Duration(minutes: 30)),
          createdAt: at,
          updatedAt: at,
          exercises: [
            WorkoutExercise(
              id: '$id-we',
              workoutId: id,
              exerciseId: ex.id,
              exerciseName: ex.name,
              createdAt: at,
              updatedAt: at,
              sets: [
                for (var i = 0; i < sets.length; i++)
                  WorkoutSet(
                    id: '$id-s$i',
                    workoutExerciseId: '$id-we',
                    setNumber: i + 1,
                    weight: sets[i].$1,
                    reps: sets[i].$2,
                    isWarmup: sets[i].$3,
                    createdAt: at,
                    updatedAt: at,
                  ),
              ],
            ),
          ],
        ),
      );
      await seed('older', DateTime(2026, 11, 1, 9), exercises[0], [(40, 10, false), (45, 8, false)]);
      await seed('newer', DateTime(2026, 11, 3, 9), exercises[1], [(70, 5, false), (20, 12, true)]);

      final history = await h.container.read(exerciseHistoryProvider.future);
      expect(history.recentExerciseIds, [exercises[1].id, exercises[0].id]);
      expect(history.lastSetFor(exercises[0].id)?.weight, 45);
      // 有正式組時只留正式組:暖身組(後記)不會被當成「最後一組」。
      expect(history.lastSetFor(exercises[1].id)?.weight, 70);
      final recent = await h.container.read(recentExercisesProvider.future);
      expect(recent.map((e) => e.id), [exercises[1].id, exercises[0].id]);
    });
  });
}
