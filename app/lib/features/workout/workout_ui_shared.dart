// 訓練核心流共用的小工具,避免 add_set_sheet.dart/workout_in_progress_view.dart/
// workout_summary_sheet.dart 各自抄一份、改一處漏兩處(code review r1
// minor)。**檔名裡的「ui」是歷史命名,不是分層訊號**——`kDefaultRestSeconds`
// 也被 `workout_controller.dart`(非 UI 層)消費,不要以為這裡只給 widget
// 檔案 import(code review r2 minor:避免誤導未來的分層判斷)。

import '../settings/preferences/weight_unit.dart';

/// 整數值不顯示小數點(例如 60 顯示成 `60` 不是 `60.0`),非整數保留原始
/// 精度。用於重量/RPE 顯示。
String trimZeros(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toString();
}

/// 重量的唯讀顯示字串(數字部分,不含單位):kg→顯示單位後四捨五入到小數 2 位
/// 再去尾 0。lb 換算有浮點長尾(100 kg → 220.46226218500001),唯讀顯示一律走這裡;
/// 可編輯欄位的預填值不走這裡(取整後原樣存回會改動 kg 值)。
/// kg 模式同樣取 2 位:手動輸入 3 位小數(如 1.125)時唯讀顯示 1.13、編輯欄仍是 1.125,接受。
String displayWeight(double kg, WeightUnit unit) =>
    trimZeros((kgToDisplay(kg, unit) * 100).round() / 100);

/// 記組 sheet 的預設休息秒數(對照 iOS `AddSetSheet.swift` 的
/// `GlobalSettingsManager.shared.defaultRestTime` 預設值)。`AddSetSheet`/
/// `WorkoutController.addSet`/`workout_in_progress_view.dart` 的編輯回填
/// 三處原本各自寫死 `90`,收斂成具名常數。
const kDefaultRestSeconds = 90;
