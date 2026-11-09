// 波 6 偏好設定——1RM(單次最大重量)估算公式。
//
// `one_rm_calculator.dart` 目前只實作 Epley 一種公式(`calculateOneRepMax`
// 不帶 formula 參數,見該檔開頭註解:PR 偵測只會用到 iOS 預設值 `.epley`,
// Brzycki/Lander 沒有任何呼叫路徑,所以沒有移植計算本體)。本波只交付
// 「使用者選了哪個公式」這個偏好狀態的單一真源——[OneRmFormula] 三個
// case 對齊 iOS `Models/User.swift` 的 `OneRMFormula`(值域無損映射),
// **不含 Brzycki/Lander 的計算實作**,公式呼叫端要不要、何時擴充計算本體
// 是大腦 merge 後的事,不在本 brief 範圍。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/shared_preferences_provider.dart';

/// 對齊 iOS `Models/User.swift` 的 `OneRMFormula` rawValue
/// ("epley"/"brzycki"/"lander")。
enum OneRmFormula {
  epley,
  brzycki,
  lander;

  static OneRmFormula fromStorageString(String? raw) => switch (raw) {
        'brzycki' => OneRmFormula.brzycki,
        'lander' => OneRmFormula.lander,
        _ => OneRmFormula.epley, // 未知值/null 落 epley(iOS 與現行實作的預設值)
      };

  String get storageString => name;

  String get displayName => switch (this) {
        OneRmFormula.epley => 'Epley',
        OneRmFormula.brzycki => 'Brzycki',
        OneRmFormula.lander => 'Lander',
      };
}

const kOneRmFormulaPrefsKey = 'one_rm_formula';

/// legacy_prefs_importer.dart 的 `migrateString('legacy_one_rm_formula', ...)`
/// 目標 key,來源是 GlobalSettings.oneRMFormula。
const kLegacyOneRmFormulaPrefsKey = 'legacy_one_rm_formula';

/// [oneRmFormulaProvider] 的真身實作。
///
/// 快取生命週期(含換帳號):同 [WeightUnitController] 的理由——
/// `one_rm_formula`/`legacy_one_rm_formula` 是裝置層級設定,不在換帳號清除
/// 清單裡,刻意不 watch `sessionControllerProvider`。
/// (大腦裁示追認 2026-09-01:偏好不隨換帳號清除——裝置層級設定,非個資,
/// 不進清除清單,跨帳號共用是正確行為)
/// 注意:這四個 controller 只 watch sharedPreferencesProvider 的 instance;日後
/// 若把其 key 列入換帳號/登出清除清單,`prefs.remove()` 不會觸發 rebuild,
/// 清除點必須同步 invalidate 對應 provider,否則會靜默留著舊 state。
class OneRmFormulaController extends Notifier<OneRmFormula> {
  @override
  OneRmFormula build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getString(kOneRmFormulaPrefsKey);
    if (stored != null) return OneRmFormula.fromStorageString(stored);
    // fromStorageString 本身已把 null/未知值落 epley,legacy 畸形值不需要
    // 另外判斷。
    return OneRmFormula.fromStorageString(prefs.getString(kLegacyOneRmFormulaPrefsKey));
  }

  /// 設定頁選擇公式:寫入失敗時 state 維持原值(同
  /// [WeightUnitController.setUnit] 的理由)。
  Future<void> setFormula(OneRmFormula formula) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(kOneRmFormulaPrefsKey, formula.storageString);
    state = formula;
  }
}

final oneRmFormulaControllerProvider = NotifierProvider<OneRmFormulaController, OneRmFormula>(
  OneRmFormulaController.new,
);

/// 當前 1RM 估算公式。大腦 merge 後接進 `one_rm_calculator.dart` 呼叫端
/// (本波不做這條接線;呼叫端目前也只有 Epley 實作可接)。
final oneRmFormulaProvider =
    Provider<OneRmFormula>((ref) => ref.watch(oneRmFormulaControllerProvider));
