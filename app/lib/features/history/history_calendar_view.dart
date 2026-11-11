// 歷史頁「日曆」檢視:月視圖 + 有訓練的日子標記小圓點 + 點選日期顯示當天
// 訓練清單(對照 iOS `HistoryCalendarView`)。不含刪除入口——刪除只在
// 列表滑動、詳情頁按鈕兩處(brief 規格)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/section_header.dart';

import 'calendar_grid.dart';
import 'history_calendar_controller.dart';
import 'history_format.dart';
import 'widgets/calendar_day_cell.dart';
import 'widgets/history_error_view.dart';
import 'widgets/workout_history_card.dart';
import 'workout_detail_page.dart';

class HistoryCalendarView extends ConsumerWidget {
  const HistoryCalendarView({super.key, required this.modeToggle});

  /// 列表／日曆切換鈕,由 history_page.dart 提供。資料就緒時放進月份列右側;
  /// 載入中/錯誤時沒有月份列,改放精簡頂列,確保任何狀態都能切回列表。
  final Widget modeToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyCalendarControllerProvider);
    return async.when(
      data: (state) => _CalendarBody(state: state, modeToggle: modeToggle),
      loading: () => _ToggleOnlyLayout(
        modeToggle: modeToggle,
        child: const Center(child: CircularProgressIndicator()),
      ),
      // review 打回 MINOR-6:錯誤重試不能用 `ref.invalidate`——那會整個重跑
      // build(),把月份跳回「本月」,跟 history_calendar_controller.dart
      // `refresh()` 文件注解的設計意圖(保留 displayedMonth/selectedDate)
      // 相衝。改叫 `.notifier.refresh()`:Riverpod 的 `AsyncNotifier.state`
      // setter 內部會自動對新 state 做 `copyWithPrevious`(見
      // riverpod `element.dart` `asyncTransition`),所以就算目前落在
      // `AsyncError`,`state.value` 仍讀得到上一次成功載入的
      // `displayedMonth`,`refresh()` 才能真的重新查詢「原本在看的那個
      // 月份」,不是悄悄跳回本月。
      error: (error, stackTrace) => _ToggleOnlyLayout(
        modeToggle: modeToggle,
        child: HistoryErrorView(
          retryButtonKey: const Key('historyCalendarErrorRetryButton'),
          onRetry: () => ref.read(historyCalendarControllerProvider.notifier).refresh(),
        ),
      ),
    );
  }
}

/// 載入中/錯誤時的版面:右上一顆切換鈕 + 下方內容(沒有月份列可併入)。
class _ToggleOnlyLayout extends StatelessWidget {
  const _ToggleOnlyLayout({required this.modeToggle, required this.child});

  final Widget modeToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: Align(alignment: Alignment.centerRight, child: modeToggle),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _CalendarBody extends ConsumerWidget {
  const _CalendarBody({required this.state, required this.modeToggle});

  final HistoryCalendarState state;
  final Widget modeToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(historyCalendarControllerProvider.notifier);
    // 格線、有訓練的日期集合、選取日訓練都在 controller state 建構時算好,
    // build 只取用。
    final selectedWorkouts = state.selectedWorkouts;

    // 月曆區塊固定在頂端、下方當天訓練用 SliverList 懶建置,整頁一條捲動軸。
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: AppSpacing.pagePadding,
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 月份導覽靠左、切換鈕靠右,同一列(日曆模式不另佔頂列)。
                Row(
                  children: [
                    IconButton(
                      key: const Key('historyCalendarPrevMonthButton'),
                      icon: const Icon(Icons.chevron_left),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => notifier.changeMonth(-1),
                    ),
                    Text(
                      formatMonthLabel(state.displayedMonth),
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      key: const Key('historyCalendarNextMonthButton'),
                      icon: const Icon(Icons.chevron_right),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => notifier.changeMonth(1),
                    ),
                    const Spacer(),
                    modeToggle,
                  ],
                ),
                const _WeekdayHeader(),
                // RepaintBoundary:選日期時只有格線重畫,不連帶重畫下方卡片。
                RepaintBoundary(child: _MonthGrid(state: state, onSelect: notifier.selectDate)),
                const SizedBox(height: AppSpacing.lg),
                if (state.selectedDate != null)
                  _SelectedDateHeader(
                    selected: state.selectedDate!,
                    isEmpty: selectedWorkouts.isEmpty,
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal,
            0,
            AppSpacing.pageHorizontal,
            AppSpacing.lg,
          ),
          sliver: SliverList.builder(
            itemCount: selectedWorkouts.length,
            itemBuilder: (context, index) {
              final workout = selectedWorkouts[index];
              return WorkoutHistoryCard(
                workout: workout,
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => WorkoutDetailPage(workout: workout))),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 月曆格線:固定列高的 [Table](取代巢狀 `GridView shrinkWrap`——後者在父層
/// 捲動容器裡要求自己量出全部子項,又得關掉自身捲動)。7 欄等寬,與
/// [_WeekdayHeader] 的 7 個 `Expanded` 對齊。
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.state, required this.onSelect});

  final HistoryCalendarState state;
  final void Function(DateTime day) onSelect;

  /// 一列的高度:數字 + 標記點 + 格內邊距放得下,比正方形格(約 51)更緊湊。
  static const double _rowHeight = 46;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = state.days;
    return Table(
      key: const Key('historyCalendarGrid'),
      children: [
        for (var start = 0; start < days.length; start += 7)
          TableRow(
            children: [
              for (final day in days.sublist(start, start + 7))
                SizedBox(
                  height: _rowHeight,
                  child: day == null
                      ? null
                      : CalendarDayCell(
                          day: day,
                          hasWorkout: state.workoutDates.contains(day),
                          isSelected: state.selectedDate != null && isSameDate(state.selectedDate!, day),
                          isToday: isSameDate(today, day),
                          onTap: () => onSelect(day),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

/// 星期標題列(一二三四五六日)。7 個 `Expanded` 等寬,與下方 `GridView.count`
/// 的 7 欄對齊(格線無水平 padding)。
class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      key: const Key('historyCalendarWeekdayHeader'),
      children: [
        for (final (index, label) in kCalendarWeekdayLabels.indexed)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                label,
                key: Key('historyCalendarWeekday-$index'),
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
          ),
      ],
    );
  }
}

/// 選取日標題(+ 當天沒有訓練時的提示)。當天的訓練卡片在外層 SliverList。
class _SelectedDateHeader extends StatelessWidget {
  const _SelectedDateHeader({required this.selected, required this.isEmpty});

  final DateTime selected;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('historyCalendarSelectedDateSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '${formatHistoryDate(selected)} ${formatHistoryWeekday(selected)}',
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        ),
        if (isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: Text('當天無訓練記錄')),
          ),
      ],
    );
  }
}
