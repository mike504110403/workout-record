// 目前登入者 userId 的解析(原散在 7 個 controller 的 `_resolveUserId` 複本)。
//
// 兩種語義刻意分開,不合併:
// - [resolveSessionUserId]:只認 session 的登入者,且 users 表查得到才算。
// - [resolveSessionUserIdWithImportFallback]:查不到登入者時,退回舊 CoreData
//   匯入時建立的使用者([kCoreDataImportedUserIdKey]),讓目標/力量/PR 頁在
//   匯入資料歸屬尚未對上 session 時仍顯示得出舊資料。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/migration/coredata_importer_result.dart' show kCoreDataImportedUserIdKey;
import '../../data/providers.dart' show userRepositoryProvider;
import 'session_controller.dart';
import 'shared_preferences_provider.dart';

Future<String?> resolveSessionUserId(Ref ref) async {
  final sessionUserId = ref.read(sessionControllerProvider).appleUserId;
  if (sessionUserId == null || sessionUserId.isEmpty) return null;
  final user = await ref.read(userRepositoryProvider).getById(sessionUserId);
  return user?.id;
}

Future<String?> resolveSessionUserIdWithImportFallback(Ref ref) async {
  final userRepo = ref.read(userRepositoryProvider);

  final sessionUserId = ref.read(sessionControllerProvider).appleUserId;
  if (sessionUserId != null && sessionUserId.isNotEmpty) {
    final existing = await userRepo.getById(sessionUserId);
    if (existing != null) return existing.id;
  }

  final importedUserId = ref.read(sharedPreferencesProvider).getString(kCoreDataImportedUserIdKey);
  if (importedUserId != null && importedUserId.isNotEmpty) {
    final imported = await userRepo.getById(importedUserId);
    if (imported != null) return imported.id;
  }

  return null;
}
