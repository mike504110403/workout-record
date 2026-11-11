// 歷史「日曆」檢視的資料組裝與月份/選取日狀態控制。對照 iOS
// `HistoryCalendarView`。userId／資料流慣例與快取生命週期理由同
// history_list_controller.dart 檔頭注解(這裡不重複):同樣只 watch
// session 觸發重新 build,不複製沒有呼叫點的 `_resolveUserId`。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/workout.dart';
import '../../data/providers.dart';
import '../auth/session_controller.dart';
import 'calendar_grid.dart';

class HistoryCalendarState {
  HistoryCalendarState({
    required this.displayedMonth,
    this.workouts = const [],
    this.selectedDate,
    List<DateTime?>? reuseDays,
    Set<DateTime>? reuseWorkoutDates,
  }) : days = reuseDays ?? buildCalendarGrid(displayedMonth),
       workoutDates = reuseWorkoutDates ?? {for (final w in workouts) dateOnly(w.startedAt)},
       selectedWorkouts = selectedDate == null
           ? const []
           : [for (final w in workouts) if (isSameDate(w.startedAt, selectedDate)) w];

  /// 目前顯示的月份,已截斷成該月 1 號 00:00(不含時分秒)。
  final DateTime displayedMonth;

  /// [displayedMonth] 當月已完成訓練,`WorkoutRepository.fetchByDateRange`
  /// 已排除草稿。
  final List<Workout> workouts;

  /// 使用者點選(或預設選中)的日期(僅日期部分)。null = 當月沒有任何可預設
  /// 選取的日子(切到沒有訓練的月份),「當天訓練清單」區塊不顯示。
  final DateTime? selectedDate;

  /// 月曆格線(null = 月初前／月底後的空格)。以下三個衍生值都在建構時算好,
  /// 不放進 widget 的 build。[copyWith] 在月份、訓練清單沒變時(例如只是選日期)
  /// 直接沿用既有的 [days]／[workoutDates],只重算 [selectedWorkouts]。
  final List<DateTime?> days;

  /// 當月有訓練的日期集合(僅日期部分),日曆格用來決定要不要畫標記。
  final Set<DateTime> workoutDates;

  /// [selectedDate] 當天的訓練,保留 [workouts] 的順序(新到舊)。
  final List<Workout> selectedWorkouts;

  HistoryCalendarState copyWith({
    DateTime? displayedMonth,
    List<Workout>? workouts,
    DateTime? selectedDate,
    bool clearSelectedDate = false,
  }) {
    final sameMonth = displayedMonth == null || displayedMonth == this.displayedMonth;
    final sameWorkouts = workouts == null || identical(workouts, this.workouts);
    return HistoryCalendarState(
      displayedMonth: displayedMonth ?? this.displayedMonth,
      workouts: workouts ?? this.workouts,
      selectedDate: clearSelectedDate ? null : (selectedDate ?? this.selectedDate),
      reuseDays: sameMonth ? days : null,
      reuseWorkoutDates: sameWorkouts ? workoutDates : null,
    );
  }
}

class HistoryCalendarController extends AsyncNotifier<HistoryCalendarState> {
  @override
  Future<HistoryCalendarState> build() {
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    return _loadInitial();
  }

  /// 預設選取規則:本月有訓練 → 今天有就選今天、否則選本月最近一天(本月資料
  /// 已在手,不再多打一次 `fetchRecent`);本月沒有才往前找「最近一次有訓練的
  /// 日子」(可能落在更早的月份,此時一併把顯示月份切過去,不然選了看不到);
  /// 完全沒有訓練紀錄才選今天(下方顯示「當天無訓練記錄」)。
  Future<HistoryCalendarState> _loadInitial() async {
    final now = DateTime.now();
    final today = dateOnly(now);
    final thisMonth = DateTime(now.year, now.month, 1);
    final monthState = await _loadMonth(thisMonth);
    final pick = _defaultSelection(monthState);
    if (pick != null) return monthState.copyWith(selectedDate: pick);
    // 「往前找最近一天」只是加分的預設選取;它失敗(網路等)不該讓整頁變錯誤頁,
    // 退回選今天即可,使用者仍可正常翻月、點日期。
    final List<Workout> recent;
    try {
      recent = await ref.read(workoutRepositoryProvider).fetchRecent(1);
    } catch (_) {
      return monthState.copyWith(selectedDate: today);
    }
    if (recent.isEmpty) return monthState.copyWith(selectedDate: today);
    final lastDay = dateOnly(recent.first.startedAt);
    final lastMonth = DateTime(lastDay.year, lastDay.month, 1);
    if (lastMonth == thisMonth) return monthState.copyWith(selectedDate: lastDay);
    return _loadMonth(lastMonth, selectedDate: lastDay);
  }

  Future<HistoryCalendarState> _loadMonth(DateTime month, {DateTime? selectedDate}) async {
    final repo = ref.read(workoutRepositoryProvider);
    final from = month;
    // 下個月 1 號減 1 毫秒 = 當月最後一刻,涵蓋整個月(不用「當月最後一天
    // 23:59:59」手算,避免大月/小月/閏年算錯)。
    final to = DateTime(month.year, month.month + 1, 1).subtract(const Duration(milliseconds: 1));
    final workouts = await repo.fetchByDateRange(from, to);
    return HistoryCalendarState(displayedMonth: month, workouts: workouts, selectedDate: selectedDate);
  }

  /// 切換月份([delta] = -1 上個月 / +1 下個月),重新查詢新月份的資料。
  /// 選取日改為新月份「最近一次有訓練的日子」(本月且今天有訓練則選今天),
  /// 讓切月後下方不是一片空白;該月沒有訓練則不選(對照 iOS `changeMonth`
  /// 原本一律重置為 nil)。
  Future<void> changeMonth(int delta) async {
    final base = state.value?.displayedMonth ?? DateTime.now();
    final target = DateTime(base.year, base.month + delta, 1);
    state = await AsyncValue.guard(() async {
      final loaded = await _loadMonth(target);
      final pick = _defaultSelection(loaded);
      return pick == null ? loaded : loaded.copyWith(selectedDate: pick);
    });
  }

  DateTime? _defaultSelection(HistoryCalendarState loaded) {
    if (loaded.workouts.isEmpty) return null;
    final today = dateOnly(DateTime.now());
    if (loaded.workoutDates.contains(today)) return today;
    // fetchByDateRange 已新到舊排序,第一筆就是當月最近一次。
    return dateOnly(loaded.workouts.first.startedAt);
  }

  void selectDate(DateTime date) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(selectedDate: dateOnly(date)));
  }

  /// 重新查詢**目前顯示的月份**(保留 `displayedMonth`/`selectedDate`,不
  /// 像 `ref.invalidate` 會整個重跑 build() 把月份跳回「本月」)——
  /// history_list_controller.dart 刪除成功後呼叫這個方法,讓日曆檢視即使
  /// 當下不在畫面上也保持跟列表一致的資料。
  Future<void> refresh() async {
    final current = state.value;
    // 沒有任何成功載入過的 state(初次載入失敗後重試、或日曆沒開過就被列表
    // 刪除觸發):等同初次載入,要套用預設選中,而不是載出一個沒選日期的月份。
    if (current == null) {
      state = await AsyncValue.guard(_loadInitial);
      return;
    }
    state = await AsyncValue.guard(
      () => _loadMonth(current.displayedMonth, selectedDate: current.selectedDate),
    );
  }
}

final historyCalendarControllerProvider =
    AsyncNotifierProvider<HistoryCalendarController, HistoryCalendarState>(HistoryCalendarController.new);
