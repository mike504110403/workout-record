// 「這個使用者最近練過什麼、上次怎麼練」的查詢快照,給三處共用:
// - 選動作 sheet 頂端「最近用過」(最多 [kRecentExerciseLimit] 個);
// - 記組 sheet 第一組預填「該動作歷史最後一組」;
// - 從模板開始時計畫組的預填數字(上一次的重量次數,沒有才用模板值)。
//
// 排序/分組在 provider 裡算一次(不在 widget build 裡算)。開始新訓練(建新
// 草稿)與完成訓練時由 `WorkoutController` 失效重查——所以成功的結果「每次
// 訓練最多查一次」:第一個讀到它的畫面觸發查詢,之後整場訓練共用快取。只用
// 既有 repository API(`fetchRecent`),不碰資料層。
//
// **一律 best-effort**:雲端模式下 `fetchRecent` 走網路、離線會拋錯。這份
// 資料只拿來「預填/提示」,查不到就當沒有(回 [ExerciseHistory.unavailable]),
// 也刻意不放在開始訓練、寫入組的必經路徑上(呼叫端只 watch 它的 value)。
//
// **失敗結果不快取**:provider 是 autoDispose、只在查詢成功時 keepAlive——
// 失敗的空白結果沒人聽就丟掉,下次讀會重查。訓練畫面整場都在 watch 它,
// 所以另由使用者操作(記組、選動作)呼叫 [retryExerciseHistoryIfUnavailable]
// 重查;只在使用者操作時觸發,離線時不會自己一直打網路。
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/exercise.dart';
import '../../data/models/workout.dart';
import '../../data/providers.dart';
import '../auth/resolve_user_id.dart';
import '../auth/session_controller.dart';

/// 「最近用過」最多列幾個動作(brief:最多 8 個)。
const kRecentExerciseLimit = 8;

/// 往回看幾筆已完成訓練(固定 20,只用 `fetchRecent`、不准 `fetchAll`——雲端
/// 模式下它走網路,筆數要有上限)。單一使用者一週數練,20 筆約涵蓋一個多月,
/// 足夠找到「上一次」的數字。
const kExerciseHistoryLookback = 20;

@immutable
class ExerciseHistory {
  const ExerciseHistory({
    this.recentExerciseIds = const [],
    this.lastSetsByExerciseId = const {},
    this.exercisesById = const {},
    this.isUnavailable = false,
  });

  static const empty = ExerciseHistory();

  /// 查詢失敗時的空白替代品(內容同 [empty])。用旗標區分「真的沒練過」與
  /// 「沒查到」:後者不快取、使用者下次操作時重查。
  static const unavailable = ExerciseHistory(isUnavailable: true);

  /// 依最近訓練時間排序、去重後的動作 id(最多 [kRecentExerciseLimit] 個)。
  final List<String> recentExerciseIds;

  /// 每個動作「最近一次出現的那場訓練」裡的組(依 setNumber 排序)。有正式
  /// 組時只留正式組——預填暖身組的數字對下一次訓練沒有參考價值。
  final Map<String, List<WorkoutSet>> lastSetsByExerciseId;

  /// 查詢結果裡已 hydrate 的動作本體(本機 Drift 會帶;雲端 mapping 可能沒有,
  /// 由 [recentExercisesProvider] 補查)。
  final Map<String, Exercise> exercisesById;

  /// 這份快照是查詢失敗的空白替代品([unavailable])。
  final bool isUnavailable;

  /// 該動作歷史最後一組;沒練過回 null。
  WorkoutSet? lastSetFor(String exerciseId) {
    final sets = lastSetsByExerciseId[exerciseId];
    if (sets == null || sets.isEmpty) return null;
    return sets.last;
  }

  /// [workouts] 需已依 startedAt 由新到舊排序(`fetchRecent` 的契約)。
  factory ExerciseHistory.fromWorkouts(Iterable<Workout> workouts) {
    final recent = <String>[];
    final lastSets = <String, List<WorkoutSet>>{};
    final exercisesById = <String, Exercise>{};
    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        final exerciseId = exercise.exerciseId;
        if (exercise.sets.isEmpty || lastSets.containsKey(exerciseId)) continue;
        if (exercise.exercise case final hydrated?) exercisesById[exerciseId] = hydrated;
        final sorted = [...exercise.sets]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
        final working = sorted.where((s) => !s.isWarmup).toList();
        lastSets[exerciseId] = working.isNotEmpty ? working : sorted;
        if (recent.length < kRecentExerciseLimit) recent.add(exerciseId);
      }
    }
    return ExerciseHistory(
      recentExerciseIds: recent,
      lastSetsByExerciseId: lastSets,
      exercisesById: exercisesById,
    );
  }
}

final exerciseHistoryProvider = FutureProvider.autoDispose<ExerciseHistory>((ref) async {
  // 換帳號重查(同 WorkoutController.build 的慣例)。
  ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
  final repo = ref.watch(workoutRepositoryProvider);
  try {
    final userId = await resolveSessionUserId(ref);
    if (userId == null) return ExerciseHistory.empty;
    final workouts = await repo.fetchRecent(kExerciseHistoryLookback);
    // 只有成功的結果才留著(見檔頭「失敗結果不快取」)。查詢途中被失效
    // (例如剛好開始新訓練)時這份 ref 已作廢,不碰它。
    if (ref.mounted) ref.keepAlive();
    // 本機 Drift 的 fetchRecent 不分使用者(同一台裝置可能登過別的帳號),
    // 這裡再過濾一次,避免把別人的動作列進「最近用過」。
    return ExerciseHistory.fromWorkouts(workouts.where((w) => w.userId == userId));
  } catch (e) {
    // 離線/網路錯誤:提示資料拿不到就空白,不讓錯誤冒到畫面或擋住記組。
    debugPrint('exerciseHistoryProvider: 查詢最近訓練失敗,改用空白預填:$e');
    return ExerciseHistory.unavailable;
  }
});

/// 使用者操作(記組、選動作)時呼叫:目前的歷史快照是查詢失敗的替代品就
/// 失效重查,下一次讀到的是新結果。查詢中或查成功時什麼都不做。
void retryExerciseHistoryIfUnavailable(WidgetRef ref) {
  if (ref.read(exerciseHistoryProvider).value?.isUnavailable ?? false) {
    ref.invalidate(exerciseHistoryProvider);
  }
}

/// 選動作 sheet 頂端「最近用過」的動作清單(最多 [kRecentExerciseLimit] 個,
/// 依最近訓練時間排序)。獨立 provider,不改 `exercisePickerControllerProvider`
/// 的 state 形狀;同樣 best-effort——任何一步失敗就少列/不列,不擋選動作。
///
/// 同樣 autoDispose、只在歷史查成功時 keepAlive:它 watch 歷史,若無條件留著
/// 就會一直吊住歷史那份失敗結果,讓「失敗不快取」失效。
final recentExercisesProvider = FutureProvider.autoDispose<List<Exercise>>((ref) async {
  final history = await ref.watch(exerciseHistoryProvider.future);
  if (!history.isUnavailable && ref.mounted) ref.keepAlive();
  if (history.recentExerciseIds.isEmpty) return const [];
  final exerciseRepo = ref.watch(exerciseRepositoryProvider);
  final result = <Exercise>[];
  for (final id in history.recentExerciseIds) {
    var exercise = history.exercisesById[id];
    if (exercise == null) {
      try {
        exercise = await exerciseRepo.fetchById(id);
      } catch (_) {
        exercise = null;
      }
    }
    // 已停用(刪除)的自訂動作不再推薦。
    if (exercise != null && exercise.isActive) result.add(exercise);
  }
  return result;
});
