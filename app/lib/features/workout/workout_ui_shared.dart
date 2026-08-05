// 訓練核心流共用的小工具,避免 add_set_sheet.dart/workout_in_progress_view.dart/
// workout_summary_sheet.dart 各自抄一份、改一處漏兩處(code review r1
// minor)。**檔名裡的「ui」是歷史命名,不是分層訊號**——`kDefaultRestSeconds`
// 也被 `workout_controller.dart`(非 UI 層)消費,不要以為這裡只給 widget
// 檔案 import(code review r2 minor:避免誤導未來的分層判斷)。

/// 整數值不顯示小數點(例如 60 顯示成 `60` 不是 `60.0`),非整數保留原始
/// 精度。用於重量/RPE 顯示。
String trimZeros(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toString();
}

/// 記組 sheet 的預設休息秒數(對照 iOS `AddSetSheet.swift` 的
/// `GlobalSettingsManager.shared.defaultRestTime` 預設值)。`AddSetSheet`/
/// `WorkoutController.addSet`/`workout_in_progress_view.dart` 的編輯回填
/// 三處原本各自寫死 `90`,收斂成具名常數。
const kDefaultRestSeconds = 90;
