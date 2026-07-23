// ExerciseRepository 測試:系統/自訂動作查詢、search、軟刪除後
// fetchAll(includeInactive:false) 看不到。

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/db/app_database.dart' hide Exercise;
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;
  late ExerciseRepository repository;

  setUp(() async {
    db = openTestDatabase();
    await seedTestUser(db);
    repository = ExerciseRepository(db);
  });

  tearDown(() async => db.close());

  Exercise buildCustomExercise({
    required String id,
    required String name,
    String? nameEn,
  }) {
    final now = DateTime.now();
    return Exercise(
      id: id,
      name: name,
      nameEn: nameEn,
      categoryId: 'custom-category',
      type: ExerciseType.freeWeight,
      isSystem: false,
      userId: testUserId,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('系統/自訂動作查詢', () {
    test('fetchSystemExercises 只回傳 isSystem = true 的 66 筆內建動作', () async {
      final result = await repository.fetchSystemExercises();
      expect(result, hasLength(66));
      expect(result.every((e) => e.isSystem), isTrue);
    });

    test('fetchCustomExercises 只回傳指定 userId 的自訂動作', () async {
      await repository.create(buildCustomExercise(id: 'custom-1', name: '自訂動作 A'));
      await repository.create(buildCustomExercise(id: 'custom-2', name: '自訂動作 B'));

      final result = await repository.fetchCustomExercises(testUserId);

      expect(result, hasLength(2));
      expect(result.every((e) => !e.isSystem), isTrue);
      expect(result.map((e) => e.id).toSet(), {'custom-1', 'custom-2'});
    });

    test('fetchByCategory 只回傳該分類且 isActive 的動作', () async {
      final result = await repository.fetchByCategory(
        '00000000-0000-0000-0000-000000000001', // 胸部
      );
      expect(result, hasLength(12));
      expect(result.every((e) => e.categoryId == '00000000-0000-0000-0000-000000000001'), isTrue);
    });
  });

  group('search', () {
    test('依中文名稱關鍵字搜尋', () async {
      final result = await repository.search('臥推');
      expect(result, isNotEmpty);
      expect(result.every((e) => e.name.contains('臥推')), isTrue);
    });

    test('依英文名稱關鍵字搜尋', () async {
      final result = await repository.search('Squat');
      expect(result, isNotEmpty);
      expect(result.any((e) => e.name == '深蹲'), isTrue);
    });

    test('查無結果回傳空清單', () async {
      final result = await repository.search('不存在的動作關鍵字xyz');
      expect(result, isEmpty);
    });
  });

  group('軟刪除', () {
    test('delete 後 fetchAll(includeInactive:false) 看不到該動作', () async {
      await repository.create(buildCustomExercise(id: 'custom-3', name: '待刪除動作'));

      final beforeDelete = await repository.fetchAll();
      expect(beforeDelete.any((e) => e.id == 'custom-3'), isTrue);

      await repository.delete('custom-3');

      final afterDelete = await repository.fetchAll();
      expect(afterDelete.any((e) => e.id == 'custom-3'), isFalse);

      // includeInactive:true 仍然找得到,且已標記為 isActive = false。
      final afterDeleteIncludeInactive = await repository.fetchAll(includeInactive: true);
      final softDeleted = afterDeleteIncludeInactive.firstWhere((e) => e.id == 'custom-3');
      expect(softDeleted.isActive, isFalse);
    });

    test('fetchById 在軟刪除後仍能查到(只是 isActive 變 false,列表看不到)', () async {
      await repository.create(buildCustomExercise(id: 'custom-4', name: '另一個待刪除動作'));
      await repository.delete('custom-4');

      final fetched = await repository.fetchById('custom-4');
      expect(fetched, isNotNull);
      expect(fetched!.isActive, isFalse);
    });
  });
}
