// 舊版 iOS App(SwiftUI + CoreData)遺留在 NSUserDefaults.standard 裡的使用者
// 偏好設定 → 匯入 shared_preferences。規格見
// docs/COREDATA_MIGRATION_SPEC.md 第 3 節。
//
// 新舊 App 是同一個 bundle ID 覆蓋安裝,`Library/Preferences/<bundle
// id>.plist` 這份 plist 本身原封不動留在沙盒裡,`NSUserDefaults.standard`
// 讀到的就是同一份。採方案 A(spec 3.3 節):寫一段原生 Swift
// MethodChannel(`com.mikelin.workitout/legacy_prefs`,見
// app/ios/Runner/AppDelegate.swift)直接呼叫 `UserDefaults.standard` 的
// 型別化 API 讀值,回傳給 Dart,不在 Dart 端自己解析 binary plist。
//
// 只搬 spec 3.2 節「需要遷移」的項目:
// - GlobalSettings(JSON blob,優先)+ AppSettings/UserProfile 個別 key(補缺)
// - isDarkMode / accentColor / reminderTime / UnlockedAchievements /
//   lastViewedAchievementsDate
// - CurrentUserId(對應 CoreData UserEntity.id,供之後「目前使用者」判斷用)
//
// 刻意不搬(理由見 spec 3.2 節「不建議遷移」+ 附錄 5):
// - AppleIDUserID/Name/Email:Flutter 版登入流程怎麼設計還沒定案,
//   建議使用者重新走一次 Apple 登入即可,不在這裡靜默搬移登入身分。
// - PrivacyPolicyAccepted / HasAgreedToPrivacy 等隱私同意旗標:兩套舊設計
//   互相不同步,建議 Flutter 版重新設計一套流程要求使用者重新確認。
// - CoreDataMigrationCompleted / CoreDataModelVersion / DefaultDataInitialized
//   / ForceResetCoreData / Analytics* / CloudKit*:舊 App 內部狀態機或分析
//   資料,非使用者資產。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'import_log.dart';

const _channelName = 'com.mikelin.workitout/legacy_prefs';
const kLegacyPrefsImportCompletedKey = 'legacy_prefs_import_completed';

/// 帳號隔離換帳號清除用(見
/// `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`「實作補充」
/// 節與 session_controller.dart `confirmClearAndContinueLogin`):這裡搬進來
/// 的舊 App 使用者個資 key,換帳號確認清除時要一併清掉,不然殘留給下一個
/// 帳號。顯式列舉(對照下方 [importIfNeeded] 實際寫入的 key 名稱),不做
/// `legacy_` 前綴掃描——`legacy_weight_unit`/`legacy_theme` 等 App 設定類
/// key 不算個資,刻意不在這份清單裡。
const kLegacyPrefsPersonalDataKeys = <String>[
  'legacy_user_name',
  'legacy_user_email',
  'legacy_user_gender',
  'legacy_user_age',
  'legacy_user_height',
  'legacy_user_current_weight',
  'legacy_user_target_weight',
  'legacy_global_settings_json',
  'legacy_current_user_id',
];

class LegacyPrefsResult {
  const LegacyPrefsResult({
    required this.success,
    required this.skipped,
    this.errorMessage,
    this.migratedKeys = const [],
  });

  const LegacyPrefsResult.skipped()
      : success = true,
        skipped = true,
        errorMessage = null,
        migratedKeys = const [];

  final bool success;
  final bool skipped;
  final String? errorMessage;
  final List<String> migratedKeys;

  @override
  String toString() =>
      'LegacyPrefsResult(success: $success, skipped: $skipped, '
      'errorMessage: $errorMessage, migratedKeys: $migratedKeys)';
}

bool _defaultIsIOS() => Platform.isIOS;

class LegacyPrefsImporter {
  /// [isIOSCheck] 預設就是真正的 `Platform.isIOS`;測試時可以換成回傳固定
  /// 布林值的函式,跟 [CoreDataImporter] 建構子上可覆寫的
  /// directoryProvider 是同一套模式——`dart:io` 的 `Platform.isIOS` 本身
  /// 不可覆寫(沒有 setter),沒有這層間接就無法在非 iOS 的測試主機上驗證
  /// 「假裝自己在 iOS」的匯入邏輯。[supportDirectoryProvider] 同樣是給
  /// [ImportLog] 用的間接層,預設是 path_provider 的真正實作。
  const LegacyPrefsImporter({
    bool Function() isIOSCheck = _defaultIsIOS,
    Future<Directory> Function() supportDirectoryProvider =
        getApplicationSupportDirectory,
  })  : _isIOSCheck = isIOSCheck,
        _supportDirectoryProvider = supportDirectoryProvider;

  final bool Function() _isIOSCheck;
  final Future<Directory> Function() _supportDirectoryProvider;

  static const MethodChannel _channel = MethodChannel(_channelName);

  Future<LegacyPrefsResult> importIfNeeded() async {
    if (!_isIOSCheck()) {
      return const LegacyPrefsResult.skipped();
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kLegacyPrefsImportCompletedKey) ?? false) {
      return const LegacyPrefsResult.skipped();
    }

    final log = ImportLog(supportDirectoryProvider: _supportDirectoryProvider);
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getLegacyPreferences',
      );
      if (raw == null || raw.isEmpty) {
        await prefs.setBool(kLegacyPrefsImportCompletedKey, true);
        return const LegacyPrefsResult.skipped();
      }

      final migrated = <String>[];

      Map<String, dynamic>? globalSettings;
      final globalSettingsJson = raw['globalSettingsJson'] as String?;
      if (globalSettingsJson != null) {
        try {
          final decoded = jsonDecode(globalSettingsJson);
          if (decoded is Map<String, dynamic>) {
            globalSettings = decoded;
            await prefs.setString('legacy_global_settings_json', globalSettingsJson);
            migrated.add('legacy_global_settings_json');
          }
        } catch (_) {
          // GlobalSettings blob 格式不如預期時忽略,改用個別 AppSettings key 補缺。
        }
      }

      Future<void> migrateString(
        String newKey, {
        dynamic fromGlobalSettings,
        String? rawKey,
      }) async {
        final value = (fromGlobalSettings is String && fromGlobalSettings.isNotEmpty)
            ? fromGlobalSettings
            : (rawKey != null ? raw[rawKey] as String? : null);
        if (value != null && value.isNotEmpty) {
          await prefs.setString(newKey, value);
          migrated.add(newKey);
        }
      }

      Future<void> migrateBool(
        String newKey, {
        dynamic fromGlobalSettings,
        String? rawKey,
      }) async {
        final value = fromGlobalSettings is bool
            ? fromGlobalSettings
            : (rawKey != null ? raw[rawKey] as bool? : null);
        if (value != null) {
          await prefs.setBool(newKey, value);
          migrated.add(newKey);
        }
      }

      Future<void> migrateInt(
        String newKey, {
        dynamic fromGlobalSettings,
        String? rawKey,
      }) async {
        final value = fromGlobalSettings is num
            ? fromGlobalSettings.toInt()
            : (rawKey != null ? (raw[rawKey] as num?)?.toInt() : null);
        if (value != null) {
          await prefs.setInt(newKey, value);
          migrated.add(newKey);
        }
      }

      Future<void> migrateDouble(
        String newKey, {
        dynamic fromGlobalSettings,
        String? rawKey,
      }) async {
        final value = fromGlobalSettings is num
            ? fromGlobalSettings.toDouble()
            : (rawKey != null ? (raw[rawKey] as num?)?.toDouble() : null);
        if (value != null) {
          await prefs.setDouble(newKey, value);
          migrated.add(newKey);
        }
      }

      // CurrentUserId:對應到匯入後 Drift UserEntity 的 id,兩邊需保持一致
      // (見 spec 3.2 節)。
      await migrateString('legacy_current_user_id', rawKey: 'currentUserId');

      // GlobalSettings 優先,AppSettings/UserProfile 個別 key 補缺。
      await migrateString(
        'legacy_weight_unit',
        fromGlobalSettings: globalSettings?['weightUnit'],
        rawKey: 'weightUnit',
      );
      await migrateString(
        'legacy_theme',
        fromGlobalSettings: globalSettings?['theme'],
        rawKey: 'theme',
      );
      await migrateString(
        'legacy_one_rm_formula',
        fromGlobalSettings: globalSettings?['oneRMFormula'],
        rawKey: 'oneRMFormula',
      );
      await migrateInt(
        'legacy_default_rest_time',
        fromGlobalSettings: globalSettings?['defaultRestTime'],
      );
      await migrateBool(
        'legacy_show_volume_in_stats',
        fromGlobalSettings: globalSettings?['showVolumeInStats'],
      );
      await migrateBool(
        'legacy_enable_haptic_feedback',
        fromGlobalSettings: globalSettings?['enableHapticFeedback'],
        rawKey: 'enableHapticFeedback',
      );
      await migrateBool(
        'legacy_auto_save_workout',
        fromGlobalSettings: globalSettings?['autoSaveWorkout'],
      );

      // UserProfile(非 deprecated,AppleIDAuthService 登入成功後仍會寫入)。
      await migrateString('legacy_user_name', rawKey: 'userName');
      await migrateString('legacy_user_email', rawKey: 'userEmail');
      await migrateString('legacy_user_gender', rawKey: 'userGender');
      await migrateInt('legacy_user_age', rawKey: 'userAge');
      await migrateDouble('legacy_user_height', rawKey: 'userHeight');
      await migrateDouble('legacy_user_current_weight', rawKey: 'userCurrentWeight');
      await migrateDouble('legacy_user_target_weight', rawKey: 'userTargetWeight');
      await migrateInt('legacy_weekly_workout_goal', rawKey: 'weeklyWorkoutGoal');

      // 使用者體感相關。
      await migrateBool('legacy_is_dark_mode', rawKey: 'isDarkMode');
      await migrateInt('legacy_reminder_time_millis', rawKey: 'reminderTimeMillis');
      await migrateInt(
        'legacy_last_viewed_achievements_date_millis',
        rawKey: 'lastViewedAchievementsDateMillis',
      );
      await migrateString(
        'legacy_unlocked_achievements_json',
        rawKey: 'unlockedAchievementsJson',
      );

      // accentColor:原生端已用 NSKeyedUnarchiver 解出 RGBA 分量。
      await migrateDouble('legacy_accent_color_r', rawKey: 'accentColorR');
      await migrateDouble('legacy_accent_color_g', rawKey: 'accentColorG');
      await migrateDouble('legacy_accent_color_b', rawKey: 'accentColorB');
      await migrateDouble('legacy_accent_color_a', rawKey: 'accentColorA');

      await prefs.setBool(kLegacyPrefsImportCompletedKey, true);
      return LegacyPrefsResult(success: true, skipped: false, migratedKeys: migrated);
    } catch (e, st) {
      // 不寫完成旗標,下次啟動自動重試。失敗原因寫進本地 log(spec 4.6 節
      // 「不要只靠 debugPrint」),跟 CoreDataImporter 共用同一套截斷規則。
      await log.append(
        'legacy prefs 匯入失敗:${truncateForImportLog('$e\n$st')}',
      );
      return LegacyPrefsResult(
        success: false,
        skipped: false,
        errorMessage: '$e\n$st',
      );
    }
  }
}
