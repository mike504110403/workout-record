// OnboardingStatusController + 升級用戶自動跳過(brief 第 6 點)的 seam
// 測試:
// - build() 從 SharedPreferences 讀 has_completed_onboarding。
// - markCompleted() 寫回 SharedPreferences 並更新 state。
// - autoCompleteOnboardingForUpgradedUsersIfNeeded:coredata_imported_user_id
//   存在且該 id 對應的 Users row 存在時,自動標記完成;任一條件不成立則不
//   動作。刻意不用 coredata_import_completed(血緣誤判修正,見 review
//   2026-07-30)——那個旗標「舊檔不存在」(全新安裝 / Android)時也會設
//   true,不能拿來判斷血緣,下面「全新安裝」情境的 fixture 特意帶
//   coredata_import_completed: true(對齊真機現實)驗證這一點。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/migration/coredata_importer_result.dart'
    show kCoreDataImportCompletedKey, kCoreDataImportedUserIdKey;
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
    test('有 coredata_imported_user_id 且該 id 對應的 Users row 存在 → 自動標記完成', () async {
      final container = await _container(
        prefsValues: {kCoreDataImportedUserIdKey: testUserId},
        seedUser: true, // seedTestUser 預設 id 就是 testUserId
      );

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);

      expect(container.read(onboardingStatusProvider), isTrue);
    });

    test('沒有 coredata_imported_user_id → 不自動標記(即使 Users 表非空)', () async {
      final container = await _container(seedUser: true);

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);

      expect(container.read(onboardingStatusProvider), isFalse);
    });

    test(
        '全新安裝(舊檔不存在,coredata_import_completed 仍會被設為 true,但沒有 '
        'coredata_imported_user_id)→ 不沿用、不自動跳過', () async {
      final container = await _container(
        prefsValues: {kCoreDataImportCompletedKey: true},
      );

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);

      expect(container.read(onboardingStatusProvider), isFalse);
    });

    test('coredata_imported_user_id 存在但該 id 的 Users row 已不存在 → 不自動標記', () async {
      final container = await _container(
        prefsValues: {kCoreDataImportedUserIdKey: 'deleted-user-id'},
        seedUser: true, // 表裡有別的使用者,但不是血緣指向的那一筆
      );

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);

      expect(container.read(onboardingStatusProvider), isFalse);
    });

    test('已經標記完成時直接略過(不重複查 DB)', () async {
      final container = await _container(
        prefsValues: {
          kCoreDataImportedUserIdKey: testUserId,
          kHasCompletedOnboardingKey: true,
        },
      );

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);

      expect(container.read(onboardingStatusProvider), isTrue);
    });
  });
}
