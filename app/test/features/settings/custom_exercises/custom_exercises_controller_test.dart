// CustomExercisesController seam:直接用 ProviderContainer 呼叫(不經 widget 樹),
// 驗證列表範圍、新增/編輯/刪除落地、名稱驗證,以及「刪除 = 軟刪除」不會弄壞
// 被歷史訓練引用的動作。
//
// 變異清單(各自讓對應測試必紅):
// - getCustomExercises 換成 fetchAll → 「只列自定義動作」紅
// - deleteExercise 改呼叫 permanentDelete → 「被訓練引用」紅(FK violation)
// - _afterMutation 拿掉 invalidate → 「選動作器 live 時」紅
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide Exercise, Workout, WorkoutExercise;
import 'package:workout_record/data/db/seed_data.dart';
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/custom_exercises/custom_exercises_controller.dart';
import 'package:workout_record/features/workout/exercise_picker/exercise_picker_controller.dart';

import '../../../data/test_helpers.dart';

class _ThrowingDeleteExerciseRepository extends DriftExerciseRepository {
  _ThrowingDeleteExerciseRepository(super.db);

  @override
  Future<void> delete(String id) async => throw Exception('模擬刪除失敗');
}

Exercise _custom(String id, String name, {bool isActive = true, bool isSystem = false}) {
  final now = DateTime(2026, 1, 1);
  return Exercise(
    id: id,
    name: name,
    nameEn: 'EN $name',
    categoryId: SeedCategoryIds.chest,
    type: ExerciseType.machine,
    primaryMuscleGroup: PrimaryMuscleGroup.chest,
    movementPattern: MovementPattern.push,
    description: '說明 $name',
    isSystem: isSystem,
    isActive: isActive,
    userId: testUserId,
    createdAt: now,
    updatedAt: now,
  );
}

typedef _Harness = ({AppDatabase db, ProviderContainer container, ExerciseRepository repo});

Future<_Harness> _setUp({ExerciseRepository Function(AppDatabase db)? repoBuilder}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);
  final repo = repoBuilder?.call(db) ?? DriftExerciseRepository(db);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      exerciseRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return (db: db, container: container, repo: repo);
}

CustomExercisesController _notifier(ProviderContainer c) =>
    c.read(customExercisesControllerProvider.notifier);

void main() {
  test('只列自定義動作:系統動作與已刪除(inactive)的自定義動作都不列', () async {
    final h = await _setUp();
    await h.repo.create(_custom('c-1', '史密斯臥推'));
    await h.repo.create(_custom('c-2', '側拉'));
    await h.repo.create(_custom('c-gone', '已刪除的動作', isActive: false));

    final list = await h.container.read(customExercisesControllerProvider.future);

    expect(list.map((e) => e.name), unorderedEquals(['史密斯臥推', '側拉']));
    expect(list.every((e) => !e.isSystem), isTrue);
    // 系統動作確實存在於 DB(66 筆種子),只是不列。
    expect((await h.repo.fetchSystemExercises()), isNotEmpty);
  });

  test('create:寫入 DB(isSystem=false、userId 為登入者、欄位落地)並出現在列表', () async {
    final h = await _setUp();
    await h.container.read(customExercisesControllerProvider.future);

    final created = await _notifier(h.container).create(
      name: '  彈力帶划船 ',
      categoryId: SeedCategoryIds.back,
      type: ExerciseType.bodyweight,
      primaryMuscleGroup: PrimaryMuscleGroup.back,
      movementPattern: MovementPattern.pull,
      description: '  居家用  ',
    );

    final row = await h.repo.fetchById(created.id);
    expect(row, isNotNull);
    expect(row!.name, '彈力帶划船');
    expect(row.categoryId, SeedCategoryIds.back);
    expect(row.type, ExerciseType.bodyweight);
    expect(row.primaryMuscleGroup, PrimaryMuscleGroup.back);
    expect(row.movementPattern, MovementPattern.pull);
    expect(row.description, '居家用');
    expect(row.isSystem, isFalse);
    expect(row.isActive, isTrue);
    expect(row.userId, testUserId);
    expect(
      h.container.read(customExercisesControllerProvider).value!.map((e) => e.id),
      contains(created.id),
    );
  });

  test('create:空白說明存成 null', () async {
    final h = await _setUp();
    final created = await _notifier(h.container).create(
      name: '空說明動作',
      categoryId: SeedCategoryIds.core,
      type: ExerciseType.freeWeight,
      description: '   ',
    );
    expect((await h.repo.fetchById(created.id))!.description, isNull);
  });

  group('validateName', () {
    test('空白 / 太短 / 太長 / 與既有自定義動作重名 → 錯誤;編輯自己不算重名', () async {
      final h = await _setUp();
      await h.repo.create(_custom('c-1', '史密斯臥推'));
      await h.container.read(customExercisesControllerProvider.future);
      final n = _notifier(h.container);

      expect(n.validateName('   '), '動作名稱不能為空');
      expect(n.validateName('臥'), contains('至少'));
      expect(n.validateName('臥' * 51), contains('不能超過'));
      expect(n.validateName(' 史密斯臥推 '), '此動作名稱已存在');
      expect(n.validateName('史密斯臥推', excludeId: 'c-1'), isNull);
      expect(n.validateName('全新名稱'), isNull);
    });
  });

  test('updateExercise:名稱/分類/類型/肌群/模式/說明落地;肌群改回未選擇與清空說明真的變 null;英文名稱保留', () async {
    final h = await _setUp();
    final original = _custom('c-1', '史密斯臥推');
    await h.repo.create(original);
    await h.container.read(customExercisesControllerProvider.future);

    await _notifier(h.container).updateExercise(
      original,
      name: '史密斯上斜臥推',
      categoryId: SeedCategoryIds.shoulders,
      type: ExerciseType.freeWeight,
      primaryMuscleGroup: null,
      movementPattern: null,
      description: '',
    );

    final row = (await h.repo.fetchById('c-1'))!;
    expect(row.name, '史密斯上斜臥推');
    expect(row.categoryId, SeedCategoryIds.shoulders);
    expect(row.type, ExerciseType.freeWeight);
    expect(row.primaryMuscleGroup, isNull);
    expect(row.movementPattern, isNull);
    expect(row.description, isNull);
    expect(row.nameEn, 'EN 史密斯臥推');
    expect(row.isActive, isTrue);
    expect(h.container.read(customExercisesControllerProvider).value!.single.name, '史密斯上斜臥推');
  });

  test('updateExercise / deleteExercise 對系統動作一律拒絕', () async {
    final h = await _setUp();
    await h.container.read(customExercisesControllerProvider.future);
    final system = (await h.repo.fetchSystemExercises()).first;

    expect(
      () => _notifier(
        h.container,
      ).updateExercise(system, name: '改名', categoryId: system.categoryId, type: system.type),
      throwsStateError,
    );
    expect(() => _notifier(h.container).deleteExercise(system), throwsStateError);
  });

  group('deleteExercise = 軟刪除', () {
    test('列表消失、列保留且 isActive=false;fetchAll / fetchByCategory 都看不到', () async {
      final h = await _setUp();
      final ex = _custom('c-1', '史密斯臥推');
      await h.repo.create(ex);
      await h.container.read(customExercisesControllerProvider.future);

      await _notifier(h.container).deleteExercise(ex);

      expect(h.container.read(customExercisesControllerProvider).value, isEmpty);
      final row = await h.repo.fetchById('c-1');
      expect(row, isNotNull);
      expect(row!.isActive, isFalse);
      expect((await h.repo.fetchAll()).map((e) => e.id), isNot(contains('c-1')));
      expect(
        (await h.repo.fetchByCategory(SeedCategoryIds.chest)).map((e) => e.id),
        isNot(contains('c-1')),
      );
    });

    test('被歷史訓練引用的動作:刪除不報錯,歷史訓練仍讀得到該動作(名稱不變)', () async {
      final h = await _setUp();
      final ex = _custom('c-1', '史密斯臥推');
      await h.repo.create(ex);
      final workoutRepo = h.container.read(workoutRepositoryProvider);
      final now = DateTime(2026, 1, 10, 8);
      await workoutRepo.create(
        Workout(
          id: 'w-1',
          userId: testUserId,
          startedAt: now,
          endedAt: now.add(const Duration(hours: 1)),
          exercises: [
            WorkoutExercise(
              id: 'we-1',
              workoutId: 'w-1',
              exerciseId: 'c-1',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await h.container.read(customExercisesControllerProvider.future);

      // 對照組:實體刪除會因 FK 被擋——這就是不採用 permanentDelete 的原因。
      await expectLater(h.repo.permanentDelete('c-1'), throwsA(anything));

      await _notifier(h.container).deleteExercise(ex);

      final workout = (await workoutRepo.fetchById('w-1'))!;
      expect(workout.exercises, hasLength(1));
      expect(workout.exercises.single.exercise?.name, '史密斯臥推');
    });

    test('寫入失敗:往外拋、列表還原、選動作器不受影響', () async {
      final h = await _setUp(repoBuilder: _ThrowingDeleteExerciseRepository.new);
      final ex = _custom('c-1', '史密斯臥推');
      await h.repo.create(ex);
      await h.container.read(customExercisesControllerProvider.future);

      await expectLater(_notifier(h.container).deleteExercise(ex), throwsException);

      expect(h.container.read(customExercisesControllerProvider).value!.map((e) => e.id), ['c-1']);
      expect((await h.repo.fetchById('c-1'))!.isActive, isTrue);
    });
  });

  group('選動作器同步', () {
    test('選動作器仍存活時:新增後重建能看到新動作、刪除後看不到', () async {
      final h = await _setUp();
      // 以 listen 讓 autoDispose 的 picker 保持存活,模擬仍在樹上的 picker。
      final sub = h.container.listen(exercisePickerControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final before = await h.container.read(exercisePickerControllerProvider.future);
      await h.container.read(customExercisesControllerProvider.future);

      final created = await _notifier(
        h.container,
      ).create(name: '新自訂動作', categoryId: SeedCategoryIds.arms, type: ExerciseType.machine);
      final afterCreate = await h.container.read(exercisePickerControllerProvider.future);
      expect(before.allExercises.map((e) => e.id), isNot(contains(created.id)));
      expect(afterCreate.allExercises.map((e) => e.id), contains(created.id));

      await _notifier(h.container).deleteExercise(created);
      final afterDelete = await h.container.read(exercisePickerControllerProvider.future);
      expect(afterDelete.allExercises.map((e) => e.id), isNot(contains(created.id)));
    });

    test('編輯後選動作器看到新名稱', () async {
      final h = await _setUp();
      final ex = _custom('c-1', '舊名稱動作');
      await h.repo.create(ex);
      final sub = h.container.listen(exercisePickerControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await h.container.read(exercisePickerControllerProvider.future);
      await h.container.read(customExercisesControllerProvider.future);

      await _notifier(
        h.container,
      ).updateExercise(ex, name: '新名稱動作', categoryId: ex.categoryId, type: ex.type);

      final picker = await h.container.read(exercisePickerControllerProvider.future);
      final names = picker.allExercises.map((e) => e.name);
      expect(names, contains('新名稱動作'));
      expect(names, isNot(contains('舊名稱動作')));
    });
  });
}
