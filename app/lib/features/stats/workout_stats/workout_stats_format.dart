// 訓練統計子頁專用的純函式格式化工具。刻意獨立於
// `features/dashboard/dashboard_format.dart`(不 import dashboard 的檔案,
// brief 範圍界線——dashboard 這波只允許動 week_stats_section.dart 換
// import 那一處),即使格式化規則跟 dashboard 一致也各自維護一份小檔案,
// 避免 stats 依賴 dashboard 的內部工具模組。同理不用 intl `DateFormat`,
// 避免測試環境需要額外 `initializeDateFormatting`。
//
// 重量/容量格式化波 6 起薄轉發至 `core/format/weight_format.dart`(原本
// 「4 份 format 函式各 feature 一份」是舊慣例;波 6 起收斂成共用一份、依
// `WeightUnit` 換算顯示值,呼叫端一律要傳目前單位)。
import '../../../core/format/weight_format.dart' as weight_format;
import '../../settings/preferences/weight_unit.dart';

String formatWorkoutDateTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.month}/${dateTime.day} $hour:$minute';
}

/// 對照 iOS `String(format: "%.0f kg", volume)`(lb 模式換算顯示值 + 字尾)。
String formatVolumeKg(double volume, WeightUnit unit) =>
    weight_format.formatWeight(volume, unit, decimals: 0);

/// 對照 iOS `String(format: "%.0f", volume)`(統計卡不帶單位——兩種單位都
/// 維持這個慣例,不額外補字尾)。
String formatVolumeBare(double volume, WeightUnit unit) =>
    weight_format.formatWeightValue(volume, unit, decimals: 0);
