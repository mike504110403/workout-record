// LegacyPrefsImporter 的單元測試(spec 3 節)。
//
// 用 TestDefaultBinaryMessengerBinding mock
// `com.mikelin.workitout/legacy_prefs` MethodChannel 模擬原生端回傳值,搭配
// SharedPreferences.setMockInitialValues 驗證寫入結果。
//
// `Platform.isIOS`(dart:io)本身沒有 setter,測試主機(macOS/Linux CI)也
// 永遠不會是 iOS,無法直接讓「成功匯入」路徑跑起來——因此
// [LegacyPrefsImporter] 新增了建構子參數 `isIOSCheck`(預設就是真正的
// `Platform.isIOS`),測試用它注入固定值,跟 [CoreDataImporter] 可覆寫
// directoryProvider 是同一套模式,不是額外重構匯入邏輯本身。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/migration/legacy_prefs_importer.dart';

const _channel = MethodChannel('com.mikelin.workitout/legacy_prefs');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  void mockChannel(Map<String, dynamic>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => handler(call));
  }

  test('GlobalSettingsJson blob 優先於同名的個別 key', () async {
    mockChannel((call) {
      expect(call.method, 'getLegacyPreferences');
      return {
        'currentUserId': 'user-1',
        'globalSettingsJson': '{"weightUnit":"kg","theme":"dark"}',
        // 個別 key 跟 blob 內容刻意不同,驗證 blob 贏。
        'weightUnit': 'lb',
        'theme': 'light',
      };
    });

    final importer = const LegacyPrefsImporter(isIOSCheck: _alwaysIOS);
    final result = await importer.importIfNeeded();

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.skipped, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('legacy_weight_unit'), 'kg');
    expect(prefs.getString('legacy_theme'), 'dark');
    expect(prefs.getString('legacy_current_user_id'), 'user-1');
    expect(prefs.getBool(kLegacyPrefsImportCompletedKey), isTrue);
  });

  test('GlobalSettings 缺欄位時,改用個別 AppSettings/UserProfile key 補缺', () async {
    mockChannel(
      (call) => {
        // globalSettingsJson 沒有 oneRMFormula / enableHapticFeedback。
        'globalSettingsJson': '{"weightUnit":"kg"}',
        'oneRMFormula': 'epley',
        'enableHapticFeedback': true,
        'userName': '小明',
        'weeklyWorkoutGoal': 4,
      },
    );

    final importer = const LegacyPrefsImporter(isIOSCheck: _alwaysIOS);
    final result = await importer.importIfNeeded();

    expect(result.success, isTrue, reason: result.errorMessage);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('legacy_one_rm_formula'), 'epley');
    expect(prefs.getBool('legacy_enable_haptic_feedback'), isTrue);
    expect(prefs.getString('legacy_user_name'), '小明');
    expect(prefs.getInt('legacy_weekly_workout_goal'), 4);
  });

  test('已標記完成旗標時直接 skip,完全不呼叫 channel', () async {
    SharedPreferences.setMockInitialValues({
      kLegacyPrefsImportCompletedKey: true,
    });
    var channelCalled = false;
    mockChannel((call) {
      channelCalled = true;
      return {};
    });

    final importer = const LegacyPrefsImporter(isIOSCheck: _alwaysIOS);
    final result = await importer.importIfNeeded();

    expect(result.skipped, isTrue);
    expect(result.success, isTrue);
    expect(channelCalled, isFalse);
  });

  test('非 iOS 平台直接 skip,不呼叫 channel(也不寫入完成旗標)', () async {
    var channelCalled = false;
    mockChannel((call) {
      channelCalled = true;
      return {};
    });

    final importer = const LegacyPrefsImporter(isIOSCheck: _neverIOS);
    final result = await importer.importIfNeeded();

    expect(result.skipped, isTrue);
    expect(result.success, isTrue);
    expect(channelCalled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kLegacyPrefsImportCompletedKey), isNull);
  });

  test('刻意不搬的清單(登入身分 / 隱私同意 / 內部狀態機旗標)即使原生端回傳也不寫入', () async {
    mockChannel(
      (call) => {
        'globalSettingsJson': '{"weightUnit":"kg"}',
        // spec 3.2 節「不建議遷移」:登入身分留給 Flutter 版重新登入。
        'appleIDUserID': 'apple-user-id',
        'appleIDName': 'Mike',
        'appleIDEmail': 'mike@example.com',
        // 隱私同意旗標:要求使用者在 Flutter 版重新確認。
        'privacyPolicyAccepted': true,
        'hasAgreedToPrivacy': true,
        // 舊 App 內部狀態機 / 分析資料,非使用者資產。
        'coreDataMigrationCompleted': true,
        'coreDataModelVersion': 3,
        'defaultDataInitialized': true,
        'forceResetCoreData': false,
        'analyticsUserId': 'abc',
        'cloudKitZoneId': 'zone-1',
      },
    );

    final importer = const LegacyPrefsImporter(isIOSCheck: _alwaysIOS);
    final result = await importer.importIfNeeded();

    expect(result.success, isTrue, reason: result.errorMessage);
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    expect(keys.any((k) => k.toLowerCase().contains('apple')), isFalse);
    expect(keys.any((k) => k.toLowerCase().contains('privacy')), isFalse);
    expect(keys.any((k) => k.toLowerCase().contains('coredata')), isFalse);
    expect(keys.any((k) => k.toLowerCase().contains('analytics')), isFalse);
    expect(keys.any((k) => k.toLowerCase().contains('cloudkit')), isFalse);
  });

  test('原生端回傳 null/空 map 時視為無舊值,標記完成但不算錯誤', () async {
    mockChannel((call) => null);

    final importer = const LegacyPrefsImporter(isIOSCheck: _alwaysIOS);
    final result = await importer.importIfNeeded();

    expect(result.success, isTrue);
    expect(result.skipped, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kLegacyPrefsImportCompletedKey), isTrue);
  });

  test('冪等:第二次呼叫直接 skip', () async {
    mockChannel((call) => {'globalSettingsJson': '{"weightUnit":"kg"}'});

    final importer = const LegacyPrefsImporter(isIOSCheck: _alwaysIOS);
    final first = await importer.importIfNeeded();
    final second = await importer.importIfNeeded();

    expect(first.skipped, isFalse);
    expect(second.skipped, isTrue);
  });

  test('MethodChannel 丟 PlatformException → success=false,不寫完成旗標,'
      '失敗原因寫進 ImportLog(跟 CoreDataImporter 共用同一套 log,不是只靠'
      'debugPrint)', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      throw PlatformException(code: 'ERROR', message: 'boom');
    });

    final logDir =
        await Directory.systemTemp.createTemp('legacy_prefs_log_test_');
    addTearDown(() {
      if (logDir.existsSync()) {
        logDir.deleteSync(recursive: true);
      }
    });

    final importer = LegacyPrefsImporter(
      isIOSCheck: _alwaysIOS,
      supportDirectoryProvider: () async => logDir,
    );
    final result = await importer.importIfNeeded();

    expect(result.success, isFalse);
    expect(result.errorMessage, contains('boom'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kLegacyPrefsImportCompletedKey), isNull);

    final logFile = File(p.join(logDir.path, 'logs', 'import.log'));
    expect(logFile.existsSync(), isTrue);
    expect(logFile.readAsStringSync(), contains('boom'));
  });
}

bool _alwaysIOS() => true;
bool _neverIOS() => false;
