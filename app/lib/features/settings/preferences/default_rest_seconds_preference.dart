// 波 6 偏好設定——預設休息秒數。現行常數 `kDefaultRestSeconds`
// (`workout_ui_shared.dart`,值 90)是 iOS `GlobalSettingsManager.
// defaultRestTime` 的預設值(同檔 `@Published var defaultRestTime: Int = 90`)
// 沿用過來的,無任何 prefs 值時的 fallback 直接用它,兩邊語意一致。
//
// 呼叫端(workout_ui_shared.dart 的消費點)本波不接線——只交付
// [defaultRestSecondsProvider] 這個單一真源。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/shared_preferences_provider.dart';
import '../../workout/workout_ui_shared.dart' show kDefaultRestSeconds;

const kDefaultRestSecondsPrefsKey = 'default_rest_seconds';

/// legacy_prefs_importer.dart 的 `migrateInt('legacy_default_rest_time', ...)`
/// 目標 key,來源是 GlobalSettings.defaultRestTime(秒,int)。
const kLegacyDefaultRestTimePrefsKey = 'legacy_default_rest_time';

/// prefs 存的秒數必須是正整數才採信——legacy 資料可能是 0 或負數(此輸入不
/// 受信,落安全預設而非直接拿來用,負數秒數沒有任何合理意義)。
bool _isValidRestSeconds(int? seconds) => seconds != null && seconds > 0;

/// [defaultRestSecondsProvider] 的真身實作。
///
/// 快取生命週期(含換帳號):同 [WeightUnitController] 的理由——
/// `default_rest_seconds`/`legacy_default_rest_time` 是裝置層級設定,不在
/// 換帳號清除清單裡,刻意不 watch `sessionControllerProvider`。
/// (大腦裁示追認 2026-09-01:裝置層級設定,非個資,不進清除清單)
class DefaultRestSecondsController extends Notifier<int> {
  @override
  int build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getInt(kDefaultRestSecondsPrefsKey);
    if (_isValidRestSeconds(stored)) return stored!;
    final legacy = prefs.getInt(kLegacyDefaultRestTimePrefsKey);
    if (_isValidRestSeconds(legacy)) return legacy!;
    return kDefaultRestSeconds;
  }

  /// 設定頁選擇秒數:寫入失敗時 state 維持原值(同
  /// [WeightUnitController.setUnit] 的理由)。
  Future<void> setSeconds(int seconds) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(kDefaultRestSecondsPrefsKey, seconds);
    state = seconds;
  }
}

final defaultRestSecondsControllerProvider =
    NotifierProvider<DefaultRestSecondsController, int>(
  DefaultRestSecondsController.new,
);

/// 當前預設休息秒數。大腦 merge 後接進計時器初始值呼叫端(本波不做這條
/// 接線)。
final defaultRestSecondsProvider =
    Provider<int>((ref) => ref.watch(defaultRestSecondsControllerProvider));
