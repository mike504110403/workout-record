// WorkoutController seam:直接透過 ProviderContainer 呼叫 controller 方法
// (不經 widget 樹),真 in-memory DB + 真 repositories,只 override DB/prefs
// (對照 brief seam 規格)。涵蓋:開始訓練、進行中操作(草稿寫穿即時落地,
// 獨立 SELECT 驗證)、矩陣(重複/亂序呼叫)、草稿寫穿不變式(重啟完整還原、
// 完成/放棄後無草稿殘留)。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, Exercise;
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/personal_record_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/templates/applied_template.dart';
import 'package:workout_record/features/workout/workout_controller.dart';

import '../../data/test_helpers.dart';

typedef _Harness = ({AppDatabase db, ProviderContainer container});

/// M4 失敗路徑測試專用:模擬 `WorkoutRepository.completeWorkout` 寫入失敗。
/// 只覆寫這一個方法,其餘沿用真實實作,對照
/// templates_crud_test.dart `_ThrowingCreateTemplateRepository` 既有慣例。
class _ThrowingCompleteWorkoutRepository extends WorkoutRepository {
  _ThrowingCompleteWorkoutRepository(super.db, super.exerciseRepository);

  @override
  Future<Workout> completeWorkout(String workoutId, {DateTime? endedAt}) async {
    throw Exception('模擬完成訓練寫入失敗(失敗路徑測試用)');
  }
}

/// M4 失敗路徑測試專用:模擬 `WorkoutRepository.discardDraft` 寫入失敗。
class _ThrowingDiscardDraftRepository extends WorkoutRepository {
  _ThrowingDiscardDraftRepository(super.db, super.exerciseRepository);

  @override
  Future<void> discardDraft(String workoutId) async {
    throw Exception('模擬放棄訓練寫入失敗(失敗路徑測試用)');
  }
}

Future<_Harness> _setUpHarness({
  WorkoutRepository Function(AppDatabase db)? workoutRepoBuilder,
}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (workoutRepoBuilder != null)
        workoutRepositoryProvider.overrideWithValue(workoutRepoBuilder(db)),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (db: db, container: container);
}

Future<Exercise> _firstSystemExercise(AppDatabase db) async {
  final exercises = await ExerciseRepository(db).fetchSystemExercises();
  return exercises.first;
}

void main() {
  group('開始訓練', () {
    test('開始自由訓練:建立 endedAt=null 的草稿,無動作', () async {
      final harness = await _setUpHarness();
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);

      await notifier.startFreeWorkout();

      final state = harness.container.read(workoutControllerProvider).value!;
      expect(state.draft, isNotNull);
      expect(state.draft!.endedAt, isNull);
      expect(state.draft!.exercises, isEmpty);
      expect(state.draft!.userId, testUserId);
    });

    test('從模板開始:exercises/sets 依 AppliedTemplate 展開,一次性寫入', () async {
      final harness = await _setUpHarness();
      final exercise = await _firstSystemExercise(harness.db);
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);

      final applied = AppliedTemplate(
        templateId: 'template-1',
        templateName: '測試模板',
        exercises: [
          AppliedTemplateExercise(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            sets: const [
              AppliedTemplateSet(weight: 0, reps: 10),
              AppliedTemplateSet(weight: 0, reps: 10),
              AppliedTemplateSet(weight: 0, reps: 10),
            ],
          ),
        ],
      );

      await notifier.startFromTemplate(applied);

      final state = harness.container.read(workoutControllerProvider).value!;
      expect(state.draft, isNotNull);
      expect(state.draft!.templateId, 'template-1');
      expect(state.draft!.exercises, hasLength(1));
      expect(state.draft!.exercises.single.exerciseId, exercise.id);
      expect(state.draft!.exercises.single.sets, hasLength(3));
      expect(state.draft!.exercises.single.sets.map((s) => s.setNumber).toList(), [1, 2, 3]);
      expect(state.draft!.exercises.single.sets.every((s) => s.weight == 0 && s.reps == 10), isTrue);
    });

    // 雙向變異(草稿唯一性):把 startFreeWorkout/startFromTemplate 開頭的
    // `if (state.value?.draft != null) return;` 拿掉,下面兩則測試都會紅
    // (countWorkouts 從 1 變 2)。
    test('已有草稿時再呼叫開始自由訓練 → 不建第二筆(controller 層守)', () async {
      final harness = await _setUpHarness();
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      final repo = WorkoutRepository(harness.db, ExerciseRepository(harness.db));

      await notifier.startFreeWorkout();
      final firstDraftId = harness.container.read(workoutControllerProvider).value!.draft!.id;
      await notifier.startFreeWorkout();

      final rows = await (harness.db.select(harness.db.workouts)).get();
      expect(rows, hasLength(1));
      expect(harness.container.read(workoutControllerProvider).value!.draft!.id, firstDraftId);
      expect(await repo.fetchDraft(testUserId), isNotNull);
    });

    test('開始訓練連點兩下(不 await 第一次就觸發第二次)→ 只建一筆草稿', () async {
      final harness = await _setUpHarness();
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);

      await Future.wait([notifier.startFreeWorkout(), notifier.startFreeWorkout()]);

      final rows = await (harness.db.select(harness.db.workouts)).get();
      expect(rows, hasLength(1));
    });

    // M2:兩條孤兒路徑(錯誤重試 ref.invalidate 後、換帳號往返後)的共同根因
    // 是「state 回到 idle,但 DB 裡的草稿列沒有消失」——`ref.invalidate` 讓
    // `build()` 重跑正是這個根因最直接的重現手法:新的 controller instance
    // 記憶體裡沒有任何草稿,若 startFreeWorkout/startFromTemplate 只信任
    // 記憶體狀態就會誤建第二筆。
    //
    // 雙向變異:把 startFreeWorkout 開頭新增的
    // `final existingDraft = await repo.fetchDraft(userId); if (existingDraft
    // != null) { ...; return; }` 拿掉,這則測試會紅(DB 草稿列從 1 筆變 2 筆)。
    test('startFreeWorkout:state 因 invalidate 重跑回 idle 後,DB 已有草稿 → 接手既有草稿,不建第二筆',
        () async {
      final harness = await _setUpHarness();
      await harness.container.read(workoutControllerProvider.future);
      final firstNotifier = harness.container.read(workoutControllerProvider.notifier);
      await firstNotifier.startFreeWorkout();
      final firstDraftId = harness.container.read(workoutControllerProvider).value!.draft!.id;

      // 模擬「build() 重跑回 idle,但 DB 草稿沒有消失」的孤兒情境(錯誤重試
      // ref.invalidate/換帳號往返共同的根因)。
      harness.container.invalidate(workoutControllerProvider);
      await harness.container.read(workoutControllerProvider.future);
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);

      final freshNotifier = harness.container.read(workoutControllerProvider.notifier);
      await freshNotifier.startFreeWorkout();

      final rows = await (harness.db.select(harness.db.workouts)).get();
      expect(rows, hasLength(1));
      expect(harness.container.read(workoutControllerProvider).value!.draft!.id, firstDraftId);
    });

    // 雙向變異同上:把 startFromTemplate 開頭新增的既有草稿查詢/接手邏輯
    // 拿掉,這則測試會紅(DB 草稿列從 1 筆變 2 筆,且接手的內容會是模板展開
    // 出來的新動作,不是原本自由訓練的空草稿)。
    test('startFromTemplate:state 因 invalidate 重跑回 idle 後,DB 已有草稿 → 接手既有草稿,不套用模板',
        () async {
      final harness = await _setUpHarness();
      final exercise = await _firstSystemExercise(harness.db);
      await harness.container.read(workoutControllerProvider.future);
      final firstNotifier = harness.container.read(workoutControllerProvider.notifier);
      await firstNotifier.startFreeWorkout();
      final firstDraftId = harness.container.read(workoutControllerProvider).value!.draft!.id;

      harness.container.invalidate(workoutControllerProvider);
      await harness.container.read(workoutControllerProvider.future);

      final freshNotifier = harness.container.read(workoutControllerProvider.notifier);
      final applied = AppliedTemplate(
        templateId: 'template-orphan',
        templateName: '孤兒草稿測試模板',
        exercises: [
          AppliedTemplateExercise(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            sets: const [AppliedTemplateSet(weight: 0, reps: 10)],
          ),
        ],
      );
      await freshNotifier.startFromTemplate(applied);

      final rows = await (harness.db.select(harness.db.workouts)).get();
      expect(rows, hasLength(1));
      final state = harness.container.read(workoutControllerProvider).value!;
      expect(state.draft!.id, firstDraftId);
      expect(state.draft!.templateId, isNull); // 接手的是原本的自由訓練草稿,不是模板套用結果
      expect(state.draft!.exercises, isEmpty);
    });
  });

  group('進行中操作(草稿寫穿即時落地,獨立 SELECT 驗證)', () {
    late _Harness harness;
    late Exercise exercise;

    setUp(() async {
      harness = await _setUpHarness();
      exercise = await _firstSystemExercise(harness.db);
      await harness.container.read(workoutControllerProvider.future);
      await harness.container.read(workoutControllerProvider.notifier).startFreeWorkout();
    });

    test('addExercise:新增動作即時落地', () async {
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await notifier.addExercise(exercise);

      final state = harness.container.read(workoutControllerProvider).value!;
      expect(state.draft!.exercises, hasLength(1));
      final row = await (harness.db.select(harness.db.workoutExercises)
            ..where((t) => t.exerciseId.equals(exercise.id)))
          .getSingle();
      expect(row.workoutId, state.draft!.id);
    });

    test('addSet:setNumber 依現有組數自動遞增', () async {
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await notifier.addExercise(exercise);
      final exerciseId = harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;

      await notifier.addSet(workoutExerciseId: exerciseId, weight: 40, reps: 10);
      await notifier.addSet(workoutExerciseId: exerciseId, weight: 45, reps: 8);

      final state = harness.container.read(workoutControllerProvider).value!;
      final sets = state.draft!.exercises.single.sets;
      expect(sets.map((s) => s.setNumber).toList(), [1, 2]);
      expect(sets[1].weight, 45);

      final rows = await (harness.db.select(harness.db.workoutSets)
            ..where((t) => t.workoutExerciseId.equals(exerciseId)))
          .get();
      expect(rows, hasLength(2));
    });

    test('updateSet:更新內容獨立 SELECT 驗證', () async {
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await notifier.addExercise(exercise);
      final exerciseId = harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;
      await notifier.addSet(workoutExerciseId: exerciseId, weight: 40, reps: 10);
      final set = harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.sets.single;

      await notifier.updateSet(set.copyWith(weight: 60, reps: 5, rpe: 9));

      final row = await (harness.db.select(harness.db.workoutSets)..where((t) => t.id.equals(set.id)))
          .getSingle();
      expect(row.weight, 60);
      expect(row.reps, 5);
      expect(row.rpe, 9);
      expect(row.volume, 300);
    });

    test('deleteSet:刪除後剩餘組數重新編號,state 與 DB 一致', () async {
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await notifier.addExercise(exercise);
      final exerciseId = harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;
      await notifier.addSet(workoutExerciseId: exerciseId, weight: 10, reps: 10);
      await notifier.addSet(workoutExerciseId: exerciseId, weight: 20, reps: 8);
      await notifier.addSet(workoutExerciseId: exerciseId, weight: 30, reps: 6);
      final firstSetId =
          harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.sets[0].id;

      await notifier.deleteSet(firstSetId, workoutExerciseId: exerciseId);

      final state = harness.container.read(workoutControllerProvider).value!;
      final sets = state.draft!.exercises.single.sets;
      expect(sets, hasLength(2));
      expect(sets.map((s) => s.setNumber).toList(), [1, 2]);
      expect(sets.map((s) => s.weight).toList(), [20, 30]);
    });

    test('setExerciseCompleted:切換完成狀態', () async {
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await notifier.addExercise(exercise);
      final exerciseId = harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;

      await notifier.setExerciseCompleted(exerciseId, isCompleted: true);
      expect(
        harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.isCompleted,
        isTrue,
      );

      await notifier.setExerciseCompleted(exerciseId, isCompleted: false);
      expect(
        harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.isCompleted,
        isFalse,
      );
    });

    test('removeExercise:連同其下組數一併移除', () async {
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await notifier.addExercise(exercise);
      final exerciseId = harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;
      await notifier.addSet(workoutExerciseId: exerciseId, weight: 10, reps: 10);

      await notifier.removeExercise(exerciseId);

      expect(harness.container.read(workoutControllerProvider).value!.draft!.exercises, isEmpty);
      final remainingSets = await (harness.db.select(harness.db.workoutSets)
            ..where((t) => t.workoutExerciseId.equals(exerciseId)))
          .get();
      expect(remainingSets, isEmpty);
    });
  });

  group('矩陣:完成/放棄的重複與互斥', () {
    late _Harness harness;
    late Exercise exercise;
    late String workoutExerciseId;

    setUp(() async {
      harness = await _setUpHarness();
      exercise = await _firstSystemExercise(harness.db);
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await notifier.startFreeWorkout();
      await notifier.addExercise(exercise);
      workoutExerciseId = harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;
      await notifier.addSet(workoutExerciseId: workoutExerciseId, weight: 50, reps: 10);
      await notifier.setExerciseCompleted(workoutExerciseId, isCompleted: true);
    });

    // 雙向變異(完成冪等):把 completeWorkout() 開頭的
    // `if (draft == null) return const WorkoutCompletionNoOp();` 拿掉,這則
    // 測試會炸(第二次呼叫在 draft 已經是 null 時會撞
    // `WorkoutRepository.completeWorkout` 的 StateError:Workout not found)。
    test('完成訓練連點/完成後再完成 → 冪等,不重複結算、不重複 PR', () async {
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      final prRepo = PersonalRecordRepository(harness.db, ExerciseRepository(harness.db));

      final firstOutcome = await notifier.completeWorkout();
      expect(firstOutcome, isA<WorkoutCompleted>());
      final workoutId = (firstOutcome as WorkoutCompleted).workout.id;
      expect(firstOutcome.newPersonalRecordCount, 1);

      final secondOutcome = await notifier.completeWorkout();
      expect(secondOutcome, isA<WorkoutCompletionNoOp>());

      expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);
      final prs = await prRepo.fetchByExercise(exercise.id);
      expect(prs, hasLength(1)); // 沒有重複建立 PR

      final workoutRow =
          await (harness.db.select(harness.db.workouts)..where((t) => t.id.equals(workoutId))).getSingle();
      expect(workoutRow.endedAt, isNotNull);
    });

    // 雙向變異(放棄冪等):把 abandonWorkout() 開頭的
    // `if (draft == null) return;` 早退改成用 `draft!` 強制解包繼續往下走,
    // 這則測試會炸——第二次呼叫時 `state.value?.draft` 已經是 null,
    // `draft!.id` 會拋出 Null check operator used on a null value。這則測試
    // 釘住的是外部可觀察契約:不管內部怎麼實作,呼叫兩次都必須安全。
    test('放棄確認後再放棄 → no-op', () async {
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      final repo = WorkoutRepository(harness.db, ExerciseRepository(harness.db));
      final workoutId = harness.container.read(workoutControllerProvider).value!.draft!.id;

      await notifier.abandonWorkout();
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);
      expect(await repo.fetchById(workoutId), isNull);

      await notifier.abandonWorkout(); // 不應拋錯
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);
    });

    // 雙向變異(互斥):把 _synchronized 的序列化改成直接呼叫 action()(不排隊)
    // ,這則測試會紅——放棄會在完成訓練的 DB 寫入還沒完成前搶先跑,
    // workouts 表最終會被 discardDraft 整列刪除,`workoutRow` 這行 getSingle
    // 會找不到列而拋錯(而不是斷言 endedAt 非 null)。
    test('完成與放棄互斥:同時觸發時,放棄序列化排在完成之後,變成安全的 no-op', () async {
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      final workoutId = harness.container.read(workoutControllerProvider).value!.draft!.id;

      // 兩個呼叫都先發動、不 await 任何一個(才是真的「同時觸發」);
      // `_synchronized` 讓 abandon 排到 complete 後面才真正執行。
      final completeFuture = notifier.completeWorkout();
      final abandonFuture = notifier.abandonWorkout();
      final completeOutcome = await completeFuture;
      await abandonFuture;

      expect(completeOutcome, isA<WorkoutCompleted>());
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);

      // 訓練「完成」了,不是被放棄刪除——workout row 仍存在且 endedAt 非
      // null。
      final workoutRow =
          await (harness.db.select(harness.db.workouts)..where((t) => t.id.equals(workoutId))).getSingle();
      expect(workoutRow.endedAt, isNotNull);
    });
  });

  group('草稿寫穿不變式', () {
    test('不變式 1:重啟(同一 DB 開新 ProviderContainer)→ 草稿完整還原', () async {
      final harness = await _setUpHarness();
      final exercise = await _firstSystemExercise(harness.db);
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);

      await notifier.startFreeWorkout();
      final originalStartedAt = harness.container.read(workoutControllerProvider).value!.draft!.startedAt;
      await notifier.addExercise(exercise);
      final exerciseId = harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;
      await notifier.addSet(workoutExerciseId: exerciseId, weight: 42, reps: 7, rpe: 8, isWarmup: true);
      await notifier.addSet(workoutExerciseId: exerciseId, weight: 60, reps: 5);
      final workoutId = harness.container.read(workoutControllerProvider).value!.draft!.id;

      // 模擬「App 重啟」:同一份底層 DB,開全新的 ProviderContainer(全新的
      // WorkoutController instance,沒有任何記憶體狀態延續)。
      final restartContainer = ProviderContainer(
        overrides: [
          sharedPreferencesProvider
              .overrideWithValue(await SharedPreferences.getInstance()),
          appDatabaseProvider.overrideWithValue(harness.db),
        ],
      );
      addTearDown(restartContainer.dispose);
      await restartContainer.read(workoutControllerProvider.future);
      final restartNotifier = restartContainer.read(workoutControllerProvider.notifier);

      // 重啟後一開始是 idle(不自動接手),呼叫 checkForRecoverableDraft 才
      // 找得到草稿。
      expect(restartContainer.read(workoutControllerProvider).value!.draft, isNull);
      final recoverable = await restartNotifier.checkForRecoverableDraft();
      expect(recoverable, isNotNull);
      expect(recoverable!.id, workoutId);

      await restartNotifier.resumeDraft(workoutId);
      final restored = restartContainer.read(workoutControllerProvider).value!.draft!;

      // 逐項比對參照值(手算,不是照抄被測程式):startedAt 一致、1 個動作、
      // 2 組,欄位值逐一核對。
      expect(restored.id, workoutId);
      expect(restored.startedAt, originalStartedAt);
      expect(restored.endedAt, isNull);
      expect(restored.exercises, hasLength(1));
      final restoredExercise = restored.exercises.single;
      expect(restoredExercise.exerciseId, exercise.id);
      expect(restoredExercise.sets, hasLength(2));
      expect(restoredExercise.sets[0].weight, 42);
      expect(restoredExercise.sets[0].reps, 7);
      expect(restoredExercise.sets[0].rpe, 8);
      expect(restoredExercise.sets[0].isWarmup, isTrue);
      expect(restoredExercise.sets[1].weight, 60);
      expect(restoredExercise.sets[1].reps, 5);
      expect(restoredExercise.sets[1].isWarmup, isFalse);
    });

    test('不變式 2:完成後 → endedAt IS NULL 查詢為 0 筆(無草稿殘留)', () async {
      final harness = await _setUpHarness();
      final exercise = await _firstSystemExercise(harness.db);
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      final repo = WorkoutRepository(harness.db, ExerciseRepository(harness.db));

      await notifier.startFreeWorkout();
      await notifier.addExercise(exercise);
      final exerciseId = harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;
      await notifier.addSet(workoutExerciseId: exerciseId, weight: 50, reps: 10);
      await notifier.setExerciseCompleted(exerciseId, isCompleted: true);

      await notifier.completeWorkout();

      expect(await repo.fetchDraft(testUserId), isNull);
    });

    test('不變式 2:放棄後 → endedAt IS NULL 查詢為 0 筆(無草稿殘留)', () async {
      final harness = await _setUpHarness();
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      final repo = WorkoutRepository(harness.db, ExerciseRepository(harness.db));

      await notifier.startFreeWorkout();
      await notifier.abandonWorkout();

      expect(await repo.fetchDraft(testUserId), isNull);
      expect(await repo.fetchAll(), isEmpty);
    });
  });

  group('失敗路徑', () {
    test('沒有進行中草稿時呼叫 addExercise 拋出 StateError', () async {
      final harness = await _setUpHarness();
      final exercise = await _firstSystemExercise(harness.db);
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);

      expect(() => notifier.addExercise(exercise), throwsA(isA<StateError>()));
    });

    // M4:completeWorkout 的 catch 復位邏輯——`WorkoutRepository.completeWorkout`
    // 寫入拋錯時,rethrow 給呼叫端之前必須先把 isCompleting 復位、草稿留在
    // state(不能讓 UI 卡在 loading、也不能讓草稿憑空消失讓使用者無從重試)。
    //
    // 雙向變異:把 completeWorkout() 的 `catch (_) { state = AsyncData(
    // WorkoutFlowState(draft: draft)); rethrow; }` 改成只 `rethrow` 不復位
    // state,這則測試會紅(isCompleting 停在 true、或 draft 維持 completeWorkout
    // 呼叫前一刻設成 isCompleting:true 的那個中間態)。
    test('completeWorkout 失敗路徑:寫入拋錯 → rethrow,isCompleting 復位且草稿還在', () async {
      final harness = await _setUpHarness(
        workoutRepoBuilder: (db) => _ThrowingCompleteWorkoutRepository(db, ExerciseRepository(db)),
      );
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await notifier.startFreeWorkout();
      final draftId = harness.container.read(workoutControllerProvider).value!.draft!.id;

      await expectLater(notifier.completeWorkout(), throwsA(isA<Exception>()));

      final state = harness.container.read(workoutControllerProvider).value!;
      expect(state.isCompleting, isFalse);
      expect(state.draft, isNotNull);
      expect(state.draft!.id, draftId);
    });

    // M4:abandonWorkout 的 catch 復位邏輯,理由同上——`WorkoutRepository.
    // discardDraft` 寫入拋錯時,rethrow 前先復位 isAbandoning、草稿留在
    // state。
    //
    // 雙向變異:把 abandonWorkout() 的 catch 區塊改成只 `rethrow` 不復位
    // state,這則測試會紅(isAbandoning 停在 true)。
    test('abandonWorkout 失敗路徑:寫入拋錯 → rethrow,isAbandoning 復位且草稿還在', () async {
      final harness = await _setUpHarness(
        workoutRepoBuilder: (db) => _ThrowingDiscardDraftRepository(db, ExerciseRepository(db)),
      );
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);
      await notifier.startFreeWorkout();
      final draftId = harness.container.read(workoutControllerProvider).value!.draft!.id;

      await expectLater(notifier.abandonWorkout(), throwsA(isA<Exception>()));

      final state = harness.container.read(workoutControllerProvider).value!;
      expect(state.isAbandoning, isFalse);
      expect(state.draft, isNotNull);
      expect(state.draft!.id, draftId);
    });
  });

  group('PR 判定排除暖身組', () {
    // M6:`_recordPersonalRecords` 的 `if (set.isWarmup) continue;` 若被拿掉,
    // 暖身組(刻意設比正式組更高的重量,1RM 會更高)會被誤判為 PR 來源,
    // 這則測試會紅在兩個地方:newPersonalRecordCount 變成 2、且
    // `oneRepMax`(若只斷言正式組那筆)會因為暖身組先建立、正式組的 1RM
    // 反而不是「新 PR」而不被建立(`isNewPR` 用「比現有最高 1RM 高」判斷)。
    //
    // 雙向變異:把 workout_controller.dart `_recordPersonalRecords` 裡的
    // `if (set.isWarmup) continue;` 拿掉,這則測試會紅。
    test('完成訓練:暖身組(重量刻意高於正式組)不建立 PR,只有正式組建立,數值與 achievedAt 手算核對',
        () async {
      final harness = await _setUpHarness();
      final exercise = await _firstSystemExercise(harness.db);
      final prRepo = PersonalRecordRepository(harness.db, ExerciseRepository(harness.db));
      await harness.container.read(workoutControllerProvider.future);
      final notifier = harness.container.read(workoutControllerProvider.notifier);

      await notifier.startFreeWorkout();
      final startedAt = harness.container.read(workoutControllerProvider).value!.draft!.startedAt;
      await notifier.addExercise(exercise);
      final workoutExerciseId =
          harness.container.read(workoutControllerProvider).value!.draft!.exercises.single.id;

      // 暖身組:100kg x 5 下,1RM(Epley)= 100 * (1 + 5/30) = 116.666...7
      await notifier.addSet(
          workoutExerciseId: workoutExerciseId, weight: 100, reps: 5, isWarmup: true);
      // 正式組:60kg x 8 下,1RM(Epley)= 60 * (1 + 8/30) = 76
      await notifier.addSet(workoutExerciseId: workoutExerciseId, weight: 60, reps: 8);
      await notifier.setExerciseCompleted(workoutExerciseId, isCompleted: true);

      final outcome = await notifier.completeWorkout();

      expect(outcome, isA<WorkoutCompleted>());
      expect((outcome as WorkoutCompleted).newPersonalRecordCount, 1);

      final prs = await prRepo.fetchByExercise(exercise.id);
      expect(prs, hasLength(1));
      // 手算 Epley:60 * (1 + 8/30) = 76,不是照抄被測程式碼算出來的。
      expect(prs.single.oneRepMax, closeTo(76.0, 0.0001));
      expect(prs.single.weight, 60);
      expect(prs.single.reps, 8);
      expect(prs.single.achievedAt, startedAt);
    });
  });
}
