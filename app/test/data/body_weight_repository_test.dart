// BodyWeightRepository 測試:getLatestWeight 取最新、fetchByDateRange、
// getAverageWeight。

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/db/app_database.dart' hide BodyWeight;
import 'package:workout_record/data/models/body_weight.dart';
import 'package:workout_record/data/repositories/body_weight_repository.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;
  late BodyWeightRepository repository;

  setUp(() async {
    db = openTestDatabase();
    await seedTestUser(db);
    repository = BodyWeightRepository(db);
  });

  tearDown(() async => db.close());

  BodyWeight buildEntry({
    required String id,
    required double weight,
    required DateTime measuredAt,
  }) {
    final now = DateTime.now();
    return BodyWeight(
      id: id,
      userId: testUserId,
      weight: weight,
      measuredAt: measuredAt,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('getLatestWeight', () {
    test('回傳 measuredAt 最新的一筆,不受插入順序影響', () async {
      await repository.create(buildEntry(id: 'bw-1', weight: 70, measuredAt: DateTime(2026, 1, 5)));
      await repository.create(buildEntry(id: 'bw-3', weight: 72, measuredAt: DateTime(2026, 1, 15)));
      await repository.create(buildEntry(id: 'bw-2', weight: 71, measuredAt: DateTime(2026, 1, 10)));

      final latest = await repository.getLatestWeight();
      expect(latest, isNotNull);
      expect(latest!.id, 'bw-3');
      expect(latest.weight, 72);
    });

    test('沒有任何紀錄時回傳 null', () async {
      final latest = await repository.getLatestWeight();
      expect(latest, isNull);
    });
  });

  group('fetchByDateRange', () {
    test('含頭含尾(BETWEEN 語意),依 measuredAt 由舊到新排序', () async {
      await repository.create(buildEntry(id: 'bw-before', weight: 69, measuredAt: DateTime(2025, 12, 31)));
      await repository.create(buildEntry(id: 'bw-from', weight: 70, measuredAt: DateTime(2026, 1, 1)));
      await repository.create(buildEntry(id: 'bw-mid', weight: 71, measuredAt: DateTime(2026, 1, 15)));
      await repository.create(buildEntry(id: 'bw-to', weight: 72, measuredAt: DateTime(2026, 1, 31)));
      await repository.create(buildEntry(id: 'bw-after', weight: 73, measuredAt: DateTime(2026, 2, 1)));

      final result = await repository.fetchByDateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31));

      expect(result.map((e) => e.id).toList(), ['bw-from', 'bw-mid', 'bw-to']);
    });
  });

  group('getAverageWeight', () {
    test('計算範圍內體重的平均值', () async {
      await repository.create(buildEntry(id: 'bw-a', weight: 70, measuredAt: DateTime(2026, 1, 1)));
      await repository.create(buildEntry(id: 'bw-b', weight: 80, measuredAt: DateTime(2026, 1, 10)));
      await repository.create(buildEntry(id: 'bw-c', weight: 90, measuredAt: DateTime(2026, 1, 20)));

      final average = await repository.getAverageWeight(DateTime(2026, 1, 1), DateTime(2026, 1, 31));

      expect(average, 80);
    });

    test('範圍內沒有紀錄時回傳 null', () async {
      final average = await repository.getAverageWeight(DateTime(2030, 1, 1), DateTime(2030, 1, 31));
      expect(average, isNull);
    });
  });
}
