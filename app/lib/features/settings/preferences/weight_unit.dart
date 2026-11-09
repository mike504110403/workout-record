// 波 6 跨工人契約檔(大腦定,commit 在 feature/wave6 基底):重量單位的
// enum/換算純函式/provider 介面。
//
// 分工契約:
// - preferences 工人(B):把 [weightUnitProvider] 接上 SharedPreferences
//   持久化(含 legacy_weight_unit 預填)與偏好設定頁 UI——可改本檔的
//   provider 實作,**不得改 enum 名/函式簽名/換算係數**(顯示層工人以此
//   為編譯依賴)。
// - unit-display 工人(C):只消費——`ref.watch(weightUnitProvider)` 拿
//   [WeightUnit],用 [kgToDisplay]/[displayToKg]/[unitSuffix] 做顯示與
//   輸入換算。**儲存一律 kg**(DB/model 單位不變),lb 只存在於顯示層。
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 重量顯示單位。持久化字串值對齊 iOS `GlobalSettings.weightUnit`
/// ("kg"/"lb",legacy_prefs_importer 搬進 `legacy_weight_unit`)。
enum WeightUnit {
  kg,
  lb;

  static WeightUnit fromStorageString(String? raw) => switch (raw) {
        'lb' => WeightUnit.lb,
        _ => WeightUnit.kg, // 未知值/null 一律回 kg(fail-safe 到現狀)
      };

  String get storageString => name;
}

/// 1 kg = 2.20462262185 lb(國際常衡磅定義換算,顯示層唯一係數來源——
/// 消費端不得自帶字面係數)。
const double kLbPerKg = 2.20462262185;

/// kg(儲存值)→ 當前單位的顯示值。
double kgToDisplay(double kg, WeightUnit unit) =>
    unit == WeightUnit.lb ? kg * kLbPerKg : kg;

/// 當前單位的輸入值 → kg(儲存值)。
double displayToKg(double value, WeightUnit unit) =>
    unit == WeightUnit.lb ? value / kLbPerKg : value;

/// 單位字尾(顯示用)。
String unitSuffix(WeightUnit unit) => unit == WeightUnit.lb ? 'lb' : 'kg';

/// 當前重量顯示單位。
///
/// 契約:同步 Provider、預設 [WeightUnit.kg]。B 工人負責換成綁
/// SharedPreferences 的真身(持久化+legacy 預填+設定頁寫入時更新+換帳號
/// 重讀);在那之前的 stub 恆回 kg——所有顯示行為與波 5 現狀一致,
/// C 工人的改造在 stub 下必須是 no-op(這也是 C 的回歸基準)。
final weightUnitProvider = Provider<WeightUnit>((ref) => WeightUnit.kg);
