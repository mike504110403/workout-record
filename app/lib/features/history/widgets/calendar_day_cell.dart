// 月曆單一日期格:數字 + 有訓練時的小圓點標記(對照 iOS `dayCell(for:)`——
// 只用小圓點,不是容量深淺)。
import 'package:flutter/material.dart';

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
    final foreground = isSelected
        ? colorScheme.onPrimary
        : (isToday ? colorScheme.primary : colorScheme.onSurface);

    return InkWell(
      key: Key('historyCalendarDay-${day.year}-${day.month}-${day.day}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary
              : (isToday ? colorScheme.primary.withValues(alpha: 0.1) : null),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                color: foreground,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (hasWorkout)
              Container(
                key: Key('historyCalendarMarker-${day.year}-${day.month}-${day.day}'),
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? colorScheme.onPrimary : colorScheme.primary,
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
