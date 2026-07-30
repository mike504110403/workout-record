// Onboarding 完成旗標 + 升級用戶自動跳過邏輯。
//
// 「升級用戶跳過」(brief 第 6 點):舊 App 使用者透過 CoreData 匯入拿到一筆
// 以上的訓練歷史,不該被強迫重跑新人 Onboarding 精靈——首次啟動時若
// `coredata_import_completed == true` 且 Drift Users 表非空,直接把
// `has_completed_onboarding` 標記為 true。這個檢查在 main.dart 用
// [autoCompleteOnboardingForUpgradedUsersIfNeeded] 跑一次,跑完之後
// Onboarding 完成與否單純看這個旗標,router 不需要碰 DB。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/migration/coredata_importer_result.dart' show kCoreDataImportCompletedKey;
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

/// App 啟動時跑一次:升級用戶(有舊 CoreData 匯入紀錄且 Drift Users 表非空)
/// 自動視為已完成 Onboarding。已完成旗標存在就不重複檢查。
Future<void> autoCompleteOnboardingForUpgradedUsersIfNeeded(
  ProviderContainer container,
) async {
  if (container.read(onboardingStatusProvider)) return;

  final prefs = container.read(sharedPreferencesProvider);
  final coreDataImportCompleted = prefs.getBool(kCoreDataImportCompletedKey) ?? false;
  if (!coreDataImportCompleted) return;

  final userRepo = container.read(userRepositoryProvider);
  final anyUser = await userRepo.getFirst();
  if (anyUser == null) return;

  await container.read(onboardingStatusProvider.notifier).markCompleted();
}
