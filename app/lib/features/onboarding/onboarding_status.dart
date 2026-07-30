// Onboarding 完成旗標 + 升級用戶自動跳過邏輯。
//
// 「升級用戶跳過」(brief 第 6 點):舊 App 使用者透過 CoreData 匯入拿到一筆
// 以上的訓練歷史,不該被強迫重跑新人 Onboarding 精靈——首次啟動時若
// `coredata_imported_user_id` 存在且該 id 對應的 Drift Users row 存在,
// 直接把 `has_completed_onboarding` 標記為 true。這個檢查在 main.dart 用
// [autoCompleteOnboardingForUpgradedUsersIfNeeded] 跑一次,跑完之後
// Onboarding 完成與否單純看這個旗標,router 不需要碰 DB。
//
// 刻意不用 `coredata_import_completed`(血緣誤判修正,見 review
// 2026-07-30)——那個旗標「舊檔不存在」時也會設 true(全新安裝 / Android
// 天然沒有舊檔),不能拿來判斷「這台裝置有沒有真的匯入過舊資料」,見
// coredata_importer_result.dart 的欄位註解。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/migration/coredata_importer_result.dart' show kCoreDataImportedUserIdKey;
import '../../data/providers.dart';
import '../auth/shared_preferences_provider.dart';

const kHasCompletedOnboardingKey = 'has_completed_onboarding';

class OnboardingStatusController extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(kHasCompletedOnboardingKey) ?? false;
  }

  Future<void> markCompleted() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(kHasCompletedOnboardingKey, true);
    state = true;
  }
}

final onboardingStatusProvider = NotifierProvider<OnboardingStatusController, bool>(
  OnboardingStatusController.new,
);

/// App 啟動時跑一次:升級用戶(有 CoreData 匯入血緣紀錄,且該匯入落地的
/// 使用者 row 確實存在)自動視為已完成 Onboarding。已完成旗標存在就不重複
/// 檢查。
Future<void> autoCompleteOnboardingForUpgradedUsersIfNeeded(
  ProviderContainer container,
) async {
  if (container.read(onboardingStatusProvider)) return;

  final prefs = container.read(sharedPreferencesProvider);
  final importedUserId = prefs.getString(kCoreDataImportedUserIdKey);
  if (importedUserId == null || importedUserId.isEmpty) return;

  final userRepo = container.read(userRepositoryProvider);
  final importedUser = await userRepo.getById(importedUserId);
  if (importedUser == null) return;

  await container.read(onboardingStatusProvider.notifier).markCompleted();
}
