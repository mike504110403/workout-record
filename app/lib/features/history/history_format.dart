// 歷史頁專用的純函式格式化工具。刻意不用 intl `DateFormat`(理由同
// `features/dashboard/dashboard_format.dart` 開頭注解:避免測試環境需要
// 額外 `initializeDateFormatting`),獨立一份而非共用 dashboard/其他
// feature 的版本——本波 brief 範圍界線只允許動 `features/history/`,不跨
// feature import(同 `workout_stats_format.dart` 開頭注解的理由)。

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

/// 對照 iOS `String(format: "%.0f kg", volume)`。
String formatVolumeKg(double volume) => '${volume.toStringAsFixed(0)} kg';

/// review 打回 MINOR-3:動作明細直印 `set.weight`(double)會顯示「60.0 kg」
/// 這種不必要的尾綴——照 dashboard_format.dart:19 慣例補一位小數格式化。
/// 對照 iOS `String(format: "%.1f kg", weight)`。
String formatWeightKg(double weight) => '${weight.toStringAsFixed(1)} kg';

/// 容量分布卡的百分比文字,對照 iOS
/// `String(format: "(%.0f%%)", exercise.percentage)`。
String formatPercentage(double percentage) => '${percentage.toStringAsFixed(0)}%';
