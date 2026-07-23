// PersonalRecordRepository 測試:isNewPR 判斷(更高 1RM true、更低
// false)、createIfNewPR 不覆蓋較低值、getPRSummary。

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/db/app_database.dart' hide PersonalRecord;
import 'package:workout_record/data/models/personal_record.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/personal_record_repository.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;
  late ExerciseRepository exerciseRepository;
  late PersonalRecordRepository repository;
  late String exerciseIdA;
  late String exerciseIdB;

  setUp(() async {
    db = openTestDatabase();
    await seedTestUser(db);
    exerciseRepository = ExerciseRepository(db);
    repository = PersonalRecordRepository(db, exerciseRepository);

    final systemExercises = await exerciseRepository.fetchSystemExercises();
    exerciseIdA = systemExercises[0].id;
    exerciseIdB = systemExercises[1].id;
  });

  tearDown(() async => db.close());

  PersonalRecord buildPR({
    required String id,
    required String exerciseId,
    required double oneRepMax,
    DateTime? achievedAt,
  }) {
    final now = DateTime.now();
    return PersonalRecord(
      id: id,
      userId: testUserId,
      exerciseId: exerciseId,
      weight: oneRepMax,
      reps: 1,
      oneRepMax: oneRepMax,
      achievedAt: achievedAt ?? now,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('isNewPR', () {
    test('尚無任何紀錄時,任何 1RM 都算新 PR', () async {
      final isNew = await repository.isNewPR(exerciseIdA, 100);
      expect(isNew, isTrue);
    });

    test('更高的 1RM 判定為新 PR', () async {
      await repository.create(buildPR(id: 'pr-1', exerciseId: exerciseIdA, oneRepMax: 100));

      final isNew = await repository.isNewPR(exerciseIdA, 110);
      expect(isNew, isTrue);
    });

    test('更低或相等的 1RM 不算新 PR', () async {
      await repository.create(buildPR(id: 'pr-2', exerciseId: exerciseIdA, oneRepMax: 100));

      expect(await repository.isNewPR(exerciseIdA, 90), isFalse);
      expect(await repository.isNewPR(exerciseIdA, 100), isFalse);
    });
  });

  group('createIfNewPR', () {
    test('1RM 較高時寫入新紀錄並回傳該紀錄', () async {
      await repository.create(buildPR(id: 'pr-3', exerciseId: exerciseIdA, oneRepMax: 100));

      final created = await repository.createIfNewPR(
        buildPR(id: 'pr-4', exerciseId: exerciseIdA, oneRepMax: 120),
      );

      expect(created, isNotNull);
      expect(created!.id, 'pr-4');

      final all = await repository.fetchByExercise(exerciseIdA);
      expect(all, hasLength(2));
    });

    test('1RM 較低時不覆蓋既有較高紀錄,回傳 null 且不寫入', () async {
      await repository.create(buildPR(id: 'pr-5', exerciseId: exerciseIdA, oneRepMax: 100));

      final created = await repository.createIfNewPR(
        buildPR(id: 'pr-6', exerciseId: exerciseIdA, oneRepMax: 80),
      );

      expect(created, isNull);

      final all = await repository.fetchByExercise(exerciseIdA);
      expect(all, hasLength(1));
      expect(all.single.id, 'pr-5');
      expect(all.single.oneRepMax, 100);
    });
  });

  group('getPRSummary', () {
    test('依動作分組,current PR 是各組最高的一筆,history 依時間新到舊排序', () async {
      await repository.create(buildPR(
        id: 'pr-a1',
        exerciseId: exerciseIdA,
        oneRepMax: 100,
        achievedAt: DateTime(2026, 1, 1),
      ));
      await repository.create(buildPR(
        id: 'pr-a2',
        exerciseId: exerciseIdA,
        oneRepMax: 120,
        achievedAt: DateTime(2026, 1, 10),
      ));
      await repository.create(buildPR(
        id: 'pr-b1',
        exerciseId: exerciseIdB,
        oneRepMax: 50,
        achievedAt: DateTime(2026, 1, 5),
      ));

      final summary = await repository.getPRSummary(testUserId);

      expect(summary, hasLength(2));

      final summaryA = summary.firstWhere((s) => s.exerciseId == exerciseIdA);
      expect(summaryA.currentPR!.id, 'pr-a2');
      expect(summaryA.oneRepMax, 120);
      expect(summaryA.prHistory.map((p) => p.id).toList(), ['pr-a2', 'pr-a1']);

      final summaryB = summary.firstWhere((s) => s.exerciseId == exerciseIdB);
      expect(summaryB.currentPR!.id, 'pr-b1');
      expect(summaryB.oneRepMax, 50);
    });

    test('沒有任何 PR 時回傳空清單', () async {
      final summary = await repository.getPRSummary(testUserId);
      expect(summary, isEmpty);
    });
  });
}
