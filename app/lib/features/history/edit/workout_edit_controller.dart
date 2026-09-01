// 編輯已完成訓練的狀態機(波 5)。對照波 3 `workout_controller.dart` 的草稿
// 寫穿慣例,但操作對象是「已完成」的訓練,不是進行中草稿——沒有取消/還原
// 概念,每個編輯操作直接寫穿 DB(Mike 預授權裁定,見 brief「波 5 編輯已
// 完成訓練」規格細節 2:離開頁面即是最新狀態)。
//
// **單一事實來源是 DB**:每個變動方法寫入後一律重新 `fetchById` 整包
// workout 寫回 [state],不維護一份可能失準的鏡像狀態,做法對齊
// workout_controller.dart 檔案開頭的說明。
//
// **每次變更後依序跑 recomputeSummary + PR 結算**(不是離開頁面才跑收尾)
// ——使用者殺 app 也要能維持 summary/PR 與目前資料一致,見
// [WorkoutEditController._mutate]。
//
// **序列化寫入**:沿用 workout_controller.dart 的 `_synchronized` 手法,
// 保證同一個 controller instance 上的操作依呼叫順序嚴格序列化,不會並發
// 交錯(例如連點刪除兩次同一組)。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/uuid.dart';
import '../../../data/models/exercise.dart';
import '../../../data/models/personal_record.dart';
import '../../../data/models/workout.dart';
import '../../../data/providers.dart';
import '../../workout/one_rm_calculator.dart';
import '../../workout/workout_ui_shared.dart';

/// 編輯已完成訓練的畫面狀態。[isSaving] 為 true 時代表有一筆寫入正在進行
/// 中——UI 用來 disable 編輯控制項,避免使用者在寫入期間疊加下一個操作
/// (對照 workout_controller.dart `isCompleting`/`isAbandoning` 的用途)。
class WorkoutEditState {
  const WorkoutEditState({required this.workout, this.isSaving = false});

  final Workout workout;
  final bool isSaving;

  WorkoutEditState copyWith({Workout? workout, bool? isSaving}) {
    return WorkoutEditState(
      workout: workout ?? this.workout,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

class WorkoutEditController extends AsyncNotifier<WorkoutEditState> {
  WorkoutEditController(this.workoutId);

  /// family 參數:要編輯的訓練 id(由呼叫端在 `Navigator.push` 時帶入,見
  /// `workout_edit_page.dart` `WorkoutEditPage` 建構子)。
  final String workoutId;

  Future<void> _lock = Future.value();

  /// 序列化執行,做法照抄 workout_controller.dart `_synchronized` 文件——
  /// 用 [Completer] 標記「這個操作做完了」,不讓單一操作失敗就讓 `_lock`
  /// 這條鏈本身進入 completed-with-error 狀態。
  Future<T> _synchronized<T>(Future<T> Function() action) {
    final previousTurn = _lock;
    final doneWithThisTurn = Completer<void>();
    _lock = doneWithThisTurn.future;
    return previousTurn.then((_) async {
      try {
        return await action();
      } finally {
        doneWithThisTurn.complete();
      }
    });
  }

  @override
  Future<WorkoutEditState> build() async {
    final workout = await ref.read(workoutRepositoryProvider).fetchById(workoutId);
    if (workout == null) {
      throw StateError('WorkoutEditController: 找不到訓練 $workoutId');
    }
    // 前置守衛(code review Std-2):這個頁面只服務「已完成」的訓練——若
    // 呼叫端不慎帶了一筆草稿(`endedAt IS NULL`)的 id 進來,提前在這裡就
    // 拋錯,讓 `WorkoutEditPage` 直接落在 error 分支(進頁面就看得到「載入
    // 失敗」)。沒有這道守衛的話,頁面會先正常渲染成功、直到使用者第一次
    // 編輯操作觸發 `recomputeSummary` 的草稿守衛才半路拋錯——同一個錯誤,
    // 越晚爆出來使用者越困惑(以為是這次編輯把訓練弄壞的)。
    if (workout.endedAt == null) {
      throw StateError(
        'WorkoutEditController: workout $workoutId 還是進行中的草稿'
        '(endedAt IS NULL),編輯頁只服務已完成的訓練',
      );
    }
    return WorkoutEditState(workout: workout);
  }

  /// 所有變動方法的共用外殼:先把 [WorkoutEditState.isSaving] 打開,執行
  /// [action](拿到目前 state 裡的 workout 當參數,呼叫端不需要另外
  /// `state.value` 取一次),成功時依序 `recomputeSummary` + PR 結算再重讀
  /// 整包 workout 寫回 state;失敗時**一律重讀 DB** 讓 UI 狀態與 DB 一致
  /// (不假設「拋錯 == 完全沒寫入」),`isSaving` 解除,並把原始例外原樣
  /// rethrow 給呼叫端(UI 層 catch 後浮 SnackBar,對照
  /// workout_in_progress_view.dart 每個操作方法的 try/catch 慣例)。
  ///
  /// **transaction 窗口取捨**(code review Std-1):[action]、
  /// `recomputeSummary`、PR 結算(`_checkPersonalRecords` 對每個動作各自
  /// 呼叫一次 `createIfNewPR`)是三個(或更多)各自獨立的 DB 寫入,**不是
  /// 包在同一個橫跨 repository 的大 transaction 裡**——`action` 用的是
  /// `WorkoutRepository` 那些既有方法各自的 transaction/單一 UPDATE,
  /// `recomputeSummary` 是它自己的 transaction,PR 結算又是
  /// `PersonalRecordRepository` 另外的寫入。代價:如果 app 在這幾步之間
  /// 崩潰(例如 `action` 成功寫入但還沒跑到 `recomputeSummary`),DB 會短暫
  /// 停在「sets 已經是新值、summary 還是舊值」的中間態。接受這個代價是
  /// 刻意的取捨:(1)這個中間態是**自癒**的——下一次任何編輯操作呼叫
  /// `_mutate` 都會重新跑一次 `recomputeSummary`,不需要額外的復原機制;
  /// (2)要把三個 repository 的寫入包進同一個 transaction,得打破
  /// `WorkoutRepository`/`PersonalRecordRepository` 各自管理自己
  /// transaction 邊界的封裝(它們都是各自 `_db.transaction` 包好的公開
  /// 方法,不是暴露內部 statement 讓呼叫端自己組 transaction),不值得為了
  /// 這個極窄的崩潰窗口去打開這道封裝。
  Future<void> _mutate(Future<void> Function(Workout current) action) => _synchronized(() async {
        final current = state.value;
        if (current == null) {
          throw StateError('WorkoutEditController: 尚未載入完成,無法編輯');
        }
        state = AsyncData(current.copyWith(isSaving: true));
        final repo = ref.read(workoutRepositoryProvider);
        try {
          await action(current.workout);
          await repo.recomputeSummary(workoutId);
          final refreshed = await repo.fetchById(workoutId);
          if (refreshed == null) {
            throw StateError('WorkoutEditController: workout 在寫入後消失:$workoutId');
          }
          await _checkPersonalRecords(refreshed);
          state = AsyncData(WorkoutEditState(workout: refreshed));
        } catch (e) {
          // code review Std-3:重讀本身也可能失敗(例如同一段時間 DB 被鎖、
          // IO 錯誤)——包一層 try/catch,重讀失敗時保留寫入前的
          // `current.workout`,而不是讓這裡新拋出的例外蓋掉外層要 rethrow
          // 的原始例外 `e`(呼叫端 catch 到的錯誤文案應該講「原本那個操作
          // 為什麼失敗」,不是「重讀 DB 為什麼也失敗」這個次要症狀)。
          Workout? refreshed;
          try {
            refreshed = await repo.fetchById(workoutId);
          } catch (_) {
            // 吞掉重讀失敗本身,不覆寫下面的 rethrow。
          }
          state = AsyncData(WorkoutEditState(workout: refreshed ?? current.workout));
          rethrow;
        }
      });

  /// PR 結算(只升不降):逐一檢查訓練裡每個動作,用「該動作目前非暖身組
  /// 裡 1RM 最高的那一組」構造一次候選,走
  /// `PersonalRecordRepository.createIfNewPR`(只在更高時才寫入,天然
  /// 冪等,見該方法文件)。
  ///
  /// **與 workout_controller.dart `_recordPersonalRecords` 刻意口徑不同**
  /// (brief 規格,先讀過那段完成流程再抄):那裡逐一檢查「每一組」——訓練
  /// 只會完成一次,循序檢查每組能捕捉到「同一次訓練裡後面的組別打破前面
  /// 組別剛建立的 PR」這種情境。這裡的呼叫時機是「每次編輯」,同一筆
  /// 訓練的同一組資料會被反覆檢查很多次,若照抄逐組檢查,使用者每次存檔
  /// 都要重新掃過全部組別、且理論上一次編輯不該對同一個動作生出多筆 PR
  /// 列——收斂成「每個動作只送一次候選」,candidate 的欄位構造(除了
  /// weight/reps/oneRepMax 换成挑出來那組的值)仍照抄該段程式碼。
  ///
  /// 1RM(不是重量)才是「最高」的正確判準:同一動作內較輕但反覆次數更多
  /// 的一組,Epley 公式換算後 1RM 可能反而更高(見 one_rm_calculator.dart)。
  Future<void> _checkPersonalRecords(Workout workout) async {
    final prRepo = ref.read(personalRecordRepositoryProvider);
    final now = DateTime.now();

    for (final exercise in workout.exercises) {
      WorkoutSet? bestSet;
      double bestOneRepMax = -1;
      for (final set in exercise.sets) {
        if (set.isWarmup) continue;
        final oneRepMax = calculateOneRepMax(weight: set.weight, reps: set.reps);
        if (oneRepMax > bestOneRepMax) {
          bestOneRepMax = oneRepMax;
          bestSet = set;
        }
      }
      if (bestSet == null) continue;

      final candidate = PersonalRecord(
        id: generateUuidV4(),
        userId: workout.userId,
        exerciseId: exercise.exerciseId,
        weight: bestSet.weight,
        reps: bestSet.reps,
        oneRepMax: bestOneRepMax,
        // 對齊 workout_controller.dart:PR 的 achievedAt 用訓練開始時間,
        // 不是編輯當下的時間。
        achievedAt: workout.startedAt,
        workoutId: workout.id,
        createdAt: now,
        updatedAt: now,
      );
      await prRepo.createIfNewPR(candidate);
    }
  }

  // MARK: - 編輯操作(全部重用 WorkoutRepository 現成方法,見 brief seam)

  /// 更新既有組數(重量/次數/RPE/暖身標記)。[set] 通常是從目前 state 裡
  /// 讀出的既有 `WorkoutSet` 再用 `copyWith` 改過欄位,呼叫端(編輯
  /// sheet)負責組出完整的新版本。
  Future<void> updateSet(WorkoutSet set) =>
      _mutate((_) => ref.read(workoutRepositoryProvider).updateSet(set));

  /// 新增一組。[setNumber] 由目前 state 裡該動作既有的組數長度 + 1 算出。
  Future<void> addSet({
    required String workoutExerciseId,
    required double weight,
    required int reps,
    double? rpe,
    bool isWarmup = false,
    int restSeconds = kDefaultRestSeconds,
  }) =>
      _mutate((draft) async {
        final exercise = draft.exercises.firstWhere(
          (e) => e.id == workoutExerciseId,
          orElse: () => throw StateError('動作不存在於目前訓練:$workoutExerciseId'),
        );
        final now = DateTime.now();
        await ref.read(workoutRepositoryProvider).addSet(WorkoutSet(
              id: generateUuidV4(),
              workoutExerciseId: workoutExerciseId,
              setNumber: exercise.sets.length + 1,
              weight: weight,
              reps: reps,
              rpe: rpe,
              restSeconds: restSeconds,
              isWarmup: isWarmup,
              createdAt: now,
              updatedAt: now,
            ));
      });

  /// 刪除一組(確認對話框由呼叫端 UI 負責,見 workout_edit_page.dart)。
  Future<void> deleteSet(String setId, {required String workoutExerciseId}) => _mutate(
        (_) => ref
            .read(workoutRepositoryProvider)
            .deleteSet(setId, workoutExerciseId: workoutExerciseId),
      );

  /// 新增動作到訓練(接在現有動作之後,orderIndex 依序遞增)。
  Future<void> addExercise(Exercise exercise) => _mutate((draft) async {
        final now = DateTime.now();
        await ref.read(workoutRepositoryProvider).addExerciseToWorkout(WorkoutExercise(
              id: generateUuidV4(),
              workoutId: draft.id,
              exerciseId: exercise.id,
              exerciseName: exercise.name,
              orderIndex: draft.exercises.length,
              createdAt: now,
              updatedAt: now,
            ));
      });

  /// 移除動作(確認對話框由呼叫端 UI 負責)。最後一個動作也可以刪——
  /// 訓練會變成空殼(0 動作)但仍然存在,不會連帶刪除整筆訓練。
  Future<void> removeExercise(String workoutExerciseId) => _mutate(
        (_) => ref
            .read(workoutRepositoryProvider)
            .removeExercise(workoutExerciseId, workoutId: workoutId),
      );

  /// 更新訓練備註。**刻意不用 `Workout.copyWith`**——它的 `note` 參數是
  /// `note ?? this.note`,傳 `null` 代表「不覆寫」而不是「清空備註」,沒有
  /// 辦法把既有備註改回空(`data/models/workout.dart` 不在本波可動檔案
  /// 清單內,不能就地修正這個限制,這裡改用完整具名建構子繞開)。其餘欄位
  /// 照抄目前 state 的完整值(重讀後的最新值)——`WorkoutRepository.update`
  /// 會同時覆寫 summary 五欄(endedAt/duration/totalVolume/totalSets/
  /// totalExercises),用完整值當底才不會把其他欄位寫壞;`_mutate` 收尾
  /// 一律再跑一次 `recomputeSummary`,即使這裡帶的 summary 值有任何失準
  /// 也會被蓋回正確結果(見 brief seam 說明)。
  Future<void> updateNote(String? note) => _mutate((draft) {
        final updated = Workout(
          id: draft.id,
          userId: draft.userId,
          startedAt: draft.startedAt,
          endedAt: draft.endedAt,
          duration: draft.duration,
          totalVolume: draft.totalVolume,
          totalSets: draft.totalSets,
          totalExercises: draft.totalExercises,
          note: note,
          templateId: draft.templateId,
          isSynced: draft.isSynced,
          exercises: draft.exercises,
          createdAt: draft.createdAt,
          updatedAt: draft.updatedAt,
        );
        return ref.read(workoutRepositoryProvider).update(updated);
      });
}

final workoutEditControllerProvider =
    AsyncNotifierProvider.family<WorkoutEditController, WorkoutEditState, String>(
  WorkoutEditController.new,
);
