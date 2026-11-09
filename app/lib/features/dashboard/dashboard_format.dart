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

/// 對照 iOS `String(format: "%.0f", volume)`(StatCard 不帶單位——這個
/// 慣例兩種單位都維持,不額外補字尾,避免打破既有窄版面設計)。
String formatVolumeBare(double volume, WeightUnit unit) =>
    weight_format.formatWeightValue(volume, unit, decimals: 0);

/// 對照 iOS `String(format: "%.1f kg", weight)`(lb 模式換算顯示值 + 字尾)。
String formatWeightKg(double weight, WeightUnit unit) =>
    weight_format.formatWeight(weight, unit, decimals: 1);
