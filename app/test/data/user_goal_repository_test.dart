// UserGoalRepository 測試:createOrUpdate 冪等(同一 userId 只留一筆,
// 沿用原 id、更新內容)、fetchByUser、delete。

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/db/app_database.dart' hide UserGoal;
import 'package:workout_record/data/models/user_goal.dart';
import 'package:workout_record/data/repositories/user_goal_repository.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;
  late UserGoalRepository repository;

  setUp(() async {
    db = openTestDatabase();
    await seedTestUser(db);
    repository = UserGoalRepository(db);
  });

  tearDown(() async => db.close());

  UserGoal buildGoal({
    required String id,
    int weeklyWorkoutGoal = 3,
    double? targetWeight,
    VolumeGoals volumeGoals = const VolumeGoals(),
  }) {
    final now = DateTime.now();
    return UserGoal(
      id: id,
      userId: testUserId,
      weeklyWorkoutGoal: weeklyWorkoutGoal,
      targetWeight: targetWeight,
      volumeGoals: volumeGoals,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('createOrUpdate', () {
    test('第一次呼叫是 insert,可讀回', () async {
      await repository.createOrUpdate(buildGoal(id: 'goal-1', weeklyWorkoutGoal: 4, targetWeight: 75));

      final fetched = await repository.fetchByUser(testUserId);
      expect(fetched, isNotNull);
      expect(fetched!.weeklyWorkoutGoal, 4);
      expect(fetched.targetWeight, 75);
    });

    test('冪等:同一 userId 重複呼叫只留一筆,且沿用第一筆的 row(userId 唯一)', () async {
      await repository.createOrUpdate(buildGoal(id: 'goal-2', weeklyWorkoutGoal: 3, targetWeight: 70));
      await repository.createOrUpdate(buildGoal(id: 'goal-3', weeklyWorkoutGoal: 5, targetWeight: 80));

      final rows = await db.select(db.userGoals).get();
      expect(rows, hasLength(1));

      final fetched = await repository.fetchByUser(testUserId);
      expect(fetched!.weeklyWorkoutGoal, 5);
      expect(fetched.targetWeight, 80);
    });

    test('第二次呼叫會更新 volumeGoals 各肌群欄位', () async {
      await repository.createOrUpdate(buildGoal(id: 'goal-4'));
      await repository.createOrUpdate(buildGoal(
        id: 'goal-5',
        volumeGoals: const VolumeGoals(chest: 1000, back: 1200, legs: 1500),
      ));

      final fetched = await repository.fetchByUser(testUserId);
      expect(fetched!.volumeGoals.chest, 1000);
      expect(fetched.volumeGoals.back, 1200);
      expect(fetched.volumeGoals.legs, 1500);
    });
  });

  group('fetchByUser', () {
    test('沒有目標時回傳 null', () async {
      final fetched = await repository.fetchByUser(testUserId);
      expect(fetched, isNull);
    });
  });

  group('delete', () {
    test('刪除後 fetchByUser 回傳 null', () async {
      await repository.createOrUpdate(buildGoal(id: 'goal-6'));
      await repository.delete(testUserId);

      final fetched = await repository.fetchByUser(testUserId);
      expect(fetched, isNull);
    });
  });
}
