// Dashboard 專用的純函式格式化工具。刻意不用 intl `DateFormat`——避免測試
// 環境需要額外 `initializeDateFormatting`,而 Dashboard 只需要固定的
// `M/d HH:mm` 短格式(對照 iOS `.formatted(date: .abbreviated, time: .shortened)`
// 的視覺效果,不逐字對應其 locale 相依輸出)。
//
// 重量/容量格式化波 6 起薄轉發至 `core/format/weight_format.dart`(原本
// 「4 份 format 函式各 feature 一份」是舊慣例,波 6 起收斂成共用一份、依
// `WeightUnit` 換算顯示值;呼叫端一律要傳目前單位,不再有隱含 kg 版本)。
import '../../core/format/weight_format.dart' as weight_format;
import '../settings/preferences/weight_unit.dart';

String formatWorkoutDateTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.month}/${dateTime.day} $hour:$minute';
}

/// 對照 iOS `String(format: "%.0f kg", volume)`(lb 模式換算顯示值 + 字尾)。
String formatVolumeKg(double volume, WeightUnit unit) =>
    weight_format.formatWeight(volume, unit, decimals: 0);

/// 對照 iOS `String(format: "%.0f", volume)`(不帶單位——單位由
/// `MetricTile.unit` 另外顯示,這個慣例兩種單位都維持)。
String formatVolumeBare(double volume, WeightUnit unit) =>
    weight_format.formatWeightValue(volume, unit, decimals: 0);

/// 對照 iOS `String(format: "%.1f kg", weight)`(lb 模式換算顯示值 + 字尾)。
String formatWeightKg(double weight, WeightUnit unit) =>
    weight_format.formatWeight(weight, unit, decimals: 1);

/// 體重卡單列用的變化量:▲ 上升、▼ 下降,不帶單位(單位已在前面的體重上)。
/// 輸入 kg 差值,依 [unit] 換算;四捨五入到 0.1 後為 0 不帶箭頭。
/// 箭頭只表方向、不套好壞色——減脂與增肌的人對漲跌的好壞相反。
String formatWeightChangeArrow(double deltaKg, WeightUnit unit) {
  final shown = kgToDisplay(deltaKg, unit);
  final magnitude = shown.abs().toStringAsFixed(1);
  if (double.parse(magnitude) == 0) return magnitude;
  return '${shown < 0 ? '\u25BC' : '\u25B2'}$magnitude';
}
