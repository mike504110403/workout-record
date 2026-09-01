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
  const HistoryCalendarState({
    required this.displayedMonth,
    this.workouts = const [],
    this.selectedDate,
  });

  /// 目前顯示的月份,已截斷成該月 1 號 00:00(不含時分秒)。
  final DateTime displayedMonth;

  /// [displayedMonth] 當月已完成訓練,`WorkoutRepository.fetchByDateRange`
  /// 已排除草稿。
  final List<Workout> workouts;

  /// 使用者點選的日期(僅日期部分)。null = 尚未選取,「當天訓練清單」區塊
  /// 不顯示。切月份時重置為 null(對照 iOS `changeMonth` 的
  /// `selectedDate = nil`)。
  final DateTime? selectedDate;

  HistoryCalendarState copyWith({
    DateTime? displayedMonth,
    List<Workout>? workouts,
    DateTime? selectedDate,
    bool clearSelectedDate = false,
  }) {
    return HistoryCalendarState(
      displayedMonth: displayedMonth ?? this.displayedMonth,
      workouts: workouts ?? this.workouts,
      selectedDate: clearSelectedDate ? null : (selectedDate ?? this.selectedDate),
    );
  }
}

class HistoryCalendarController extends AsyncNotifier<HistoryCalendarState> {
  @override
  Future<HistoryCalendarState> build() {
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    final now = DateTime.now();
    return _loadMonth(DateTime(now.year, now.month, 1));
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

  /// 切換月份([delta] = -1 上個月 / +1 下個月),重新查詢新月份的資料,
  /// 並重置 `selectedDate`(對照 iOS `changeMonth`)。
  Future<void> changeMonth(int delta) async {
    final base = state.value?.displayedMonth ?? DateTime.now();
    final target = DateTime(base.year, base.month + delta, 1);
    state = await AsyncValue.guard(() => _loadMonth(target));
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
    final month = current?.displayedMonth ?? DateTime(DateTime.now().year, DateTime.now().month, 1);
    state = await AsyncValue.guard(() => _loadMonth(month, selectedDate: current?.selectedDate));
  }
}

final historyCalendarControllerProvider =
    AsyncNotifierProvider<HistoryCalendarController, HistoryCalendarState>(HistoryCalendarController.new);
