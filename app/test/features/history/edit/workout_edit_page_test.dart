// WorkoutEditPage widget seam:pump 真實頁面(repositories/provider 一律用真的,
// 只換 appDatabaseProvider 為 in-memory DB、sharedPreferencesProvider 為 mock
// prefs,對照 dashboard_page_test.dart harness 慣例)。涵蓋 brief 驗收標準 5
// (真組裝路徑編輯流)、6(失敗路徑)、以及規格細節 5 的邊界行為(最後一個
// 動作可以刪)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet;
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/history/edit/workout_edit_page.dart';

import '../../../data/test_helpers.dart';

/// Drift 的 dateTime() 欄位是整數秒精度,種 fixture 一律先截斷到秒,避免跟
/// DB 往返後的值比較時 flaky(dashboard_page_test.dart harness 註解提過的
/// 雷)。
DateTime _secondPrecisionNow() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, now.hour, now.minute, now.second);
}

/// 失敗路徑測試專用:只覆寫 `updateSet`,模擬寫入失敗(例如磁碟已滿),其餘
/// 方法沿用真實實作(對照 dashboard_page_test.dart `_ThrowingBodyWeightRepository`)。
class _ThrowingUpdateSetWorkoutRepository extends WorkoutRepository {
  _ThrowingUpdateSetWorkoutRepository(super.db, super.exerciseRepository);

  @override
  Future<void> updateSet(WorkoutSet set) async {
    throw Exception('模擬更新組數失敗(失敗路徑測試用)');
  }
}

class _EditHarness {
  _EditHarness(this.db, this.container)
      : workoutRepo = WorkoutRepository(db, ExerciseRepository(db)),
        exerciseRepo = ExerciseRepository(db);

  final AppDatabase db;
  final ProviderContainer container;

  /// 種 fixture / 事後查 DB 一律用這個「真的」repository,不管容器裡實際
  /// 注入的是不是被覆寫過的版本(對照 dashboard harness 慣例)。
  final WorkoutRepository workoutRepo;
  final ExerciseRepository exerciseRepo;
}

Future<_EditHarness> _setUpHarness({
  WorkoutRepository Function(AppDatabase db)? workoutRepoBuilder,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (workoutRepoBuilder != null)
        workoutRepositoryProvider.overrideWithValue(workoutRepoBuilder(db)),
    ],
  );
  addTearDown(container.dispose);
  return _EditHarness(db, container);
}

Future<void> _pumpEditPage(WidgetTester tester, _EditHarness harness, String workoutId) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(home: WorkoutEditPage(workoutId: workoutId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  /// 種一筆已完成的訓練:一個動作、一組。回傳 (workoutExerciseId, setId)
  /// 供測試按 key 操作。
  Future<(String, String)> seedSingleSetWorkout(
    _EditHarness harness, {
    required String workoutId,
    required String exerciseId,
    double weight = 50,
    int reps = 5,
    String? note,
  }) async {
    final now = _secondPrecisionNow();
    const workoutExerciseId = 'we-1';
    const setId = 'set-1';
    await harness.workoutRepo.create(Workout(
      id: workoutId,
      userId: testUserId,
      startedAt: now.subtract(const Duration(hours: 1)),
      endedAt: now,
      duration: 60,
      note: note,
      // 種下「已經算好」的 summary(對照真實已完成訓練一律已經跑過
      // completeWorkout,summary 欄位與目前 sets 是一致的)——不是留預設值
      // 0,失敗路徑測試才有意義(拋錯時「沒被寫壞」跟「本來就是 0」是兩件
      // 不一樣的事,種一個非零的正確初值,才能真的驗證失敗時沒被覆寫)。
      totalVolume: weight * reps,
      totalSets: 1,
      totalExercises: 1,
      createdAt: now,
      updatedAt: now,
      exercises: [
        WorkoutExercise(
          id: workoutExerciseId,
          workoutId: workoutId,
          exerciseId: exerciseId,
          exerciseName: 'Fixture 動作',
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
    return (workoutExerciseId, setId);
  }

  testWidgets('編輯頁 widget 流:改一組重量 → 存後重讀 DB 斷言 sets 與 summary 齊變', (tester) async {
    final harness = await _setUpHarness();
    // `WorkoutExercises.exerciseId` 有 FK 參照 Exercises(tables.tables.dart),
    // 系統動作的 id 是每個 DB 各自 seed 時隨機產生(`generateUuidV4()`,見
    // seed_data.dart),不是固定值——一律從「這個測試自己的 harness DB」現查,
    // 不能沿用別的 DB 查到的 id(否則 FK 違反,insert 直接失敗)。
    final exerciseId = (await harness.exerciseRepo.fetchSystemExercises()).first.id;
    final (_, setId) = await seedSingleSetWorkout(
      harness,
      workoutId: 'edit-weight',
      exerciseId: exerciseId,
      weight: 50,
      reps: 5,
    );

    await _pumpEditPage(tester, harness, 'edit-weight');

    // 編輯前:總容量 = 50 * 5 = 250。
    expect(
      find.descendant(
        of: find.byKey(const Key('workoutEditTotalVolumeValue')),
        matching: find.text('250 kg'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(Key('workoutEditEditSetButton_$setId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addSetWeightField')), '120');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSetSaveButton')));
    await tester.pumpAndSettle();

    // 畫面同步:總容量變成 120 * 5 = 600。
    expect(
      find.descendant(
        of: find.byKey(const Key('workoutEditTotalVolumeValue')),
        matching: find.text('600 kg'),
      ),
      findsOneWidget,
    );

    // 重讀 DB(不是只信任畫面):sets 與 summary 齊變。
    final fetched = await harness.workoutRepo.fetchById('edit-weight');
    expect(fetched, isNotNull);
    expect(fetched!.exercises.single.sets.single.weight, 120);
    expect(fetched.totalVolume, 600);
    expect(fetched.totalSets, 1);
    expect(fetched.totalExercises, 1);
  });

  // code review Spec-1/2 順手:這裡刻意**不用** dashboard_page_test.dart
  // harness 的 `disableAutoRetry` 慣例——那個慣例是為了關掉 riverpod
  // 對 `build()` 拋錯的自動重試(provider 進入 AsyncError 狀態才會觸發)。
  // 這裡測的是 `WorkoutEditController._mutate` 內某個操作方法拋錯,`_mutate`
  // 的 catch 區一律把 state 收回 `AsyncData`(不管成功或失敗都不會讓
  // provider 落入 AsyncError),riverpod 的自動重試機制根本不會被觸發,
  // 不需要額外關掉它。
  testWidgets('失敗路徑:寫入拋錯 → 解除 loading、浮出錯誤、UI 狀態與 DB 一致(重讀)', (tester) async {
    final harness = await _setUpHarness(
      workoutRepoBuilder: (db) => _ThrowingUpdateSetWorkoutRepository(db, ExerciseRepository(db)),
    );
    final exerciseId = (await harness.exerciseRepo.fetchSystemExercises()).first.id;
    final (_, setId) = await seedSingleSetWorkout(
      harness,
      workoutId: 'edit-fail',
      exerciseId: exerciseId,
      weight: 50,
      reps: 5,
    );

    await _pumpEditPage(tester, harness, 'edit-fail');

    await tester.tap(find.byKey(Key('workoutEditEditSetButton_$setId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addSetWeightField')), '999');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSetSaveButton')));
    await tester.pumpAndSettle();

    // 浮出錯誤。
    expect(find.textContaining('更新組數失敗'), findsOneWidget);
    // loading 已解除:saving 指示器不在畫面上。
    expect(find.byKey(const Key('workoutEditSavingIndicator')), findsNothing);
    // 編輯按鈕沒有卡死在 disabled——可以再次點擊重試。
    final editButton = tester.widget<IconButton>(find.byKey(Key('workoutEditEditSetButton_$setId')));
    expect(editButton.onPressed, isNotNull);
    // UI 狀態與 DB 一致(重讀):畫面上的容量仍是編輯前的 250,不是誤植的
    // 950(=999*... 之類的髒值)。
    expect(
      find.descendant(
        of: find.byKey(const Key('workoutEditTotalVolumeValue')),
        matching: find.text('250 kg'),
      ),
      findsOneWidget,
    );

    final fetched = await harness.workoutRepo.fetchById('edit-fail');
    expect(fetched!.exercises.single.sets.single.weight, 50); // 沒有寫入
    expect(fetched.totalVolume, 250);
  });

  testWidgets('刪除組數:取消不刪,確認才真的刪並更新統計', (tester) async {
    final harness = await _setUpHarness();
    final exerciseId = (await harness.exerciseRepo.fetchSystemExercises()).first.id;
    final now = _secondPrecisionNow();
    await harness.workoutRepo.create(Workout(
      id: 'edit-delete-set',
      userId: testUserId,
      startedAt: now.subtract(const Duration(hours: 1)),
      endedAt: now,
      duration: 60,
      createdAt: now,
      updatedAt: now,
      exercises: [
        WorkoutExercise(
          id: 'we-del-set',
          workoutId: 'edit-delete-set',
          exerciseId: exerciseId,
          exerciseName: 'Fixture 動作',
          createdAt: now,
          updatedAt: now,
          sets: [
            WorkoutSet(
              id: 'set-del-1',
              workoutExerciseId: 'we-del-set',
              setNumber: 1,
              weight: 40,
              reps: 10,
              createdAt: now,
              updatedAt: now,
            ),
            WorkoutSet(
              id: 'set-del-2',
              workoutExerciseId: 'we-del-set',
              setNumber: 2,
              weight: 60,
              reps: 5,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      ],
    ));

    await _pumpEditPage(tester, harness, 'edit-delete-set');

    // 取消:對話框關閉,兩組都還在。
    await tester.tap(find.byKey(const Key('workoutEditDeleteSetButton_set-del-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workoutEditDeleteSetCancelButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('workoutEditDeleteSetCancelButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workoutEditSetRow_set-del-2')), findsOneWidget);

    // 確認:那一組被刪除,統計更新(只剩 40*10=400)。
    await tester.tap(find.byKey(const Key('workoutEditDeleteSetButton_set-del-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workoutEditDeleteSetConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workoutEditSetRow_set-del-2')), findsNothing);
    expect(find.byKey(const Key('workoutEditSetRow_set-del-1')), findsOneWidget);
    final fetched = await harness.workoutRepo.fetchById('edit-delete-set');
    expect(fetched!.exercises.single.sets, hasLength(1));
    expect(fetched.totalVolume, 400);
    expect(fetched.totalSets, 1);
  });

  // 規格細節 5 邊界行為:最後一個動作可以刪——訓練變空殼但仍然存在。
  testWidgets('刪除最後一個動作(邊界):確認後訓練變空殼,仍然存在、不是整筆被刪', (tester) async {
    final harness = await _setUpHarness();
    final exerciseId = (await harness.exerciseRepo.fetchSystemExercises()).first.id;
    await seedSingleSetWorkout(
      harness,
      workoutId: 'edit-last-exercise',
      exerciseId: exerciseId,
    );

    await _pumpEditPage(tester, harness, 'edit-last-exercise');

    expect(find.byKey(const Key('workoutEditExerciseCard_we-1')), findsOneWidget);
    expect(find.byKey(const Key('workoutEditEmptyExercisesHint')), findsNothing);

    await tester.tap(find.byKey(const Key('workoutEditDeleteExerciseButton_we-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workoutEditDeleteExerciseConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workoutEditExerciseCard_we-1')), findsNothing);
    expect(find.byKey(const Key('workoutEditEmptyExercisesHint')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('workoutEditExerciseCountValue')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );

    // 訓練本身仍然存在(不是連 workout 都被刪掉)。
    final fetched = await harness.workoutRepo.fetchById('edit-last-exercise');
    expect(fetched, isNotNull);
    expect(fetched!.exercises, isEmpty);
    expect(fetched.totalExercises, 0);
    expect(fetched.totalVolume, 0);
    expect(fetched.totalSets, 0);
  });

  testWidgets('新增組數:透過記組 sheet 加入一組後,畫面與 DB 都看得到', (tester) async {
    final harness = await _setUpHarness();
    final exerciseId = (await harness.exerciseRepo.fetchSystemExercises()).first.id;
    await seedSingleSetWorkout(
      harness,
      workoutId: 'edit-add-set',
      exerciseId: exerciseId,
      weight: 30,
      reps: 10,
    );

    await _pumpEditPage(tester, harness, 'edit-add-set');

    await tester.tap(find.byKey(const Key('workoutEditAddSetButton_we-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addSetWeightField')), '45');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addSetRepsField')), '8');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSetSaveButton')));
    await tester.pumpAndSettle();

    final fetched = await harness.workoutRepo.fetchById('edit-add-set');
    expect(fetched!.exercises.single.sets, hasLength(2));
    // 300(30*10) + 360(45*8) = 660。
    expect(fetched.totalVolume, 660);
    expect(fetched.totalSets, 2);
  });

  testWidgets('新增動作:透過選動作器(重用波 3 元件)挑一個動作加入', (tester) async {
    final harness = await _setUpHarness();
    // 從空訓練開始(0 動作),用直接建構避免依賴 seedSingleSetWorkout 的
    // 固定形狀。
    final now = _secondPrecisionNow();
    await harness.workoutRepo.create(Workout(
      id: 'edit-add-exercise',
      userId: testUserId,
      startedAt: now.subtract(const Duration(hours: 1)),
      endedAt: now,
      duration: 60,
      createdAt: now,
      updatedAt: now,
    ));

    final pickedExercise = (await harness.exerciseRepo.fetchSystemExercises())[1];

    await _pumpEditPage(tester, harness, 'edit-add-exercise');

    expect(find.byKey(const Key('workoutEditEmptyExercisesHint')), findsOneWidget);

    await tester.tap(find.byKey(const Key('workoutEditAddExerciseButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise_picker_list')), findsOneWidget);

    await tester.tap(find.byKey(Key('exercise_row_${pickedExercise.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workoutEditEmptyExercisesHint')), findsNothing);
    expect(find.text(pickedExercise.name), findsOneWidget);

    final fetched = await harness.workoutRepo.fetchById('edit-add-exercise');
    expect(fetched!.exercises, hasLength(1));
    expect(fetched.exercises.single.exerciseId, pickedExercise.id);
    expect(fetched.totalExercises, 1);
  });

  testWidgets('更新備註:輸入文字後儲存,DB 與畫面同步', (tester) async {
    final harness = await _setUpHarness();
    final exerciseId = (await harness.exerciseRepo.fetchSystemExercises()).first.id;
    await seedSingleSetWorkout(
      harness,
      workoutId: 'edit-note',
      exerciseId: exerciseId,
    );

    await _pumpEditPage(tester, harness, 'edit-note');

    await tester.enterText(find.byKey(const Key('workoutEditNoteField')), '今天狀態不錯');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workoutEditSaveNoteButton')));
    await tester.pumpAndSettle();

    expect(find.text('備註已更新'), findsOneWidget);
    final fetched = await harness.workoutRepo.fetchById('edit-note');
    expect(fetched!.note, '今天狀態不錯');
  });
}
