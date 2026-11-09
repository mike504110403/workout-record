// 波 6 偏好設定——主題(淺色/深色/跟隨系統)。用 Flutter 內建的 [ThemeMode]
// 當狀態型別(不用 iOS `User.AppTheme` 那種自訂 enum,三個 case 一一對應,
// 沒有映射損失)。
//
// legacy 預填有兩個來源(見 `legacy_prefs_importer.dart`):
// - `legacy_theme`:GlobalSettings.theme 搬過來的字串,值域對照 iOS
//   `Models/User.swift` 的 `AppTheme`("light"/"dark"/"system")。
// - `legacy_is_dark_mode`:更舊版本(還沒有主題選擇器、只有單一深色模式開關
//   時期)的 bool 開關,對應 GlobalSettings 頂層 `isDarkMode` key。
// 兩者都可能存在。優先權:`legacy_theme` 有值就用它(值域對不上時直接落
// system,不再退回 `legacy_is_dark_mode`——一個新版本才會出現的欄位如果壞了
// 不該用更舊的訊號去猜,見 brief 第 2 項判斷);`legacy_theme` 完全沒有值
// 才看 `legacy_is_dark_mode`;兩者都沒有落 system。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/shared_preferences_provider.dart';

const kThemeModePrefsKey = 'theme_mode';
const kLegacyThemePrefsKey = 'legacy_theme';
const kLegacyIsDarkModePrefsKey = 'legacy_is_dark_mode';

/// [ThemeMode] <-> 持久化字串,對齊 iOS `User.AppTheme` 的 rawValue
/// ("light"/"dark"/"system")。回傳 null 代表值域對不上(呼叫端自行決定
/// fallback,兩個 key 的 fallback 規則不同,不能在這裡統一處理)。
ThemeMode? _themeModeFromStorageString(String? raw) => switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };

String _themeModeToStorageString(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

/// [kThemeModePrefsKey] 沒有值時的 legacy 預填鏈。
ThemeMode _resolveLegacyThemeMode(SharedPreferences prefs) {
  final rawTheme = prefs.getString(kLegacyThemePrefsKey);
  if (rawTheme != null) {
    // 此輸入不受信:legacy_theme 存在但值域對不上時直接落 system,不炸、
    // 也不退回 legacy_is_dark_mode。
    return _themeModeFromStorageString(rawTheme) ?? ThemeMode.system;
  }
  final isDark = prefs.getBool(kLegacyIsDarkModePrefsKey);
  if (isDark != null) return isDark ? ThemeMode.dark : ThemeMode.light;
  return ThemeMode.system;
}

/// [themeModeProvider] 的真身實作。
///
/// 快取生命週期(含換帳號):同 [WeightUnitController]——`theme_mode`/
/// `legacy_theme`/`legacy_is_dark_mode` 都是裝置層級設定,不在換帳號清除
/// 清單裡,刻意不 watch `sessionControllerProvider`。
/// (大腦裁示追認 2026-09-01:偏好不隨換帳號清除——裝置層級設定,非個資,
/// 不進清除清單,跨帳號共用是正確行為)
/// 注意:這四個 controller 只 watch sharedPreferencesProvider 的 instance;日後
/// 若把其 key 列入換帳號/登出清除清單,`prefs.remove()` 不會觸發 rebuild,
/// 清除點必須同步 invalidate 對應 provider,否則會靜默留著舊 state。
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getString(kThemeModePrefsKey);
    if (stored != null) {
      // 只有本 controller 會寫入這個 key,理論上不會出現對不上值域的情況;
      // 防禦式處理仍落 system,不讓一筆髒資料炸掉整頁。
      return _themeModeFromStorageString(stored) ?? ThemeMode.system;
    }
    return _resolveLegacyThemeMode(prefs);
  }

  /// 設定頁選擇主題:寫入失敗時 state 維持原值,UI 自然顯示回舊選項(同
  /// [WeightUnitController.setUnit] 的理由)。
  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(kThemeModePrefsKey, _themeModeToStorageString(mode));
    state = mode;
  }
}

final themeModeControllerProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// 當前主題模式。大腦 merge 後接進 `app.dart` 的 `MaterialApp.themeMode`
/// (本波不做這條接線)。
final themeModeProvider = Provider<ThemeMode>((ref) => ref.watch(themeModeControllerProvider));
