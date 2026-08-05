// 「經典三項」子頁專用的純函式格式化工具。刻意不用 intl `DateFormat`
// (理由同 `features/dashboard/dashboard_format.dart`),獨立一份而非共用
// dashboard 的版本——這個 feature 目錄要求自足,不跨 feature import。

/// 對照 iOS `String(format: "%.1f", weight)`(WeightFormatter 只用公斤,
/// 這裡不做單位換算)。
String formatWeight(double weight) => weight.toStringAsFixed(1);

/// 對照 iOS `.formatted(date: .abbreviated, time: .omitted)` 的視覺效果。
String formatDate(DateTime date) => '${date.year}/${date.month}/${date.day}';
