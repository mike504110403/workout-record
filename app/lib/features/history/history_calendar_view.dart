// 歷史頁「日曆」檢視:月視圖 + 有訓練的日子標記小圓點 + 點選日期顯示當天
// 訓練清單(對照 iOS `HistoryCalendarView`)。不含刪除入口——刪除只在
// 列表滑動、詳情頁按鈕兩處(brief 規格)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_grid.dart';
import 'history_calendar_controller.dart';
import 'history_format.dart';
import 'widgets/calendar_day_cell.dart';
import 'widgets/history_error_view.dart';
import 'widgets/workout_history_card.dart';
import 'workout_detail_page.dart';

class HistoryCalendarView extends ConsumerWidget {
  const HistoryCalendarView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyCalendarControllerProvider);
    return async.when(
      data: (state) => _CalendarBody(state: state),
      loading: () => const Center(child: CircularProgressIndicator()),
      // review 打回 MINOR-6:錯誤重試不能用 `ref.invalidate`——那會整個重跑
      // build(),把月份跳回「本月」,跟 history_calendar_controller.dart
      // `refresh()` 文件注解的設計意圖(保留 displayedMonth/selectedDate)
      // 相衝。改叫 `.notifier.refresh()`:Riverpod 的 `AsyncNotifier.state`
      // setter 內部會自動對新 state 做 `copyWithPrevious`(見
      // riverpod `element.dart` `asyncTransition`),所以就算目前落在
      // `AsyncError`,`state.value` 仍讀得到上一次成功載入的
      // `displayedMonth`,`refresh()` 才能真的重新查詢「原本在看的那個
      // 月份」,不是悄悄跳回本月。
      error: (error, stackTrace) => HistoryErrorView(
        retryButtonKey: const Key('historyCalendarErrorRetryButton'),
        onRetry: () => ref.read(historyCalendarControllerProvider.notifier).refresh(),
      ),
    );
  }
}

class _CalendarBody extends ConsumerWidget {
  const _CalendarBody({required this.state});

  final HistoryCalendarState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(historyCalendarControllerProvider.notifier);
    final today = DateTime.now();
    final workoutDates = {for (final w in state.workouts) dateOnly(w.startedAt)};
    final days = buildCalendarGrid(state.displayedMonth);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                key: const Key('historyCalendarPrevMonthButton'),
                icon: const Icon(Icons.chevron_left),
                onPressed: () => notifier.changeMonth(-1),
              ),
              Text(
                formatMonthLabel(state.displayedMonth),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                key: const Key('historyCalendarNextMonthButton'),
                icon: const Icon(Icons.chevron_right),
                onPressed: () => notifier.changeMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final day in days)
                if (day == null)
                  const SizedBox.shrink()
                else
                  CalendarDayCell(
                    day: day,
                    hasWorkout: workoutDates.contains(day),
                    isSelected: state.selectedDate != null && isSameDate(state.selectedDate!, day),
                    isToday: isSameDate(today, day),
                    onTap: () => notifier.selectDate(day),
                  ),
            ],
          ),
          const SizedBox(height: 20),
          if (state.selectedDate != null) _SelectedDateWorkouts(state: state),
        ],
      ),
    );
  }
}

class _SelectedDateWorkouts extends StatelessWidget {
  const _SelectedDateWorkouts({required this.state});

  final HistoryCalendarState state;

  @override
  Widget build(BuildContext context) {
    final selected = state.selectedDate!;
    final dayWorkouts = state.workouts.where((w) => isSameDate(w.startedAt, selected)).toList();

    return Column(
      key: const Key('historyCalendarSelectedDateSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatHistoryDate(selected), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (dayWorkouts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('當天無訓練記錄')),
          )
        else
          for (final workout in dayWorkouts)
            WorkoutHistoryCard(
              workout: workout,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => WorkoutDetailPage(workout: workout))),
            ),
      ],
    );
  }
}
