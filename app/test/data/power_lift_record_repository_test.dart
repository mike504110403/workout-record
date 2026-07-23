// PowerLiftRecordRepository 測試:create/update 冪等操作、getBestRecord。

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/db/app_database.dart' hide PowerLiftRecord;
import 'package:workout_record/data/models/power_lift_record.dart';
import 'package:workout_record/data/repositories/power_lift_record_repository.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;
  late PowerLiftRecordRepository repository;

  setUp(() async {
    db = openTestDatabase();
    await seedTestUser(db);
    repository = PowerLiftRecordRepository(db);
  });

  tearDown(() async => db.close());

  PowerLiftRecord buildRecord({
    required String id,
    required PowerLift lift,
    required double oneRepMax,
    DateTime? achievedAt,
  }) {
    final now = DateTime.now();
    return PowerLiftRecord(
      id: id,
      userId: testUserId,
      lift: lift,
      weight: oneRepMax,
      oneRepMax: oneRepMax,
      achievedAt: achievedAt ?? now,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('create', () {
    test('建立後可用 getById 讀回', () async {
      await repository.create(buildRecord(id: 'pl-1', lift: PowerLift.squat, oneRepMax: 100));

      final fetched = await repository.getById('pl-1');
      expect(fetched, isNotNull);
      expect(fetched!.lift, PowerLift.squat);
      expect(fetched.oneRepMax, 100);
    });
  });

  group('update', () {
    test('更新既有紀錄的數值', () async {
      await repository.create(buildRecord(id: 'pl-2', lift: PowerLift.benchPress, oneRepMax: 80));

      final existing = (await repository.getById('pl-2'))!;
      await repository.update(existing.copyWith(oneRepMax: 90, weight: 90));

      final fetched = await repository.getById('pl-2');
      expect(fetched!.oneRepMax, 90);
    });

    test('更新不存在的紀錄拋出 StateError', () async {
      final record = buildRecord(id: 'does-not-exist', lift: PowerLift.deadlift, oneRepMax: 100);
      expect(() => repository.update(record), throwsA(isA<StateError>()));
    });
  });

  group('getBestRecord', () {
    test('回傳指定三項動作中 1RM 最高的一筆', () async {
      await repository.create(buildRecord(id: 'pl-3', lift: PowerLift.deadlift, oneRepMax: 140));
      await repository.create(buildRecord(id: 'pl-4', lift: PowerLift.deadlift, oneRepMax: 160));
      await repository.create(buildRecord(id: 'pl-5', lift: PowerLift.deadlift, oneRepMax: 150));
      // 不同 lift,不應被算進來。
      await repository.create(buildRecord(id: 'pl-6', lift: PowerLift.squat, oneRepMax: 200));

      final best = await repository.getBestRecord(PowerLift.deadlift, testUserId);

      expect(best, isNotNull);
      expect(best!.id, 'pl-4');
      expect(best.oneRepMax, 160);
    });

    test('該動作沒有任何紀錄時回傳 null', () async {
      final best = await repository.getBestRecord(PowerLift.benchPress, testUserId);
      expect(best, isNull);
    });
  });

  group('deleteAll', () {
    test('刪除指定 user 的所有三項紀錄', () async {
      await repository.create(buildRecord(id: 'pl-7', lift: PowerLift.squat, oneRepMax: 100));
      await repository.create(buildRecord(id: 'pl-8', lift: PowerLift.benchPress, oneRepMax: 80));

      await repository.deleteAll(testUserId);

      final all = await repository.getAll(testUserId);
      expect(all, isEmpty);
    });
  });
}
