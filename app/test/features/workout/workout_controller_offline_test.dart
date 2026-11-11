// WorkoutController × OfflineDraftWorkoutRepository(雲端模式的離線草稿):
// 經 controller 跑完整訓練流程時零雲端呼叫;完成時離線失敗可重試;上傳成功但
// 記 PR 失敗 → 重按完成會判定已上傳、補記 PR,且不重複建立訓練。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, Exercise, PersonalRecord;
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/personal_record.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/offline/offline_draft_workout_repository.dart';
import 'package:workout_record/data/repositories/personal_record_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/workout_controller.dart';

import '../../data/offline/fake_cloud_workout_repository.dart';
import '../../data/test_helpers.dart';

/// 記 PR 的假雲端:前 [failuresLeft] 次 createIfNewPR 模擬離線失敗。
class _FakeCloudPRs implements PersonalRecordRepository {
  int failuresLeft = 0;
  final List<PersonalRecord> created = [];

  @override
  Future<PersonalRecord?> createIfNewPR(PersonalRecord candidate) async {
    if (failuresLeft > 0) {
      failuresLeft -= 1;
      throw const FakeOfflineException();
    }
    created.add(candidate);
    return candidate;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

typedef _Harness = ({
  AppDatabase db,
  ProviderContainer container,
  SharedPreferences prefs,
  FakeCloudWorkoutRepository cloud,
  _FakeCloudPRs prs,
});

Future<_Harness> _setUp() async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);
  final cloud = FakeCloudWorkoutRepository()..offline = true;
  final prs = _FakeCloudPRs();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      workoutRepositoryProvider.overrideWithValue(
        OfflineDraftWorkoutRepository(cloud, prefs),
      ),
      personalRecordRepositoryProvider.overrideWithValue(prs),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (db: db, container: container, prefs: prefs, cloud: cloud, prs: prs);
}

Future<Exercise> _firstSystemExercise(AppDatabase db) async =>
    (await DriftExerciseRepository(db).fetchSystemExercises()).first;

/// 開始→加動作→加兩組(一組暖身)→改組→加一組再刪掉,全經 controller。
/// (原本最後還有「標記動作完成」;該方法隨裁示 3 刪除,完成改由有組推導。)
Future<WorkoutController> _recordWorkout(_Harness h) async {
  await h.container.read(workoutControllerProvider.future);
  final notifier = h.container.read(workoutControllerProvider.notifier);
  await notifier.startFreeWorkout();
  await notifier.addExercise(await _firstSystemExercise(h.db));
  final weId = h.container
      .read(workoutControllerProvider)
      .value!
      .draft!
      .exercises
      .single
      .id;
  await notifier.addSet(
    workoutExerciseId: weId,
    weight: 20,
    reps: 10,
    isWarmup: true,
  );
  await notifier.addSet(workoutExerciseId: weId, weight: 60, reps: 8);
  await notifier.addSet(workoutExerciseId: weId, weight: 99, reps: 1);
  var sets = h.container
      .read(workoutControllerProvider)
      .value!
      .draft!
      .exercises
      .single
      .sets;
  await notifier.updateSet(sets[1].copyWith(weight: 62.5));
  await notifier.deleteSet(sets[2].id, workoutExerciseId: weId);
  return notifier;
}

void main() {
  test('經 controller 開始→加動作→加/改/刪組:零雲端呼叫,state 即本機草稿', () async {
    final h = await _setUp();
    await _recordWorkout(h);

    final draft = h.container.read(workoutControllerProvider).value!.draft!;
    expect(h.cloud.calls, isEmpty);
    final sets = draft.exercises.single.sets;
    expect(sets.map((s) => (s.setNumber, s.weight, s.isWarmup)), [
      (1, 20.0, true),
      (2, 62.5, false),
    ]);
    // 現行行為:controller 不寫 isCompleted(完成由有組推導,裁示 3)。
    expect(draft.exercises.single.isCompleted, isFalse);
  });

  test('離線放棄:零雲端呼叫,草稿清掉', () async {
    final h = await _setUp();
    final notifier = await _recordWorkout(h);
    await notifier.abandonWorkout();
    expect(h.cloud.calls, isEmpty);
    expect(h.container.read(workoutControllerProvider).value!.draft, isNull);
    expect(await notifier.checkForRecoverableDraft(), isNull);
  });

  test(
    '重啟(新 container)後 checkForRecoverableDraft + resumeDraft 離線接回草稿',
    () async {
      final h = await _setUp();
      await _recordWorkout(h);
      final before = h.container.read(workoutControllerProvider).value!.draft!;

      final restarted = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(h.prefs),
          appDatabaseProvider.overrideWithValue(h.db),
          workoutRepositoryProvider.overrideWithValue(
            OfflineDraftWorkoutRepository(h.cloud, h.prefs),
          ),
          personalRecordRepositoryProvider.overrideWithValue(h.prs),
        ],
      );
      addTearDown(restarted.dispose);
      await restarted.read(workoutControllerProvider.future);
      final notifier = restarted.read(workoutControllerProvider.notifier);
      final recoverable = await notifier.checkForRecoverableDraft();
      expect(recoverable!.id, before.id);
      await notifier.resumeDraft(recoverable.id);

      final resumed = restarted.read(workoutControllerProvider).value!.draft!;
      expect(
        resumed.exercises.single.sets.length,
        before.exercises.single.sets.length,
      );
      expect(h.cloud.calls, isEmpty);
    },
  );

  test('離線按完成 → 拋錯、草稿留在 state;恢復網路再按 → 上傳一次並記 PR', () async {
    final h = await _setUp();
    final notifier = await _recordWorkout(h);

    await expectLater(
      notifier.completeWorkout(),
      throwsA(isA<FakeOfflineException>()),
    );
    final afterFail = h.container.read(workoutControllerProvider).value!;
    expect(afterFail.draft, isNotNull);
    expect(afterFail.isCompleting, isFalse);
    expect(h.cloud.insertCount, 0);

    h.cloud.offline = false;
    final outcome = await notifier.completeWorkout();

    expect(outcome, isA<WorkoutCompleted>());
    final completed = (outcome as WorkoutCompleted).workout;
    expect(completed.totalVolume, 62.5 * 8);
    expect(completed.totalSets, 1);
    expect(h.cloud.insertCount, 1);
    expect(h.prs.created, hasLength(1)); // 只有非暖身那組
    expect(h.container.read(workoutControllerProvider).value!.draft, isNull);
  });

  test('上傳成功但記 PR 失敗 → 草稿留在 state;重按完成判定已上傳、補記 PR,不重複建立', () async {
    final h = await _setUp();
    final notifier = await _recordWorkout(h);
    h.cloud.offline = false;
    h.prs.failuresLeft = 1;

    await expectLater(
      notifier.completeWorkout(),
      throwsA(isA<FakeOfflineException>()),
    );
    expect(h.cloud.insertCount, 1);
    expect(h.prs.created, isEmpty);
    final draftId = h.container
        .read(workoutControllerProvider)
        .value!
        .draft!
        .id;
    // 雲端已收下、讀回的是已完成的訓練;state.draft 仍必須是進行中草稿
    // (endedAt == null),不能把已完成的那筆放進來(flow-fix 3)。
    final keptDraft = h.container.read(workoutControllerProvider).value!.draft!;
    expect(keptDraft.endedAt, isNull);
    expect(keptDraft.exercises.single.sets, hasLength(2));

    final outcome = await notifier.completeWorkout();

    expect(outcome, isA<WorkoutCompleted>());
    expect((outcome as WorkoutCompleted).workout.id, draftId);
    expect(outcome.newPersonalRecordCount, 1);
    expect(h.cloud.insertCount, 1);
    expect(h.cloud.calls.where((c) => c == 'create'), hasLength(1));
    expect(h.cloud.calls.last, 'completeWorkout');
    expect(h.prs.created.single.workoutId, draftId);
    expect(h.container.read(workoutControllerProvider).value!.draft, isNull);
  });
}
