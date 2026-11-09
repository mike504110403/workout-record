import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, SupabaseClient;

import 'app.dart';
import 'data/migration/coredata_importer.dart';
import 'data/migration/legacy_prefs_importer.dart';
import 'data/providers.dart';
import 'data/supabase_client.dart';
import 'features/auth/session_controller.dart';
import 'features/cloud_upload/cloud_upload_controller.dart';
import 'features/auth/shared_preferences_provider.dart';
import 'features/onboarding/onboarding_status.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SessionController / OnboardingController / PrivacyConsentController 都要
  // 同步讀 SharedPreferences,先在這裡 await 拿到實例,用 override 塞進
  // ProviderContainer(見 features/auth/shared_preferences_provider.dart)。
  final prefs = await SharedPreferences.getInstance();

  // 首啟舊 CoreData 資料 / UserDefaults 偏好無縫匯入(見
  // docs/COREDATA_MIGRATION_SPEC.md)。用同一個 ProviderContainer 建立
  // AppDatabase,匯入完成後原封不動交給 runApp,避免開出第二個資料庫連線。
  // 任何失敗都不能讓 App 崩潰:記錄後照常進 App,完成旗標不會被寫入,
  // 下次啟動會自動重試。
  // 資料層:非 USE_MOCK 且 SUPABASE_URL/SUPABASE_ANON_KEY 有給 → 初始化 Supabase,
  // repository 改走 Supabase 實作;否則(USE_MOCK 或未設定)維持本機 Drift
  // (見 data/supabase_client.dart、data/providers.dart)。
  SupabaseClient? supabaseClient;
  if (kUseSupabase) {
    await initSupabase();
    supabaseClient = Supabase.instance.client;
  } else if (!kUseMock) {
    debugPrint(
      'SUPABASE_URL / SUPABASE_ANON_KEY 未設定,資料層退回本機 Drift'
      '(要連 Supabase 請帶 --dart-define;純本機請帶 USE_MOCK=true)。',
    );
  }

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (supabaseClient != null) supabaseClientProvider.overrideWithValue(supabaseClient),
    ],
  );
  final db = container.read(appDatabaseProvider);

  try {
    final prefsResult = await const LegacyPrefsImporter().importIfNeeded();
    if (!prefsResult.success) {
      debugPrint('legacy prefs import failed: ${prefsResult.errorMessage}');
    }
  } catch (e, st) {
    debugPrint('legacy prefs import crashed: $e\n$st');
  }

  // 舊 CoreData 照舊匯入本機 Drift(Supabase 模式也一樣)。登入後把本機資料
  // 一次性上傳到 Supabase 見下方 startCloudUploadTrigger。
  try {
    final importResult = await const CoreDataImporter().importIfNeeded(db);
    if (!importResult.success) {
      debugPrint('CoreData import failed: ${importResult.errorMessage}');
    }
  } catch (e, st) {
    debugPrint('CoreData import crashed: $e\n$st');
  }

  // 升級用戶(有舊 CoreData 匯入紀錄且 Drift Users 表非空)自動跳過
  // Onboarding,見 features/onboarding/onboarding_status.dart。
  try {
    await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);
  } catch (e, st) {
    debugPrint('onboarding upgrade-skip check crashed: $e\n$st');
  }

  // 雲端模式:恢復 Supabase session 後,Onboarding 已完成的登入者確保有
  // users 列(見 SessionController.ensureCloudUserRowOnRestore);失敗不擋啟動。
  try {
    await container.read(sessionControllerProvider.notifier).ensureCloudUserRowOnRestore();
  } catch (e, st) {
    debugPrint('cloud users row ensure on restore failed: $e\n$st');
  }

  // 雲端模式:恢復 session 時與之後登入成功時,把本機 Drift 舊資料一次性上傳到
  // Supabase(背景執行不擋啟動;狀態見設定頁 CloudUploadStatusTile)。
  startCloudUploadTrigger(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const WorkItOutApp(),
    ),
  );
}
