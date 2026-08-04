// Dashboard 專用的純函式格式化工具。刻意不用 intl `DateFormat`——避免測試
// 環境需要額外 `initializeDateFormatting`,而 Dashboard 只需要固定的
// `M/d HH:mm` 短格式(對照 iOS `.formatted(date: .abbreviated, time: .shortened)`
// 的視覺效果,不逐字對應其 locale 相依輸出)。

String formatWorkoutDateTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.month}/${dateTime.day} $hour:$minute';
}

/// 對照 iOS `String(format: "%.0f kg", volume)`。
String formatVolumeKg(double volume) => '${volume.toStringAsFixed(0)} kg';

/// 對照 iOS `String(format: "%.0f", volume)`(StatCard 不帶單位)。
String formatVolumeBare(double volume) => volume.toStringAsFixed(0);

/// 對照 iOS `String(format: "%.1f kg", weight)`。
String formatWeightKg(double weight) => '${weight.toStringAsFixed(1)} kg';
