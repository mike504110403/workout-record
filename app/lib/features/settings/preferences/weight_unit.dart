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

import '../../auth/shared_preferences_provider.dart';

/// 新 prefs key(本波新增,B 工人定名)——設定頁選過一次之後就以這個 key
/// 為準,不再看 legacy。
const kWeightUnitPrefsKey = 'weight_unit';

/// legacy_prefs_importer.dart 搬進來的舊值目標 key("kg"/"lb" 字串,見該檔
/// `migrateString('legacy_weight_unit', ...)`)。只在 [kWeightUnitPrefsKey]
/// 還沒有值時當預填來源。
const kLegacyWeightUnitPrefsKey = 'legacy_weight_unit';

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

/// [weightUnitProvider] 的真身實作(波 6 B 工人接上 SharedPreferences)。
///
/// 快取生命週期(含換帳號):[kWeightUnitPrefsKey]/[kLegacyWeightUnitPrefsKey]
/// 都是「裝置層級」設定,不是使用者個資——換帳號確認清除時只清 Drift 全表
/// + Onboarding 個資 prefs(見
/// `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`「實作補充」
/// 節與 `legacy_prefs_importer.dart` 的 `kLegacyPrefsPersonalDataKeys` 清單,
/// 兩處都刻意不列 `legacy_weight_unit`/`weight_unit`),所以本 controller
/// 刻意不 watch `sessionControllerProvider`——沒有「換帳號後要清掉重讀」這
/// 件事,值就是這台裝置目前選的單位,跨帳號共用是正確行為而非快取殘留。
/// 仍然 `ref.watch(sharedPreferencesProvider)`(而非 `read`)是照抄
/// onboarding_status.dart 既有慣例:讓測試換掉 override 時能重新 build()。
/// (大腦裁示追認 2026-09-01:裝置層級設定,非個資,不進清除清單)
class WeightUnitController extends Notifier<WeightUnit> {
  @override
  WeightUnit build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getString(kWeightUnitPrefsKey);
    if (stored != null) return WeightUnit.fromStorageString(stored);
    // 無新 key → legacy 預填。fromStorageString 本身已把 null/未知值落 kg,
    // 不需要在這裡另外判斷「legacy 值畸形」——同一個 fail-safe 規則兩處共用。
    final legacy = prefs.getString(kLegacyWeightUnitPrefsKey);
    return WeightUnit.fromStorageString(legacy);
  }

  /// 設定頁選擇單位:寫入 prefs 後才更新 state——寫入失敗(如磁碟已滿)時
  /// state 維持原值,UI(直接 watch [weightUnitProvider])自然顯示回舊選項,
  /// 不需要額外的「復原」邏輯。呼叫端(PreferencesPage)自己包 try/catch 顯示
  /// 失敗浮錯、解除 loading。
  Future<void> setUnit(WeightUnit unit) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(kWeightUnitPrefsKey, unit.storageString);
    state = unit;
  }
}

final weightUnitControllerProvider = NotifierProvider<WeightUnitController, WeightUnit>(
  WeightUnitController.new,
);

/// 當前重量顯示單位。
///
/// 契約:同步 Provider、型別/名稱不可改(C 工人 22 個檔案消費它)。真身是
/// 上面的 [WeightUnitController]——本 provider 只是把 Notifier 的 state 攤平
/// 成單純的 `Provider<WeightUnit>`,讀端(C 工人)不需要知道背後有 prefs
/// 持久化;寫端(PreferencesPage)另外經 [weightUnitControllerProvider] 呼叫
/// `.setUnit()`。
final weightUnitProvider = Provider<WeightUnit>((ref) => ref.watch(weightUnitControllerProvider));
