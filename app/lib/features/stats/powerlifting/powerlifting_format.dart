// 「經典三項」子頁專用的純函式格式化工具。刻意不用 intl `DateFormat`
// (理由同 `features/dashboard/dashboard_format.dart`),獨立一份而非共用
// dashboard 的版本——這個 feature 目錄要求自足,不跨 feature import。
//
// 重量格式化波 6 起薄轉發至 `core/format/weight_format.dart`(原本「4 份
// format 函式各 feature 一份」是舊慣例;波 6 起收斂成共用一份、依
// `WeightUnit` 換算顯示值,呼叫端一律要傳目前單位——本檔案雖不在原本 4
// 份之列,但同樣是「各 feature 一份」的重複實作,一併收斂)。
import '../../../core/format/weight_format.dart' as weight_format;
import '../../settings/preferences/weight_unit.dart';

/// 對照 iOS `String(format: "%.1f", weight)`(不含單位字尾,呼叫端各自
/// 決定要不要接 unitSuffix——維持既有慣例)。
String formatWeight(double weight, WeightUnit unit) => weight_format.formatWeightValue(weight, unit);

/// 對照 iOS `.formatted(date: .abbreviated, time: .omitted)` 的視覺效果。
String formatDate(DateTime date) => '${date.year}/${date.month}/${date.day}';
