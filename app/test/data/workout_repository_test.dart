// WorkoutRepository 測試:含 exercises/sets 巢狀的 create + fetchById、
// fetchByDateRange 邊界、completeWorkout 統計計算、delete FK cascade。

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/db/app_database.dart' hide Workout, WorkoutExercise, WorkoutSet;
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';

import 'test_helpers.dart';

/// `buildWorkout` 的 `endedAt` 參數用來區分「呼叫端沒傳(套用預設值)」與
/// 「明確傳入 null(草稿)」——裸 `DateTime?` 參數做不到這個區分,見下方
/// `buildWorkout` 的說明。
const _unset = Object();

void main() {
  late AppDatabase db;
  late ExerciseRepository exerciseRepository;
  late WorkoutRepository repository;
  late String exerciseId;

  setUp(() async {
    db = openTestDatabase();
    await seedTestUser(db);
    exerciseRepository = ExerciseRepository(db);
    repository = WorkoutRepository(db, exerciseRepository);

    final systemExercises = await exerciseRepository.fetchSystemExercises();
    exerciseId = systemExercises.first.id;
  });

  tearDown(() async => db.close());

  // endedAt 預設為 startedAt 一小時後(代表「已完成」)——這份測試檔大多數
  // 案例(fetchByDateRange/delete)驗證的是完成訓練後的查詢行為,不是波 3
  // 新增的草稿語意。`completeWorkout` group 不在此列:completeWorkout 只在
  // 進行中草稿(endedAt IS NULL)上有效(DB 級冪等守衛,見
  // workout_repository.dart `completeWorkout` 文件),該 group 底下每個
  // fixture 都明確傳 `endedAt: null`,不依賴這裡的預設值。草稿(endedAt:
  // null)不計入 fetchByDateRange/fetchRecent/countWorkouts/
  // calculateTotalVolume 的行為另外在 `草稿排除(endedAt IS NULL)` group
  // 獨立測試,那裡才會明確傳 `endedAt: null`。
  Workout buildWorkout({
    required String id,
    required DateTime startedAt,
    List<WorkoutExercise> exercises = const [],
    Object? endedAt = _unset,
  }) {
    final now = DateTime.now();
    return Workout(
      id: id,
      userId: testUserId,
      startedAt: startedAt,
      endedAt: identical(endedAt, _unset)
          ? startedAt.add(const Duration(hours: 1))
          : endedAt as DateTime?,
      exercises: exercises,
      createdAt: now,
      updatedAt: now,
    );
  }

  // 注意:completeWorkout() 是從 sets 的 weight*reps 現算 totalVolume(見
  // 下方 completeWorkout 測試群組),不信任 WorkoutExercise.totalVolume 欄位
  // ——這裡仍先算好 totalVolume/totalSets 才組出 WorkoutExercise,單純是
  // 比照「正常使用流程」的資料形狀,不是 completeWorkout 實際依賴它。
  WorkoutExercise buildExercise({
    required String id,
    required String workoutId,
    List<WorkoutSet> sets = const [],
  }) {
    final now = DateTime.now();
    return WorkoutExercise(
      id: id,
      workoutId: workoutId,
      exerciseId: exerciseId,
      sets: sets,
      totalVolume: sets.fold<double>(0, (sum, s) => sum + s.volume),
      totalSets: sets.length,
      createdAt: now,
      updatedAt: now,
    );
  }

  WorkoutSet buildSet({
    required String id,
    required String workoutExerciseId,
    required int setNumber,
    required double weight,
    required int reps,
  }) {
    final now = DateTime.now();
    return WorkoutSet(
      id: id,
      workoutExerciseId: workoutExerciseId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('create + fetchById', () {
    test('完整讀回 workout,含巢狀 exercises 與 sets', () async {
      final workout = buildWorkout(
        id: 'workout-1',
        startedAt: DateTime(2026, 1, 10, 8),
        exercises: [
          buildExercise(
            id: 'we-1',
            workoutId: 'workout-1',
            sets: [
              buildSet(id: 'set-1', workoutExerciseId: 'we-1', setNumber: 1, weight: 60, reps: 10),
              buildSet(id: 'set-2', workoutExerciseId: 'we-1', setNumber: 2, weight: 65, reps: 8),
            ],
          ),
        ],
      );

      await repository.create(workout);

      final fetched = await repository.fetchById('workout-1');

      expect(fetched, isNotNull);
      expect(fetched!.userId, testUserId);
      expect(fetched.exercises, hasLength(1));
      expect(fetched.exercises.single.id, 'we-1');
      expect(fetched.exercises.single.sets, hasLength(2));
      expect(fetched.exercises.single.sets[0].weight, 60);
      expect(fetched.exercises.single.sets[0].reps, 10);
      expect(fetched.exercises.single.sets[0].volume, 600);
      expect(fetched.exercises.single.sets[1].weight, 65);
      expect(fetched.exercises.single.sets[1].reps, 8);
    });

    test('不存在的 id 回傳 null', () async {
      final fetched = await repository.fetchById('does-not-exist');
      expect(fetched, isNull);
    });
  });

  group('fetchByDateRange', () {
    test('邊界值(from/to 當下的時間點)皆含在範圍內,採 SQL BETWEEN 語意', () async {
      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 1, 31);

      await repository.create(buildWorkout(id: 'w-before', startedAt: DateTime(2025, 12, 31)));
      await repository.create(buildWorkout(id: 'w-from-edge', startedAt: from));
      await repository.create(buildWorkout(id: 'w-mid', startedAt: DateTime(2026, 1, 15)));
      await repository.create(buildWorkout(id: 'w-to-edge', startedAt: to));
      await repository.create(buildWorkout(id: 'w-after', startedAt: DateTime(2026, 2, 1)));

      final result = await repository.fetchByDateRange(from, to);
      final ids = result.map((w) => w.id).toSet();

      // WorkoutRepository.fetchByDateRange 底層用 isBetweenValues,對應
      // SQL 的 BETWEEN,含頭含尾 —— 這裡照實作行為驗證。
      expect(ids, {'w-from-edge', 'w-mid', 'w-to-edge'});
      expect(ids.contains('w-before'), isFalse);
      expect(ids.contains('w-after'), isFalse);
    });
  });

  group('completeWorkout', () {
    test('依現有 exercises/sets 重新計算統計欄位', () async {
      await repository.create(buildWorkout(
        id: 'workout-2',
        startedAt: DateTime(2026, 1, 10, 8, 0),
        // completeWorkout 只在進行中草稿(endedAt IS NULL)上有效(DB 級冪等
        // 守衛,見 workout_repository.dart completeWorkout 文件)——明確傳
        // null,不依賴 buildWorkout 「沒傳就當已完成」的預設值。
        endedAt: null,
        exercises: [
          buildExercise(
            id: 'we-2a',
            workoutId: 'workout-2',
            sets: [
              buildSet(id: 'set-2a-1', workoutExerciseId: 'we-2a', setNumber: 1, weight: 60, reps: 10),
              buildSet(id: 'set-2a-2', workoutExerciseId: 'we-2a', setNumber: 2, weight: 65, reps: 8),
            ],
          ),
          buildExercise(
            id: 'we-2b',
            workoutId: 'workout-2',
            sets: [
              buildSet(id: 'set-2b-1', workoutExerciseId: 'we-2b', setNumber: 1, weight: 20, reps: 12),
            ],
          ),
        ],
      ));

      final endedAt = DateTime(2026, 1, 10, 9, 30);
      final completed = await repository.completeWorkout('workout-2', endedAt: endedAt);

      // totalVolume = 60*10 + 65*8 + 20*12 = 600 + 520 + 240 = 1360
      expect(completed.totalVolume, 1360);
      expect(completed.totalSets, 3);
      expect(completed.totalExercises, 2);
      expect(completed.duration, 90);
      expect(completed.endedAt, endedAt);
    });

    test('workout 不存在時拋出 StateError', () async {
      expect(
        () => repository.completeWorkout('does-not-exist'),
        throwsA(isA<StateError>()),
      );
    });

    test('WorkoutExercise.totalVolume 欄位未預先維護時,totalVolume 仍從 sets 現算', () async {
      final now = DateTime.now();
      await repository.create(Workout(
        id: 'workout-2-bug',
        userId: testUserId,
        startedAt: DateTime(2026, 1, 10, 8, 0),
        createdAt: now,
        updatedAt: now,
        exercises: [
          WorkoutExercise(
            id: 'we-2-bug',
            workoutId: 'workout-2-bug',
            exerciseId: exerciseId,
            // 刻意不設 totalVolume(維持預設值 0),模擬呼叫端沒有另外維護
            // 這個欄位的情境。
            sets: [
              buildSet(id: 'set-2-bug-1', workoutExerciseId: 'we-2-bug', setNumber: 1, weight: 60, reps: 10),
            ],
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ));

      final completed = await repository.completeWorkout('workout-2-bug');

      expect(completed.totalVolume, 600);
      expect(completed.totalSets, 1);
    });

    // 雙向變異(暖身排除):把下方 `.where((set) => !set.isWarmup)` 兩處
    // 改回無條件加總,這則測試(以及 completeWorkout 統計計算那則)會紅
    // ——參照值(1360/3、200/1)手算自 buildSet 傳入的重量/次數,不是照抄
    // 被測程式碼算出來的。
    test('暖身組(isWarmup)不計入 totalVolume/totalSets,對齊 iOS WorkoutViewModel', () async {
      await repository.create(buildWorkout(
        id: 'workout-warmup',
        startedAt: DateTime(2026, 1, 10, 8, 0),
        // 同上:completeWorkout 只在進行中草稿上有效,明確傳 null。
        endedAt: null,
        exercises: [
          WorkoutExercise(
            id: 'we-warmup',
            workoutId: 'workout-warmup',
            exerciseId: exerciseId,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            sets: [
              WorkoutSet(
                id: 'set-warmup-1',
                workoutExerciseId: 'we-warmup',
                setNumber: 1,
                weight: 20,
                reps: 10,
                isWarmup: true,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
              buildSet(
                id: 'set-warmup-2',
                workoutExerciseId: 'we-warmup',
                setNumber: 2,
                weight: 100,
                reps: 2,
              ),
            ],
          ),
        ],
      ));

      final completed = await repository.completeWorkout('workout-warmup');

      // 暖身組(20 x 10)排除;只計正式組(100 x 2 = 200)。
      expect(completed.totalVolume, 200);
      expect(completed.totalSets, 1);
    });

    // 雙向變異(DB 級冪等):把 UPDATE 的 where 子句從
    // `t.id.equals(workoutId) & t.endedAt.isNull()` 改回單純
    // `t.id.equals(workoutId)`,這則測試會紅——第二次呼叫會用
    // `secondEndedAt`/現算的新統計覆寫掉第一次完成時寫入的內容。
    test('completeWorkout 冪等:對已完成的訓練再次呼叫 → 不覆寫既有 endedAt/統計', () async {
      await repository.create(buildWorkout(
        id: 'workout-idempotent',
        startedAt: DateTime(2026, 1, 10, 8, 0),
        endedAt: null,
        exercises: [
          buildExercise(
            id: 'we-idempotent',
            workoutId: 'workout-idempotent',
            sets: [
              buildSet(
                  id: 'set-idempotent-1', workoutExerciseId: 'we-idempotent', setNumber: 1, weight: 50, reps: 10),
            ],
          ),
        ],
      ));

      final firstEndedAt = DateTime(2026, 1, 10, 9, 0);
      final first = await repository.completeWorkout('workout-idempotent', endedAt: firstEndedAt);
      expect(first.totalVolume, 500);
      expect(first.endedAt, firstEndedAt);

      final secondEndedAt = DateTime(2026, 1, 10, 12, 0);
      final second = await repository.completeWorkout('workout-idempotent', endedAt: secondEndedAt);

      expect(second.endedAt, firstEndedAt); // 沒被第二次呼叫的 secondEndedAt 覆蓋
      expect(second.duration, first.duration);
      expect(second.totalVolume, 500);
    });
  });

  group('delete', () {
    test('刪除 workout 後,exercises 與 sets 透過 FK cascade 一併刪除', () async {
      await repository.create(buildWorkout(
        id: 'workout-3',
        startedAt: DateTime(2026, 1, 10),
        exercises: [
          buildExercise(
            id: 'we-3',
            workoutId: 'workout-3',
            sets: [
              buildSet(id: 'set-3-1', workoutExerciseId: 'we-3', setNumber: 1, weight: 40, reps: 10),
            ],
          ),
        ],
      ));

      await repository.delete('workout-3');

      final fetched = await repository.fetchById('workout-3');
      expect(fetched, isNull);

      final remainingExercises =
          await (db.select(db.workoutExercises)..where((t) => t.workoutId.equals('workout-3')))
              .get();
      expect(remainingExercises, isEmpty);

      final remainingSets =
          await (db.select(db.workoutSets)..where((t) => t.workoutExerciseId.equals('we-3')))
              .get();
      expect(remainingSets, isEmpty);
    });

    // 雙向變異(草稿排除守衛):把 deleteOlderThan 的 where 子句從
    // `t.startedAt.isSmallerThanValue(date) & _isCompleted(t)` 改回單純
    // `t.startedAt.isSmallerThanValue(date)`,這則測試會紅——舊的進行中草稿
    // 會被一併清掉。
    test('deleteOlderThan:只清已完成的舊訓練,進行中草稿不管多舊都不清', () async {
      await repository.create(buildWorkout(id: 'old-completed', startedAt: DateTime(2020, 1, 1)));
      await repository.create(buildWorkout(
        id: 'old-draft',
        startedAt: DateTime(2020, 1, 1),
        endedAt: null,
      ));

      await repository.deleteOlderThan(DateTime(2025, 1, 1));

      expect(await repository.fetchById('old-completed'), isNull);
      expect(await repository.fetchById('old-draft'), isNotNull);
    });
  });

  group('草稿寫穿的增量方法', () {
    test('fetchDraft:找到 endedAt IS NULL 的草稿,已完成訓練不算', () async {
      await repository.create(buildWorkout(id: 'completed-1', startedAt: DateTime(2026, 1, 1)));
      await repository.create(buildWorkout(
        id: 'draft-1',
        startedAt: DateTime(2026, 1, 2),
        endedAt: null,
      ));

      final draft = await repository.fetchDraft(testUserId);

      expect(draft, isNotNull);
      expect(draft!.id, 'draft-1');
      expect(draft.endedAt, isNull);
    });

    test('fetchDraft:沒有草稿時回傳 null', () async {
      await repository.create(buildWorkout(id: 'completed-only', startedAt: DateTime(2026, 1, 1)));

      expect(await repository.fetchDraft(testUserId), isNull);
    });

    test('addExerciseToWorkout + addSet:新增動作與組數即時落地,獨立 SELECT 驗證', () async {
      await repository.create(buildWorkout(id: 'draft-2', startedAt: DateTime(2026, 1, 3), endedAt: null));
      final now = DateTime.now();

      await repository.addExerciseToWorkout(WorkoutExercise(
        id: 'we-draft-2',
        workoutId: 'draft-2',
        exerciseId: exerciseId,
        orderIndex: 0,
        createdAt: now,
        updatedAt: now,
      ));
      await repository.addSet(buildSet(
        id: 'set-draft-2-1',
        workoutExerciseId: 'we-draft-2',
        setNumber: 1,
        weight: 50,
        reps: 8,
      ));

      final exerciseRow =
          await (db.select(db.workoutExercises)..where((t) => t.id.equals('we-draft-2')))
              .getSingle();
      expect(exerciseRow.workoutId, 'draft-2');
      final setRow =
          await (db.select(db.workoutSets)..where((t) => t.id.equals('set-draft-2-1'))).getSingle();
      expect(setRow.weight, 50);
      expect(setRow.reps, 8);
      expect(setRow.volume, 400);
    });

    test('removeExercise:連同其下的 sets 一併刪除(FK cascade)', () async {
      await repository.create(buildWorkout(id: 'draft-3', startedAt: DateTime(2026, 1, 4), endedAt: null));
      final now = DateTime.now();
      await repository.addExerciseToWorkout(WorkoutExercise(
        id: 'we-draft-3',
        workoutId: 'draft-3',
        exerciseId: exerciseId,
        createdAt: now,
        updatedAt: now,
      ));
      await repository.addSet(buildSet(
          id: 'set-draft-3-1', workoutExerciseId: 'we-draft-3', setNumber: 1, weight: 10, reps: 5));

      await repository.removeExercise('we-draft-3', workoutId: 'draft-3');

      final remainingExercise =
          await (db.select(db.workoutExercises)..where((t) => t.id.equals('we-draft-3')))
              .getSingleOrNull();
      expect(remainingExercise, isNull);
      final remainingSet =
          await (db.select(db.workoutSets)..where((t) => t.id.equals('set-draft-3-1')))
              .getSingleOrNull();
      expect(remainingSet, isNull);
    });

    test('removeExercise:動作不存在時拋出 StateError', () {
      expect(
        () => repository.removeExercise('does-not-exist', workoutId: 'nowhere'),
        throwsA(isA<StateError>()),
      );
    });

    // 雙向變異(結構守衛):把 DELETE 的 where 子句從
    // `t.id.equals(workoutExerciseId) & t.workoutId.equals(workoutId)` 改回
    // 單純 `t.id.equals(workoutExerciseId)`,這則測試會紅——動作會被誤刪
    // (即使呼叫端傳的 workoutId 跟該動作實際所屬的訓練對不上)。
    test('removeExercise:workoutExerciseId 存在但屬於別筆訓練 → 結構守衛擋下,不刪、拋出 StateError',
        () async {
      await repository.create(buildWorkout(id: 'draft-cross-a', startedAt: DateTime(2026, 1, 11), endedAt: null));
      await repository.create(buildWorkout(id: 'draft-cross-b', startedAt: DateTime(2026, 1, 11), endedAt: null));
      final now = DateTime.now();
      await repository.addExerciseToWorkout(WorkoutExercise(
        id: 'we-cross-a',
        workoutId: 'draft-cross-a',
        exerciseId: exerciseId,
        createdAt: now,
        updatedAt: now,
      ));

      // 傳對的 exercise id,但 workoutId 傳成另一筆(不屬於它的)訓練。
      expect(
        () => repository.removeExercise('we-cross-a', workoutId: 'draft-cross-b'),
        throwsA(isA<StateError>()),
      );

      final stillThere = await (db.select(db.workoutExercises)..where((t) => t.id.equals('we-cross-a')))
          .getSingleOrNull();
      expect(stillThere, isNotNull);
    });

    test('removeExercise:移除中間動作後,剩餘動作的 orderIndex 重新編號成連續的 0..N-1', () async {
      await repository.create(buildWorkout(id: 'draft-orderidx', startedAt: DateTime(2026, 1, 9), endedAt: null));
      final now = DateTime.now();
      for (final entry in [('we-oi-1', 0), ('we-oi-2', 1), ('we-oi-3', 2)]) {
        await repository.addExerciseToWorkout(WorkoutExercise(
          id: entry.$1,
          workoutId: 'draft-orderidx',
          exerciseId: exerciseId,
          orderIndex: entry.$2,
          createdAt: now,
          updatedAt: now,
        ));
      }

      // 移除中間那個(orderIndex 1)——第三個理當被重編號成 1。
      await repository.removeExercise('we-oi-2', workoutId: 'draft-orderidx');

      final remaining = await (db.select(db.workoutExercises)
            ..where((t) => t.workoutId.equals('draft-orderidx'))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      expect(remaining.map((e) => e.id).toList(), ['we-oi-1', 'we-oi-3']);
      expect(remaining.map((e) => e.orderIndex).toList(), [0, 1]);

      // 重編號後再新增一個動作,controller 端用 `draft.exercises.length` 算
      // 下一個 orderIndex(2)——驗證不會撞號(既有的兩個是 0/1)。
      await repository.addExerciseToWorkout(WorkoutExercise(
        id: 'we-oi-4',
        workoutId: 'draft-orderidx',
        exerciseId: exerciseId,
        orderIndex: remaining.length,
        createdAt: now,
        updatedAt: now,
      ));
      final afterAdd = await (db.select(db.workoutExercises)
            ..where((t) => t.workoutId.equals('draft-orderidx'))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      expect(afterAdd.map((e) => e.orderIndex).toList(), [0, 1, 2]);
    });

    test('setExerciseCompleted:更新 isCompleted 欄位', () async {
      await repository.create(buildWorkout(id: 'draft-4', startedAt: DateTime(2026, 1, 5), endedAt: null));
      final now = DateTime.now();
      await repository.addExerciseToWorkout(WorkoutExercise(
        id: 'we-draft-4',
        workoutId: 'draft-4',
        exerciseId: exerciseId,
        createdAt: now,
        updatedAt: now,
      ));

      await repository.setExerciseCompleted('we-draft-4', isCompleted: true);

      final row = await (db.select(db.workoutExercises)..where((t) => t.id.equals('we-draft-4')))
          .getSingle();
      expect(row.isCompleted, isTrue);
    });

    test('setExerciseCompleted:動作不存在時拋出 StateError', () {
      expect(
        () => repository.setExerciseCompleted('does-not-exist', isCompleted: true),
        throwsA(isA<StateError>()),
      );
    });

    test('updateSet:更新重量/次數會連帶重算 volume', () async {
      await repository.create(buildWorkout(id: 'draft-5', startedAt: DateTime(2026, 1, 6), endedAt: null));
      final now = DateTime.now();
      await repository.addExerciseToWorkout(WorkoutExercise(
        id: 'we-draft-5',
        workoutId: 'draft-5',
        exerciseId: exerciseId,
        createdAt: now,
        updatedAt: now,
      ));
      final original = buildSet(
          id: 'set-draft-5-1', workoutExerciseId: 'we-draft-5', setNumber: 1, weight: 40, reps: 10);
      await repository.addSet(original);

      await repository.updateSet(original.copyWith(weight: 60, reps: 5, rpe: 8));

      final row =
          await (db.select(db.workoutSets)..where((t) => t.id.equals('set-draft-5-1'))).getSingle();
      expect(row.weight, 60);
      expect(row.reps, 5);
      expect(row.volume, 300);
      expect(row.rpe, 8);
    });

    test('updateSet:組數不存在時拋出 StateError', () {
      final phantom = buildSet(id: 'phantom', workoutExerciseId: 'nowhere', setNumber: 1, weight: 1, reps: 1);
      expect(() => repository.updateSet(phantom), throwsA(isA<StateError>()));
    });

    test('deleteSet:刪除中間一組後,剩餘組數重新編號成連續 1..N', () async {
      await repository.create(buildWorkout(id: 'draft-6', startedAt: DateTime(2026, 1, 7), endedAt: null));
      final now = DateTime.now();
      await repository.addExerciseToWorkout(WorkoutExercise(
        id: 'we-draft-6',
        workoutId: 'draft-6',
        exerciseId: exerciseId,
        createdAt: now,
        updatedAt: now,
      ));
      await repository.addSet(
          buildSet(id: 'set-6-1', workoutExerciseId: 'we-draft-6', setNumber: 1, weight: 10, reps: 10));
      await repository.addSet(
          buildSet(id: 'set-6-2', workoutExerciseId: 'we-draft-6', setNumber: 2, weight: 20, reps: 8));
      await repository.addSet(
          buildSet(id: 'set-6-3', workoutExerciseId: 'we-draft-6', setNumber: 3, weight: 30, reps: 6));

      // 刪除中間那組(setNumber 2)——第三組理當被重編號成 2。
      await repository.deleteSet('set-6-2', workoutExerciseId: 'we-draft-6');

      final remaining = await (db.select(db.workoutSets)
            ..where((t) => t.workoutExerciseId.equals('we-draft-6'))
            ..orderBy([(t) => OrderingTerm(expression: t.setNumber)]))
          .get();
      expect(remaining.map((s) => s.id).toList(), ['set-6-1', 'set-6-3']);
      expect(remaining.map((s) => s.setNumber).toList(), [1, 2]);
    });

    test('deleteSet:組數不存在時拋出 StateError,不影響其他組', () {
      expect(
        () => repository.deleteSet('does-not-exist', workoutExerciseId: 'nowhere'),
        throwsA(isA<StateError>()),
      );
    });

    test('discardDraft:進行中草稿 → 刪除,exercises/sets 一併清除(FK cascade)', () async {
      await repository.create(buildWorkout(id: 'draft-7', startedAt: DateTime(2026, 1, 8), endedAt: null));
      final now = DateTime.now();
      await repository.addExerciseToWorkout(WorkoutExercise(
        id: 'we-draft-7',
        workoutId: 'draft-7',
        exerciseId: exerciseId,
        createdAt: now,
        updatedAt: now,
      ));

      await repository.discardDraft('draft-7');

      expect(await repository.fetchById('draft-7'), isNull);
      final remainingExercise =
          await (db.select(db.workoutExercises)..where((t) => t.id.equals('we-draft-7')))
              .getSingleOrNull();
      expect(remainingExercise, isNull);
    });

    // 雙向變異(M1 結構守衛):把 discardDraft 的 where 子句從
    // `t.id.equals(workoutId) & t.endedAt.isNull()` 改回單純
    // `t.id.equals(workoutId)`(即等同 [delete]),這則測試會紅——已完成的
    // 訓練會被誤刪。
    test('discardDraft:對已完成的訓練呼叫 → 結構守衛擋下,不刪任何東西(不等同 delete)', () async {
      final endedAt = DateTime(2026, 1, 8, 9, 30);
      await repository.create(buildWorkout(id: 'completed-not-draft', startedAt: DateTime(2026, 1, 8), endedAt: endedAt));

      await repository.discardDraft('completed-not-draft');

      final stillThere = await repository.fetchById('completed-not-draft');
      expect(stillThere, isNotNull);
      expect(stillThere!.endedAt, endedAt);
    });

    test('discardDraft:id 不存在時靜默冪等,不拋錯', () async {
      await repository.discardDraft('does-not-exist');
    });
  });

  group('草稿排除(endedAt IS NULL)', () {
    // 雙向變異:把 `_isCompleted`(workout_repository.dart)從
    // fetchAll/fetchByDateRange/fetchRecent/countWorkouts/calculateTotalVolume
    // 的 where 子句拿掉,下面五則測試全部會紅(草稿會被計入);加回來即綠。
    test('fetchAll 不含草稿', () async {
      await repository.create(buildWorkout(id: 'completed-all', startedAt: DateTime(2026, 1, 1)));
      await repository.create(
        buildWorkout(id: 'draft-all', startedAt: DateTime(2026, 1, 2), endedAt: null),
      );

      final result = await repository.fetchAll();

      expect(result.map((w) => w.id).toSet(), {'completed-all'});
    });

    test('fetchByDateRange 不含草稿', () async {
      final from = DateTime(2026, 1, 1);
      final to = DateTime(2026, 1, 31);
      await repository.create(buildWorkout(id: 'completed-in-range', startedAt: DateTime(2026, 1, 10)));
      await repository.create(
        buildWorkout(id: 'draft-in-range', startedAt: DateTime(2026, 1, 15), endedAt: null),
      );

      final result = await repository.fetchByDateRange(from, to);

      expect(result.map((w) => w.id).toSet(), {'completed-in-range'});
    });

    test('fetchRecent 不含草稿', () async {
      await repository.create(buildWorkout(id: 'completed-recent', startedAt: DateTime(2026, 1, 1)));
      await repository.create(
        buildWorkout(id: 'draft-recent', startedAt: DateTime(2026, 1, 2), endedAt: null),
      );

      final result = await repository.fetchRecent(10);

      expect(result.map((w) => w.id).toSet(), {'completed-recent'});
    });

    test('countWorkouts 不含草稿', () async {
      await repository.create(buildWorkout(id: 'completed-count', startedAt: DateTime(2026, 1, 1)));
      await repository.create(
        buildWorkout(id: 'draft-count', startedAt: DateTime(2026, 1, 2), endedAt: null),
      );

      expect(await repository.countWorkouts(), 1);
    });

    test('calculateTotalVolume 不含草稿', () async {
      await repository.create(buildWorkout(
        id: 'completed-volume',
        startedAt: DateTime(2026, 1, 1),
      ).copyWith(totalVolume: 500));
      await repository.create(buildWorkout(
        id: 'draft-volume',
        startedAt: DateTime(2026, 1, 2),
        endedAt: null,
      ).copyWith(totalVolume: 9999));

      expect(await repository.calculateTotalVolume(), 500);
    });
  });
}
