// WorkoutRepository 測試:含 exercises/sets 巢狀的 create + fetchById、
// fetchByDateRange 邊界、completeWorkout 統計計算、delete FK cascade。

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/db/app_database.dart' hide Workout, WorkoutExercise, WorkoutSet;
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';

import 'test_helpers.dart';

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

  Workout buildWorkout({
    required String id,
    required DateTime startedAt,
    List<WorkoutExercise> exercises = const [],
  }) {
    final now = DateTime.now();
    return Workout(
      id: id,
      userId: testUserId,
      startedAt: startedAt,
      exercises: exercises,
      createdAt: now,
      updatedAt: now,
    );
  }

  // 注意:completeWorkout() 是把每個 WorkoutExercise.totalVolume 欄位加總,
  // 並不是即時從 sets 的 weight*reps 重新計算(見下方 completeWorkout 測試
  // 前的說明與回報的資料層問題)。這裡比照「正常使用流程」預先算好
  // totalVolume/totalSets 才組出 WorkoutExercise,反映呼叫端(未來的
  // ViewModel)必須自行維護這兩個欄位的前提。
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
  });
}
