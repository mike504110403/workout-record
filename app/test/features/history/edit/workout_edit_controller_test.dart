// WorkoutEditController 的 PR 結算(只升不降)測試——見 brief「波 5 編輯已
// 完成訓練」驗收標準 4。走 ProviderContainer + 真實 repository(appDatabaseProvider
// 換 in-memory DB),不 pump widget:PR 結算是 controller 層的業務邏輯,不需要
// 畫面互動就能驗證,harness 慣例(真實 repository、只換 DB)對齊
// dashboard_page_test.dart。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, PersonalRecord;
import 'package:workout_record/data/models/personal_record.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/personal_record_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/history/edit/workout_edit_controller.dart';

import '../../../data/test_helpers.dart';

/// Drift 的 dateTime() 欄位預設用整數秒精度存欄位(不是毫秒)——直接拿
/// `DateTime.now()` 種 fixture,寫入再讀回來會失去毫秒,跟記憶體裡原始值
/// 比較時 flaky(同 dashboard_page_test.dart harness 註解提過的雷)。這裡種
/// 下去的每個時間戳都先截斷到秒,DB 往返後仍與記憶體裡的原始值相等。
DateTime _secondPrecisionNow() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, now.hour, now.minute, now.second);
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late WorkoutRepository workoutRepo;
  late PersonalRecordRepository prRepo;
  late String exerciseId;

  setUp(() async {
    db = openTestDatabase();
    await seedTestUser(db);
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    addTearDown(db.close);

    workoutRepo = container.read(workoutRepositoryProvider);
    prRepo = container.read(personalRecordRepositoryProvider);
    final exerciseRepo = ExerciseRepository(db);
    exerciseId = (await exerciseRepo.fetchSystemExercises()).first.id;
  });

  /// 種一筆已完成的訓練,含一個動作、一組(供編輯測試改動)。[note] 選填,
  /// 預設 null(供 Spec-3 清空備註測試種一筆「已經有備註」的訓練)。
  Future<void> seedCompletedWorkout({
    required String workoutId,
    required String workoutExerciseId,
    required String setId,
    required double weight,
    required int reps,
    String? note,
  }) async {
    final now = _secondPrecisionNow();
    await workoutRepo.create(Workout(
      id: workoutId,
      userId: testUserId,
      startedAt: now.subtract(const Duration(hours: 1)),
      endedAt: now,
      duration: 60,
      note: note,
      createdAt: now,
      updatedAt: now,
      exercises: [
        WorkoutExercise(
          id: workoutExerciseId,
          workoutId: workoutId,
          exerciseId: exerciseId,
          createdAt: now,
          updatedAt: now,
          sets: [
            WorkoutSet(
              id: setId,
              workoutExerciseId: workoutExerciseId,
              setNumber: 1,
              weight: weight,
              reps: reps,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      ],
    ));
  }

  test('編輯把某組改成史上新高 → PersonalRecords 出現新列', () async {
    // 種一筆既有 PR(較低),不屬於待編輯的這筆訓練。
    final now = _secondPrecisionNow();
    await prRepo.create(PersonalRecord(
      id: 'existing-pr-upgrade',
      userId: testUserId,
      exerciseId: exerciseId,
      weight: 50,
      reps: 5,
      oneRepMax: 58.3,
      achievedAt: now.subtract(const Duration(days: 30)),
      workoutId: 'some-other-workout',
      createdAt: now,
      updatedAt: now,
    ));

    await seedCompletedWorkout(
      workoutId: 'edit-upgrade',
      workoutExerciseId: 'we-upgrade',
      setId: 'set-upgrade',
      weight: 40,
      reps: 5,
    );

    final notifier = container.read(workoutEditControllerProvider('edit-upgrade').notifier);
    await container.read(workoutEditControllerProvider('edit-upgrade').future);

    // 改成遠高於既有 PR 的重量,確保 1RM 一定超越(不依賴公式精確值,只要
    // 邊界夠大就不會被公式細節影響斷言穩定性)。
    await notifier.updateSet(WorkoutSet(
      id: 'set-upgrade',
      workoutExerciseId: 'we-upgrade',
      setNumber: 1,
      weight: 200,
      reps: 5,
      createdAt: now,
      updatedAt: now,
    ));

    final prs = await prRepo.fetchByExercise(exerciseId);
    expect(prs, hasLength(2));
    final newPr = prs.firstWhere((p) => p.id != 'existing-pr-upgrade');
    expect(newPr.weight, 200);
    expect(newPr.reps, 5);
    expect(newPr.workoutId, 'edit-upgrade');
    expect(newPr.oneRepMax, greaterThan(58.3));
  });

  test('編輯把重量改低 → 既有 PR 列一字不動', () async {
    final now = _secondPrecisionNow();
    final originalPr = PersonalRecord(
      id: 'existing-pr-no-downgrade',
      userId: testUserId,
      exerciseId: exerciseId,
      weight: 100,
      reps: 5,
      oneRepMax: 116.7,
      achievedAt: now.subtract(const Duration(days: 10)),
      workoutId: 'some-other-workout-2',
      createdAt: now.subtract(const Duration(days: 10)),
      updatedAt: now.subtract(const Duration(days: 10)),
    );
    await prRepo.create(originalPr);

    await seedCompletedWorkout(
      workoutId: 'edit-downgrade',
      workoutExerciseId: 'we-downgrade',
      setId: 'set-downgrade',
      weight: 90,
      reps: 5,
    );

    final notifier = container.read(workoutEditControllerProvider('edit-downgrade').notifier);
    await container.read(workoutEditControllerProvider('edit-downgrade').future);

    // 改成遠低於既有 PR 的重量,確保 1RM 一定低於(同上,不依賴公式精確值)。
    await notifier.updateSet(WorkoutSet(
      id: 'set-downgrade',
      workoutExerciseId: 'we-downgrade',
      setNumber: 1,
      weight: 10,
      reps: 5,
      createdAt: now,
      updatedAt: now,
    ));

    final prs = await prRepo.fetchByExercise(exerciseId);
    expect(prs, hasLength(1));
    // 參照物是編輯前種下的獨立 PR 列(`originalPr`),不是重算出來的值——
    // 逐欄位比對整列一字不動。
    final unchanged = prs.single;
    expect(unchanged.id, originalPr.id);
    expect(unchanged.weight, originalPr.weight);
    expect(unchanged.reps, originalPr.reps);
    expect(unchanged.oneRepMax, originalPr.oneRepMax);
    expect(unchanged.achievedAt, originalPr.achievedAt);
    expect(unchanged.workoutId, originalPr.workoutId);
    expect(unchanged.createdAt, originalPr.createdAt);
    expect(unchanged.updatedAt, originalPr.updatedAt);
  });

  test('每個動作只送一次候選:同一動作多組,只有最高 1RM 的那組決定是否創 PR', () async {
    // 動作有兩組:一組較重但次數少(1RM 較低)、一組較輕但次數多(Epley
    // 公式換算後 1RM 較高)——驗證「以其最高一組算 1RM」不是單純比重量。
    // weight=60,reps=1 → 1RM = 60(reps<=1 不套公式)。
    // weight=50,reps=10 → 1RM = 50 * (1 + 10/30) = 66.67,比上面那組高。
    final now = _secondPrecisionNow();
    await workoutRepo.create(Workout(
      id: 'edit-best-set',
      userId: testUserId,
      startedAt: now.subtract(const Duration(hours: 1)),
      endedAt: now,
      duration: 60,
      createdAt: now,
      updatedAt: now,
      exercises: [
        WorkoutExercise(
          id: 'we-best-set',
          workoutId: 'edit-best-set',
          exerciseId: exerciseId,
          createdAt: now,
          updatedAt: now,
          sets: [
            WorkoutSet(
              id: 'set-best-set-heavy',
              workoutExerciseId: 'we-best-set',
              setNumber: 1,
              weight: 60,
              reps: 1,
              createdAt: now,
              updatedAt: now,
            ),
            WorkoutSet(
              id: 'set-best-set-light-highrep',
              workoutExerciseId: 'we-best-set',
              setNumber: 2,
              weight: 50,
              reps: 10,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      ],
    ));

    final notifier = container.read(workoutEditControllerProvider('edit-best-set').notifier);
    await container.read(workoutEditControllerProvider('edit-best-set').future);

    // 觸發一次寫穿(改備註)讓 PR 結算跑一次;動作本身沒有任何暖身組。
    await notifier.updateNote('觸發 PR 結算');

    final prs = await prRepo.fetchByExercise(exerciseId);
    expect(prs, hasLength(1));
    expect(prs.single.weight, 50);
    expect(prs.single.reps, 10);
  });

  // code review Spec-3:清空備註目前用完整具名建構子繞開 `Workout.copyWith`
  // 的 `note ?? this.note` 限制(見 workout_edit_controller.dart
  // `updateNote` 文件)——這條測試沒有的話,這個「繞開」本身零防護:有人
  // 手滑把 `updateNote` 改回 `draft.copyWith(note: note)` 這種看起來更簡潔
  // 的寫法,不會有任何測試變紅(其他測試都只測「設定一個非 null 的新
  // 備註」,`note ?? this.note` 在那個情境下行為剛好正確)。
  //
  // 雙向變異(已實測,見波 5 code review 回報第 2 則附的紅版輸出):把
  // `updateNote` 的實作換成 `_mutate((draft) => ref.read(...).update(draft
  // .copyWith(note: note)))`,這則測試會紅(`fetched.note` 停留在「舊備註」
  // 而不是變成 null)。
  test('清空備註(傳 null)→ DB note 真的變成 null,不是被 copyWith 的 ?? 語意擋下', () async {
    await seedCompletedWorkout(
      workoutId: 'edit-clear-note',
      workoutExerciseId: 'we-clear-note',
      setId: 'set-clear-note',
      weight: 40,
      reps: 8,
      note: '舊備註',
    );

    final notifier = container.read(workoutEditControllerProvider('edit-clear-note').notifier);
    await container.read(workoutEditControllerProvider('edit-clear-note').future);

    final before = await workoutRepo.fetchById('edit-clear-note');
    expect(before!.note, '舊備註');

    await notifier.updateNote(null);

    final fetched = await workoutRepo.fetchById('edit-clear-note');
    expect(fetched!.note, isNull);
  });

  // code review Std-2:build() 前置守衛——對草稿(endedAt IS NULL)呼叫這個
  // controller 要在 build() 當下就拋錯,不是等到第一次編輯操作觸發
  // `recomputeSummary` 的守衛才半路失敗。
  test('build() 前置守衛:對草稿(endedAt IS NULL)呼叫 → provider 落 AsyncError,不是先成功再半路壞掉', () async {
    final now = _secondPrecisionNow();
    await workoutRepo.create(Workout(
      id: 'edit-still-draft',
      userId: testUserId,
      startedAt: now,
      endedAt: null,
      createdAt: now,
      updatedAt: now,
    ));

    await expectLater(
      () => container.read(workoutEditControllerProvider('edit-still-draft').future),
      throwsA(isA<StateError>()),
    );

    // provider 落在 AsyncError,不是 AsyncData——確認真的是「進頁面就失敗」
    // 而不是「build 成功、隨便留了個奇怪的 state」。
    final asyncValue = container.read(workoutEditControllerProvider('edit-still-draft'));
    expect(asyncValue.hasError, isTrue);
    expect(asyncValue.hasValue, isFalse);
  });

  // code review Std-8:序列化寫入——不 await 連續呼叫兩次變更方法,驗證
  // `_synchronized` 真的讓它們依序完成(不是並發交錯把其中一個寫入蓋掉/
  // 半路互相踩到),而且收尾的 summary 收斂成兩次都生效後的正確值。
  test('_synchronized 序列化:不 await 連續呼叫兩次 addSet → 依序完成,兩組都在、summary 收斂正確',
      () async {
    await seedCompletedWorkout(
      workoutId: 'edit-concurrent',
      workoutExerciseId: 'we-concurrent',
      setId: 'set-concurrent-seed',
      weight: 10,
      reps: 10, // 種子組容量 100
    );

    final notifier = container.read(workoutEditControllerProvider('edit-concurrent').notifier);
    await container.read(workoutEditControllerProvider('edit-concurrent').future);

    // 刻意不 await 第一個呼叫就發第二個——兩個呼叫的 Future 幾乎同時掛進
    // `_synchronized` 佇列,驗證鎖真的讓它們排隊依序跑完,不是互相打斷。
    final first = notifier.addSet(
      workoutExerciseId: 'we-concurrent',
      weight: 20,
      reps: 5, // 容量 100
    );
    final second = notifier.addSet(
      workoutExerciseId: 'we-concurrent',
      weight: 30,
      reps: 5, // 容量 150
    );
    await Future.wait([first, second]);

    final fetched = await workoutRepo.fetchById('edit-concurrent');
    // 三組都在(種子 1 + 新增 2),沒有任何一次呼叫被蓋掉/漏寫。
    expect(fetched!.exercises.single.sets, hasLength(3));
    // summary 收斂成三組加總後的正確值:100 + 100 + 150 = 350。
    expect(fetched.totalVolume, 350);
    expect(fetched.totalSets, 3);
    // setNumber 依序遞增、沒有撞號(序列化保證每次呼叫讀到的
    // `exercise.sets.length` 是上一次寫入完成之後的最新值)。
    final setNumbers = fetched.exercises.single.sets.map((s) => s.setNumber).toList()..sort();
    expect(setNumbers, [1, 2, 3]);
  });
}
