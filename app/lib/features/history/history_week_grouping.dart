// 歷史列表的「按週分組」純函式層(不吃 BuildContext,方便單獨測試)。
//
// 週起算沿用 dashboard_controller.dart / workout_stats_controller.dart 的
// 慣例:固定 ISO 8601(週一為一週開始),讓列表的「本週」與首頁/數據頁的
// 「本週」是同一個範圍。(日曆檢視的欄位是週日起算,那是 iOS 版日曆格線的
// 既有排法,與這裡的「本週」語意無關。)
import '../../data/models/workout.dart';

class HistoryWeekGroup {
  const HistoryWeekGroup({required this.weekStart, required this.label, required this.workouts});

  /// 該週週一 00:00。
  final DateTime weekStart;

  /// 區塊標題:「本週」「上週」或「M/D – M/D」(週一 – 週日)。
  final String label;

  /// 該週的訓練,保留輸入順序(呼叫端已排序新到舊)。
  final List<Workout> workouts;
}

/// [date] 所在週的週一 00:00。用日曆欄位建構(而非減 Duration),跨 DST 不偏移。
DateTime startOfIsoWeek(DateTime date) =>
    DateTime(date.year, date.month, date.day - (date.weekday - 1));

/// 依週分組,保留輸入順序(連續同一週的項目收攏成一組)。[now] 只給測試注入。
List<HistoryWeekGroup> groupWorkoutsByWeek(List<Workout> workouts, {DateTime? now}) {
  final thisWeek = startOfIsoWeek(now ?? DateTime.now());
  final lastWeek = DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7);

  final groups = <HistoryWeekGroup>[];
  for (final workout in workouts) {
    final weekStart = startOfIsoWeek(workout.startedAt);
    final last = groups.isEmpty ? null : groups.last;
    if (last != null && last.weekStart == weekStart) {
      last.workouts.add(workout);
      continue;
    }
    groups.add(
      HistoryWeekGroup(
        weekStart: weekStart,
        label: _labelFor(weekStart, thisWeek: thisWeek, lastWeek: lastWeek),
        workouts: [workout],
      ),
    );
  }
  return groups;
}

String _labelFor(DateTime weekStart, {required DateTime thisWeek, required DateTime lastWeek}) {
  if (weekStart == thisWeek) return '本週';
  if (weekStart == lastWeek) return '上週';
  final weekEnd = DateTime(weekStart.year, weekStart.month, weekStart.day + 6);
  return '${weekStart.month}/${weekStart.day} – ${weekEnd.month}/${weekEnd.day}';
}
