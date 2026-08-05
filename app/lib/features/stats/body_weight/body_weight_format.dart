// Stats/體重子頁專用的純函式格式化工具。刻意跟 dashboard_format.dart 各自
// 一份、不共用——兩邊格式需求目前剛好重疊(%.1f kg),但屬不同 feature，
// 各自獨立比共用一份跨 feature 耦合更划算（對照
// dashboard/dashboard_format.dart 開頭同樣的理由）。

/// 對照 iOS `String(format: "%.1f", weight)` + 「kg」單位。
String formatBodyWeightKg(double weight) => '${weight.toStringAsFixed(1)} kg';

/// 對照 iOS `latest.measuredAt.formatted(date: .abbreviated, time: .shortened)`
/// 的視覺效果，不逐字對應其 locale 相依輸出（同 dashboard_format.dart 的
/// `formatWorkoutDateTime` 理由）。刻意帶年份——體重紀錄列表可能橫跨超過
/// 一年，只有「月/日 時:分」會讓跨年的兩筆紀錄顯示成一樣的文字。
String formatBodyWeightDateTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}/${dateTime.month}/${dateTime.day} $hour:$minute';
}
