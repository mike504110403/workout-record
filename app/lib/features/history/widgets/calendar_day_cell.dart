// 月曆單一日期格:數字 + 有訓練時的小圓點標記與實心底色(iOS `dayCell(for:)`
// 只有小圓點,UI 優化波加上底色讓有訓練的日子更醒目;仍不是容量深淺)。
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    super.key,
    required this.day,
    required this.hasWorkout,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool hasWorkout;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 狀態優先序:選取(實心主色)> 有訓練(主色容器實心底)> 今天(淡底)。
    // 有訓練的日子除了小圓點,再加實心底色,遠看也能一眼找到。
    final Color? background;
    final Color foreground;
    if (isSelected) {
      background = colorScheme.primary;
      foreground = colorScheme.onPrimary;
    } else if (hasWorkout) {
      background = colorScheme.primaryContainer;
      foreground = colorScheme.onPrimaryContainer;
    } else if (isToday) {
      background = colorScheme.primary.withValues(alpha: 0.1);
      foreground = colorScheme.primary;
    } else {
      background = null;
      foreground = colorScheme.onSurface;
    }
    final markerColor = isSelected ? colorScheme.onPrimary : colorScheme.primary;

    return InkWell(
      key: Key('historyCalendarDay-${day.year}-${day.month}-${day.day}'),
      onTap: onTap,
      borderRadius: AppRadius.chipRadius,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.chipRadius,
          // 今天用細框標示(即使同時有訓練/被選取也看得出來)。
          border: isToday && !isSelected
              ? Border.all(color: colorScheme.primary, width: 1.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                color: foreground,
                fontWeight: isToday || hasWorkout ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (hasWorkout)
              Container(
                key: Key('historyCalendarMarker-${day.year}-${day.month}-${day.day}'),
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(shape: BoxShape.circle, color: markerColor),
              )
            else
              const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
