// 歷史頁專用的純函式格式化工具。刻意不用 intl `DateFormat`(理由同
// `features/dashboard/dashboard_format.dart` 開頭注解:避免測試環境需要
// 額外 `initializeDateFormatting`),獨立一份而非共用 dashboard/其他
// feature 的版本——本波 brief 範圍界線只允許動 `features/history/`,不跨
// feature import(同 `workout_stats_format.dart` 開頭注解的理由)。
//
// 重量/容量格式化波 6 起薄轉發至 `core/format/weight_format.dart`(原本
// 「4 份 format 函式各 feature 一份」是舊慣例;波 6 起收斂成共用一份、依
// `WeightUnit` 換算顯示值,呼叫端一律要傳目前單位)。
import '../../core/format/weight_format.dart' as weight_format;
import '../../data/models/workout.dart';
import '../settings/preferences/weight_unit.dart';

/// 對照 iOS `.formatted(date: .abbreviated, time: .omitted)` 的視覺效果
/// (History 列表/詳情頁只顯示日期,不顯示時間——時間對「哪天練了什麼」
/// 這個場景不是關鍵資訊,iOS `WorkoutHistoryCard` 才顯示時間,
/// `WorkoutDetailView.summaryCard` 只顯示日期)。
String formatHistoryDate(DateTime date) => '${date.year}/${date.month}/${date.day}';

/// 月曆頂部的月份標籤,例如「2026年9月」。
String formatMonthLabel(DateTime month) => '${month.year}年${month.month}月';

/// 對照 iOS `Text("\(workout.duration) 分鐘")`。[minutes] 為 null 時(理論上
/// 不會發生——已完成訓練 `completeWorkout` 一律會寫入 duration,這裡防禦
/// 性地當 0 分鐘處理,不讓畫面顯示「null 分鐘」)。
String formatDurationMinutes(int? minutes) => '${minutes ?? 0} 分鐘';

/// 對照 iOS `String(format: "%.0f kg", volume)`(lb 模式換算顯示值 + 字尾)。
String formatVolumeKg(double volume, WeightUnit unit) =>
    weight_format.formatWeight(volume, unit, decimals: 0);

/// review 打回 MINOR-3:動作明細直印 `set.weight`(double)會顯示「60.0 kg」
/// 這種不必要的尾綴——照 dashboard_format.dart:19 慣例補一位小數格式化。
/// 對照 iOS `String(format: "%.1f kg", weight)`(lb 模式換算顯示值 + 字尾)。
String formatWeightKg(double weight, WeightUnit unit) =>
    weight_format.formatWeight(weight, unit, decimals: 1);

/// 容量分布卡的百分比文字,對照 iOS
/// `String(format: "(%.0f%%)", exercise.percentage)`。
String formatPercentage(double percentage) => '${percentage.toStringAsFixed(0)}%';

/// 單組休息時間,照搬 iOS `WorkoutDetailView.formatRestTime`
/// (WorkoutDetailView.swift:367-376):滿 1 分鐘顯示「m:ss」(例如 90 秒 →
/// 「1:30」,秒數補零),不滿 1 分鐘顯示「Ns」(例如 45 秒 → 「45s」)。
String formatRestSeconds(int seconds) {
  final minutes = seconds ~/ 60;
  final secs = seconds % 60;
  if (minutes > 0) return '$minutes:${secs.toString().padLeft(2, '0')}';
  return '${secs}s';
}

const _weekdayLabels = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'];

/// 星期幾標籤(「週一」…「週日」),歷史列表卡片日期旁顯示。
/// `DateTime.weekday`:週一=1 .. 週日=7。
String formatHistoryWeekday(DateTime date) => _weekdayLabels[date.weekday - 1];

/// 單一動作顯示名:優先用關聯的 Exercise 名稱,其次快照名稱,最後「未知動作」
/// (與詳情頁動作明細同一套 fallback)。
String workoutExerciseDisplayName(WorkoutExercise exercise) =>
    exercise.exercise?.name ?? exercise.exerciseName ?? '未知動作';

/// 列表卡片的動作摘要,例如「槓鈴臥推、深蹲 +2」:最多列出前 [maxNames]
/// 個動作名,超出的以「+N」收尾。沒有任何動作時回傳 null(卡片不顯示該行)。
String? summarizeWorkoutExercises(Workout workout, {int maxNames = 2}) {
  final names = [for (final e in workout.exercises) workoutExerciseDisplayName(e)];
  if (names.isEmpty) return null;
  final shown = names.take(maxNames).join('、');
  final rest = names.length - maxNames;
  return rest > 0 ? '$shown +$rest' : shown;
}
