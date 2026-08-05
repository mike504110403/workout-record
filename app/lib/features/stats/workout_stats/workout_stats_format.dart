// 訓練統計子頁專用的純函式格式化工具。刻意獨立於
// `features/dashboard/dashboard_format.dart`(不 import dashboard 的檔案,
// brief 範圍界線——dashboard 這波只允許動 week_stats_section.dart 換
// import 那一處),即使格式化規則跟 dashboard 一致也各自維護一份小檔案,
// 避免 stats 依賴 dashboard 的內部工具模組。同理不用 intl `DateFormat`,
// 避免測試環境需要額外 `initializeDateFormatting`。
String formatWorkoutDateTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.month}/${dateTime.day} $hour:$minute';
}

/// 對照 iOS `String(format: "%.0f kg", volume)`。
String formatVolumeKg(double volume) => '${volume.toStringAsFixed(0)} kg';

/// 對照 iOS `String(format: "%.0f", volume)`(統計卡不帶單位)。
String formatVolumeBare(double volume) => volume.toStringAsFixed(0);
