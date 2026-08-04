// TemplateRepository 測試:含 template exercises 的建立、update 整批重建、
// orderIndex 保序。

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/db/app_database.dart' hide TemplateExercise;
import 'package:workout_record/data/models/workout_template.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/template_repository.dart';

import 'test_helpers.dart';

void main() {
  late AppDatabase db;
  late ExerciseRepository exerciseRepository;
  late TemplateRepository repository;
  late List<String> exerciseIds;

  setUp(() async {
    db = openTestDatabase();
    await seedTestUser(db);
    exerciseRepository = ExerciseRepository(db);
    repository = TemplateRepository(db, exerciseRepository);

    final systemExercises = await exerciseRepository.fetchSystemExercises();
    exerciseIds = systemExercises.take(5).map((e) => e.id).toList();
  });

  tearDown(() async => db.close());

  WorkoutTemplate buildTemplate({
    required String id,
    required List<TemplateExercise> exercises,
  }) {
    final now = DateTime.now();
    return WorkoutTemplate(
      id: id,
      userId: testUserId,
      name: '測試模板',
      exercises: exercises,
      createdAt: now,
      updatedAt: now,
    );
  }

  TemplateExercise buildTemplateExercise({
    required String id,
    required String templateId,
    required String exerciseId,
    int orderIndex = 0,
  }) {
    return TemplateExercise(
      id: id,
      templateId: templateId,
      exerciseId: exerciseId,
      orderIndex: orderIndex,
      suggestedSets: 3,
      suggestedReps: 10,
    );
  }

  group('create', () {
    test('建立模板連同 template exercises 一併寫入,可完整讀回', () async {
      final template = buildTemplate(
        id: 'template-1',
        exercises: [
          buildTemplateExercise(id: 'te-1', templateId: 'template-1', exerciseId: exerciseIds[0]),
          buildTemplateExercise(id: 'te-2', templateId: 'template-1', exerciseId: exerciseIds[1]),
        ],
      );

      await repository.create(template);

      final fetched = await repository.fetchById('template-1');
      expect(fetched, isNotNull);
      expect(fetched!.exercises, hasLength(2));
      expect(fetched.exercises[0].exercise, isNotNull);
      expect(fetched.exercises[0].exercise!.id, exerciseIds[0]);
    });

    test('orderIndex 依插入順序自動編號(0, 1, 2, ...),與傳入清單順序無關的欄位值也一併保留', () async {
      final template = buildTemplate(
        id: 'template-2',
        exercises: [
          buildTemplateExercise(id: 'te-a', templateId: 'template-2', exerciseId: exerciseIds[0]),
          buildTemplateExercise(id: 'te-b', templateId: 'template-2', exerciseId: exerciseIds[1]),
          buildTemplateExercise(id: 'te-c', templateId: 'template-2', exerciseId: exerciseIds[2]),
        ],
      );

      await repository.create(template);

      final fetched = await repository.fetchById('template-2');
      expect(fetched!.exercises.map((e) => e.id).toList(), ['te-a', 'te-b', 'te-c']);
      expect(fetched.exercises.map((e) => e.orderIndex).toList(), [0, 1, 2]);
    });
  });

  group('update', () {
    test('整批重建 template exercises:舊的清空,換成新清單', () async {
      await repository.create(buildTemplate(
        id: 'template-3',
        exercises: [
          buildTemplateExercise(id: 'te-old-1', templateId: 'template-3', exerciseId: exerciseIds[0]),
          buildTemplateExercise(id: 'te-old-2', templateId: 'template-3', exerciseId: exerciseIds[1]),
        ],
      ));

      final updated = buildTemplate(
        id: 'template-3',
        exercises: [
          buildTemplateExercise(id: 'te-new-1', templateId: 'template-3', exerciseId: exerciseIds[2]),
        ],
      );
      await repository.update(updated);

      final fetched = await repository.fetchById('template-3');
      expect(fetched!.exercises, hasLength(1));
      expect(fetched.exercises.single.id, 'te-new-1');
      expect(fetched.exercises.single.exerciseId, exerciseIds[2]);
    });

    test('update 重建後,新清單依傳入順序保留 orderIndex', () async {
      await repository.create(buildTemplate(
        id: 'template-4',
        exercises: [
          buildTemplateExercise(id: 'te-x', templateId: 'template-4', exerciseId: exerciseIds[0]),
        ],
      ));

      final updated = buildTemplate(
        id: 'template-4',
        exercises: [
          buildTemplateExercise(id: 'te-y', templateId: 'template-4', exerciseId: exerciseIds[1]),
          buildTemplateExercise(id: 'te-z', templateId: 'template-4', exerciseId: exerciseIds[2]),
          buildTemplateExercise(id: 'te-w', templateId: 'template-4', exerciseId: exerciseIds[3]),
        ],
      );
      await repository.update(updated);

      final fetched = await repository.fetchById('template-4');
      expect(fetched!.exercises.map((e) => e.id).toList(), ['te-y', 'te-z', 'te-w']);
      expect(fetched.exercises.map((e) => e.orderIndex).toList(), [0, 1, 2]);
    });

    test('update 也更新 name/description', () async {
      await repository.create(buildTemplate(id: 'template-5', exercises: []));

      final now = DateTime.now();
      await repository.update(WorkoutTemplate(
        id: 'template-5',
        userId: testUserId,
        name: '改過的名字',
        description: '改過的描述',
        exercises: const [],
        createdAt: now,
        updatedAt: now,
      ));

      final fetched = await repository.fetchById('template-5');
      expect(fetched!.name, '改過的名字');
      expect(fetched.description, '改過的描述');
    });

    test('模板不存在時拋出 StateError', () async {
      final template = buildTemplate(id: 'does-not-exist', exercises: []);
      expect(() => repository.update(template), throwsA(isA<StateError>()));
    });
  });

  group('fetchAll', () {
    test(
        'minor 修復:isSystem = true 的列即使 userId 剛好等於查詢的使用者,'
        '也不會出現在 fetchAll(userId) 裡(防止跟 fetchSystemTemplates() 重複列出)', () async {
      final now = DateTime.now();
      // 邊界情境:一筆 isSystem = true 但 userId 剛好等於 testUserId 的模板
      // ——理論上系統模板 userId 應該是 null,但匯入來源資料沒有結構性
      // 保證,直接插一筆這樣的列來驗證 fetchAll 真的把它排除在外。
      await db.into(db.templates).insert(
            TemplatesCompanion.insert(
              id: 'edge-case-system-with-userid',
              userId: const Value(testUserId),
              name: '邊界情境系統模板',
              isSystem: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await repository.create(buildTemplate(id: 'genuinely-personal', exercises: const []));

      final personalTemplates = await repository.fetchAll(testUserId);

      expect(personalTemplates.map((t) => t.id), isNot(contains('edge-case-system-with-userid')));
      expect(personalTemplates.map((t) => t.id), contains('genuinely-personal'));
    });
  });
}
