import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/migration/coredata_importer.dart';
import 'data/migration/legacy_prefs_importer.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 首啟舊 CoreData 資料 / UserDefaults 偏好無縫匯入(見
  // docs/COREDATA_MIGRATION_SPEC.md)。用同一個 ProviderContainer 建立
  // AppDatabase,匯入完成後原封不動交給 runApp,避免開出第二個資料庫連線。
  // 任何失敗都不能讓 App 崩潰:記錄後照常進 App,完成旗標不會被寫入,
  // 下次啟動會自動重試。
  final container = ProviderContainer();
  final db = container.read(appDatabaseProvider);

  try {
    final prefsResult = await const LegacyPrefsImporter().importIfNeeded();
    if (!prefsResult.success) {
      debugPrint('legacy prefs import failed: ${prefsResult.errorMessage}');
    }
  } catch (e, st) {
    debugPrint('legacy prefs import crashed: $e\n$st');
  }

  try {
    final importResult = await const CoreDataImporter().importIfNeeded(db);
    if (!importResult.success) {
      debugPrint('CoreData import failed: ${importResult.errorMessage}');
    }
  } catch (e, st) {
    debugPrint('CoreData import crashed: $e\n$st');
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const WorkItOutApp(),
    ),
  );
}
