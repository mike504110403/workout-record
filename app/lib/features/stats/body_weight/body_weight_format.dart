// Stats/體重子頁專用的純函式格式化工具。刻意跟 dashboard_format.dart 各自
// 一份、不共用——兩邊格式需求目前剛好重疊(%.1f kg),但屬不同 feature，
// 各自獨立比共用一份跨 feature 耦合更划算（對照
// dashboard/dashboard_format.dart 開頭同樣的理由）。
//
// 重量格式化波 6 起薄轉發至 `core/format/weight_format.dart`(原本「4 份
// format 函式各 feature 一份」是舊慣例;波 6 起收斂成共用一份、依
// `WeightUnit` 換算顯示值,呼叫端一律要傳目前單位)。
import '../../../core/format/weight_format.dart' as weight_format;
import '../../settings/preferences/weight_unit.dart';

/// 對照 iOS `String(format: "%.1f", weight)` + 單位字尾(kg 模式輸出字串
/// 與改造前逐字元相同——no-op 基準)。
String formatBodyWeightKg(double weight, WeightUnit unit) => weight_format.formatWeight(weight, unit);

/// 對照 iOS `latest.measuredAt.formatted(date: .abbreviated, time: .shortened)`
/// 的視覺效果，不逐字對應其 locale 相依輸出（同 dashboard_format.dart 的
/// `formatWorkoutDateTime` 理由）。刻意帶年份——體重紀錄列表可能橫跨超過
/// 一年，只有「月/日 時:分」會讓跨年的兩筆紀錄顯示成一樣的文字。
String formatBodyWeightDateTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}/${dateTime.month}/${dateTime.day} $hour:$minute';
}
