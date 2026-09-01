// 全 app 共用的重量顯示格式化——波 6 收斂進來,取代原本「4 份 format 函式
// 各 feature 一份」的舊慣例(dashboard_format.dart 等檔案原本的開頭注解就是
// 在講這個慣例;波 6 起改成共用這一份,各 feature 檔案改為薄轉發)。
//
// 換算唯一來源是 `features/settings/preferences/weight_unit.dart` 的
// `kgToDisplay`/`unitSuffix`——本檔案不自帶係數,只負責「數字要留幾位小數、
// 要不要接單位字尾」這種純格式化規則。
import '../../features/settings/preferences/weight_unit.dart';

/// 重量數值(不含單位字尾),例如「60.0」/「132.3」。[kg] 是儲存值(恆
/// kg),依 [unit] 換算成顯示值再取到 [decimals] 位小數。
String formatWeightValue(double kg, WeightUnit unit, {int decimals = 1}) =>
    kgToDisplay(kg, unit).toStringAsFixed(decimals);

/// 重量數值 + 單位字尾,例如「60.0 kg」/「132.3 lb」。
String formatWeight(double kg, WeightUnit unit, {int decimals = 1}) =>
    '${formatWeightValue(kg, unit, decimals: decimals)} ${unitSuffix(unit)}';
