// 資料庫建置 + 系統動作種子的煙霧測試。
// 涵蓋:建庫觸發 seedIfEmpty -> 66 筆系統動作、id 唯一、重複呼叫不重插、
// 6 個分類 UUID 正確對應 tables.dart 的 exercises schema。

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/db/seed_data.dart';

import 'test_helpers.dart';

void main() {
  group('AppDatabase seed', () {
    test('onCreate 自動 seed 出 66 筆系統動作', () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      final systemExercises = await (db.select(db.exercises)
            ..where((t) => t.isSystem.equals(true)))
          .get();

      expect(systemExercises, hasLength(66));
      expect(systemExercises.every((e) => e.isActive), isTrue);
      expect(systemExercises.every((e) => e.userId == null), isTrue);
    });

    test('系統動作 id 皆唯一', () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      final systemExercises = await (db.select(db.exercises)
            ..where((t) => t.isSystem.equals(true)))
          .get();

      final ids = systemExercises.map((e) => e.id).toSet();
      expect(ids, hasLength(systemExercises.length));
    });

    test('seedIfEmpty 重複呼叫不會重複插入', () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      // onCreate 已經呼叫過一次;這裡再手動呼叫一次應該是 no-op。
      await db.seedIfEmpty();
      await db.seedIfEmpty();

      final count = await (db.selectOnly(db.exercises)
            ..addColumns([db.exercises.id.count()])
            ..where(db.exercises.isSystem.equals(true)))
          .getSingle();

      expect(count.read(db.exercises.id.count()), 66);
    });

    test('6 個分類 UUID 與 SeedCategoryIds 常數一致', () async {
      final db = openTestDatabase();
      addTearDown(db.close);

      final systemExercises = await (db.select(db.exercises)
            ..where((t) => t.isSystem.equals(true)))
          .get();

      final categoryIds = systemExercises.map((e) => e.categoryId).toSet();
      expect(
        categoryIds,
        equals({
          SeedCategoryIds.chest,
          SeedCategoryIds.back,
          SeedCategoryIds.legs,
          SeedCategoryIds.shoulders,
          SeedCategoryIds.arms,
          SeedCategoryIds.core,
        }),
      );
    });
  });
}
