// 歷史「列表」檢視的資料組裝與刪除控制。對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/ViewModels/HistoryViewModel.swift`
// 的列表部分(不含篩選——brief 明確排除,iOS 篩選面板本身也是不生效的
// demo shell)。
//
// ## userId／資料流(規則張力,已於動工前 SendMessage 回報,採用下述設計)
// brief Seam 第 4 點要求「controller 的 userId／資料流照
// `pr_list_controller.dart` 的慣例(`_resolveUserId` 複本照抄)」,但 Seam
// 第 3 點同時明講這裡用到的三個 repository 方法(`fetchAll`/
// `fetchByDateRange`/`delete`)都**不吃 userId 參數**——複製一份完全沒有
// 呼叫點的 `_resolveUserId` 私有方法會被 `flutter analyze` 判
// unused_element,直接擋掉「0 issues」驗收標準。這裡改成只沿用
// pr_list_controller.dart 「watch session 以便換帳號時觸發 provider 重新
// build()」的**資料流**慣例(即使 fetchAll() 本身不分帳號,watch 仍能保持
// 跟其他 controller 一致的重新整理時機——同 body_weight_controller.dart
// 對 `entriesDesc` 的既有注記:不是「乾淨换帳號」的完整保證,只是不留
// *查詢結果*的記憶體快取),不複製沒有落點的 `_resolveUserId` 本體。
//
// ## 快取生命週期
// `AsyncNotifierProvider`,非 autoDispose,失效路徑:
//   1. 顯式:[deleteWorkout] 刪除成功後呼叫 [_load] 整包重新查詢(不是自己
//      在記憶體裡剔除該筆——避免記憶體 state 跟 DB 打結),同時
//      `ref.read(historyCalendarControllerProvider.notifier).refresh()`
//      讓日曆檢視即使不在畫面上也保持資料一致(使用者從列表刪除後切去日曆
//      檢視,不該看到已刪除的訓練)。[WorkoutDetailPage] 的刪除按鈕呼叫的
//      是同一個 [deleteWorkout] 方法(不是各自重複一份刪除邏輯),回到列表
//      頁時資料自然一致。
//   2. session 變動:build() watch `sessionControllerProvider`,換帳號時
//      Riverpod 自動重跑 build()。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/workout.dart';
import '../../data/providers.dart';
import '../auth/session_controller.dart';
import 'history_calendar_controller.dart';

class HistoryListState {
  const HistoryListState({this.workouts = const [], this.deletingIds = const {}});

  /// 已完成訓練,`WorkoutRepository.fetchAll()` 已排序新到舊、排除草稿。
  final List<Workout> workouts;

  /// 正在刪除中的 workout id 集合——[WorkoutHistoryCard] 依此顯示列內
  /// loading 遮罩;刪除失敗時會從這裡移除(解除遮罩),不會卡死。
  final Set<String> deletingIds;

  HistoryListState copyWith({List<Workout>? workouts, Set<String>? deletingIds}) {
    return HistoryListState(
      workouts: workouts ?? this.workouts,
      deletingIds: deletingIds ?? this.deletingIds,
    );
  }
}

class HistoryListController extends AsyncNotifier<HistoryListState> {
  @override
  Future<HistoryListState> build() {
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    return _load();
  }

  Future<HistoryListState> _load() async {
    final repo = ref.read(workoutRepositoryProvider);
    final workouts = await repo.fetchAll();
    return HistoryListState(workouts: workouts);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  /// 刪除一筆訓練。過程:若目前有已載入的 state,標記 [id] 進
  /// `deletingIds`(觸發列內 loading)→ 呼叫 repository 刪除 → 成功則整包
  /// 重新查詢(連帶清空 `deletingIds`,因為重新查詢回傳的是全新 state)並
  /// 讓日曆檢視一併重新整理;失敗則把 [id] 從 `deletingIds` 移除(解除
  /// loading)並把例外原樣 rethrow,交給呼叫端(列表列 / 詳情頁)決定怎麼
  /// 呈現錯誤(SnackBar)——state 本身不落入 `AsyncError`,不影響其他列或
  /// 整頁的呈現。
  ///
  /// **review 打回 MAJOR-1(修復)**:`state.value` 在 state 還沒載入完成
  /// (`AsyncLoading`)或上一次載入失敗(`AsyncError`)時是 null——先前這裡
  /// `if (current == null) return;` 直接靜默 no-op、不呼叫 repository、也
  /// 不拋錯,呼叫端(詳情頁)收到「成功」的 Future 照樣 pop,使用者以為
  /// 刪了、資料其實還在 DB 裡。現在不論 state 是否已載入,都一律真的呼叫
  /// `repo.delete(id)`;`deletingIds` 的標記/解除只在「有 state 可以標記」
  /// 時才做(state 本來就是 null,標記與解除都無意義,不強行造一個假
  /// state),刪除本身的成功/失敗不受影響——失敗一律 rethrow,不會有任何
  /// 路徑靜默吞掉刪除失敗。
  Future<void> deleteWorkout(String id) async {
    final before = state.value;
    if (before != null) {
      state = AsyncData(before.copyWith(deletingIds: {...before.deletingIds, id}));
    }
    try {
      final repo = ref.read(workoutRepositoryProvider);
      await repo.delete(id);
      state = await AsyncValue.guard(_load);
      await ref.read(historyCalendarControllerProvider.notifier).refresh();
    } catch (e) {
      final latest = state.value ?? before;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(deletingIds: <String>{...latest.deletingIds}..remove(id)),
        );
      }
      rethrow;
    }
  }
}

final historyListControllerProvider =
    AsyncNotifierProvider<HistoryListController, HistoryListState>(HistoryListController.new);
