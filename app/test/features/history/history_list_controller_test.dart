// HistoryListController seam:直接透過 ProviderContainer 呼叫 controller
// 方法(不經 widget 樹),用來精準控制非同步時序——對照
// test/features/workout/exercise_picker/exercise_picker_controller_test.dart
// 開頭注解的理由:widget test 的 tap+pumpAndSettle 沒辦法可靠模擬「provider
// 還沒載入完成就被呼叫」這種時間點,只有直接控制 gate 才做得到。
//
// code review 打回 MAJOR-1:history_list_controller.dart:79-81(修復前)
// `if (current == null) return;`——列表 state 尚未載入完成(`AsyncLoading`)
// 或上一次載入失敗(`AsyncError`)時 `state.value` 是 null,`deleteWorkout`
// 會靜默 no-op、不呼叫 repository、也不拋錯,呼叫端(詳情頁)收到「成功」的
// Future 照樣 pop——使用者以為刪了、資料其實還在 DB 裡。觸發路徑:列表
// controller 還沒載完/上次載入失敗時,使用者從日曆檢視進詳情頁刪除(日曆
// 檢視是獨立的 `historyCalendarControllerProvider`,不吃列表 controller 的
// 載入狀態)。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/history/history_list_controller.dart';

import '../../data/test_helpers.dart';

Workout _buildWorkout({required String id, required DateTime startedAt}) {
  final now = DateTime.now();
  return Workout(
    id: id,
    userId: testUserId,
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 30)),
    duration: 30,
    totalVolume: 100,
    totalSets: 5,
    totalExercises: 1,
    createdAt: now,
    updatedAt: now,
  );
}

/// `fetchAll()` 可用外部 [Completer] 控制何時回傳(用來讓
/// `HistoryListController.build()` 卡在 `AsyncLoading`,`state.value` 保持
/// null),`delete()`/`fetchByDateRange()` 等其他方法完全沿用真實實作,不
/// 受影響——這樣才能驗證「state 還沒載入完成時呼叫 deleteWorkout,delete
/// 本身仍然真的執行」。
class _GatedFetchAllWorkoutRepository extends WorkoutRepository {
  _GatedFetchAllWorkoutRepository(super.db, super.exerciseRepository);

  Completer<void>? fetchAllGate;

  @override
  Future<List<Workout>> fetchAll() async {
    final gate = fetchAllGate;
    if (gate != null) await gate.future;
    return super.fetchAll();
  }
}

void main() {
  group('deleteWorkout — MAJOR-1 修復:state 尚未載入完成時仍要真的刪除', () {
    test(
      'build() 卡在 AsyncLoading(state.value 為 null)時呼叫 deleteWorkout → DB 真的少一筆,不是靜默 no-op',
      () async {
        SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
        final prefs = await SharedPreferences.getInstance();
        final db = openTestDatabase();
        addTearDown(db.close);
        await seedTestUser(db);

        final gatedRepo = _GatedFetchAllWorkoutRepository(db, ExerciseRepository(db));
        final realRepo = WorkoutRepository(db, ExerciseRepository(db));
        await realRepo.create(_buildWorkout(id: 'w-not-loaded-yet', startedAt: DateTime.now()));

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            workoutRepositoryProvider.overrideWithValue(gatedRepo),
          ],
        );
        addTearDown(container.dispose);

        // build() 一啟動就卡在 fetchAll() 的 gate 上,state 停在 AsyncLoading。
        final gate = Completer<void>();
        gatedRepo.fetchAllGate = gate;
        final notifier = container.read(historyListControllerProvider.notifier);

        // 確認前提成立:state 真的還沒載入完成,`.value` 是 null——不是這條
        // 測試自己臆測的情境,是實際觀察到的狀態。
        expect(container.read(historyListControllerProvider).value, isNull);
        expect(container.read(historyListControllerProvider).isLoading, isTrue);

        // 在 state 仍是 null 的當下呼叫 deleteWorkout。放開 gate 讓
        // deleteWorkout 內部成功後的 `_load()` 重新查詢(同一個 gate)能繼續
        // 往下跑,不然這個 await 會永遠卡住(不是這條測試要驗的東西)。
        final deleteFuture = notifier.deleteWorkout('w-not-loaded-yet');
        gate.complete();
        await deleteFuture;

        // 拔掉修復(還原 `if (current == null) return;` 早退)必紅的斷言:
        // repository 的 delete 真的被呼叫、DB 真的少一筆。
        final stillThere = await realRepo.fetchById('w-not-loaded-yet');
        expect(stillThere, isNull);
      },
    );
  });
}
