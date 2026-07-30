// OnboardingStatusController + 升級用戶自動跳過(brief 第 6 點)的 seam
// 測試:
// - build() 從 SharedPreferences 讀 has_completed_onboarding。
// - markCompleted() 寫回 SharedPreferences 並更新 state。
// - autoCompleteOnboardingForUpgradedUsersIfNeeded:coredata_import_completed
//   為 true 且 Drift Users 表非空時,自動標記完成;任一條件不成立則不動作。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/migration/coredata_importer_result.dart'
    show kCoreDataImportCompletedKey;
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';

import '../../data/test_helpers.dart';

Future<ProviderContainer> _container({
  Map<String, Object> prefsValues = const {},
  bool seedUser = false,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  if (seedUser) {
    await seedTestUser(db);
  }

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return container;
}

void main() {
  group('OnboardingStatusController', () {
    test('build():SharedPreferences 沒有旗標時預設 false', () async {
      final container = await _container();
      expect(container.read(onboardingStatusProvider), isFalse);
    });

    test('build():SharedPreferences 已有旗標時還原該值', () async {
      final container = await _container(
        prefsValues: {kHasCompletedOnboardingKey: true},
      );
      expect(container.read(onboardingStatusProvider), isTrue);
    });

    test('markCompleted():寫入 SharedPreferences 並更新 state', () async {
      final container = await _container();
      await container.read(onboardingStatusProvider.notifier).markCompleted();

      expect(container.read(onboardingStatusProvider), isTrue);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getBool(kHasCompletedOnboardingKey), isTrue);
    });
  });

  group('autoCompleteOnboardingForUpgradedUsersIfNeeded', () {
    test('coredata 匯入完成且 Users 表非空 → 自動標記完成', () async {
      final container = await _container(
        prefsValues: {kCoreDataImportCompletedKey: true},
        seedUser: true,
      );

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);

      expect(container.read(onboardingStatusProvider), isTrue);
    });

    test('coredata 未匯入完成 → 不自動標記', () async {
      final container = await _container(seedUser: true);

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);

      expect(container.read(onboardingStatusProvider), isFalse);
    });

    test('coredata 匯入完成但 Users 表是空的(全新安裝)→ 不自動標記', () async {
      final container = await _container(
        prefsValues: {kCoreDataImportCompletedKey: true},
      );

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);

      expect(container.read(onboardingStatusProvider), isFalse);
    });

    test('已經標記完成時直接略過(不重複查 DB)', () async {
      final container = await _container(
        prefsValues: {
          kCoreDataImportCompletedKey: true,
          kHasCompletedOnboardingKey: true,
        },
      );

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);

      expect(container.read(onboardingStatusProvider), isTrue);
    });
  });
}
