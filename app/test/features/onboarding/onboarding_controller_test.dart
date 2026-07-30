// OnboardingController.complete() seam 測試,對照 iOS
// `OnboardingState.complete()` 的行為:
// - 不論體重欄位有沒有效,complete() 都會確保有一筆 Users row——Users row
//   跟體重是否有效是兩件獨立的事(見 onboarding_controller.dart 開頭註解)。
// - 有效體重才另外寫入 user_current_weight + 建立初始 BodyWeight;體重無效
//   (例如透過「跳過教學」在還沒填體重時就完成)一樣能完成 Onboarding,只是
//   不建體重資料——這是刻意對齊 iOS 的寬鬆規則。
// - 完成後一定會標記 has_completed_onboarding = true。
// - 找不到登入身分對應的既有 row 時:只有「這台裝置有 CoreData 匯入血緣」
//   (coredata_import_completed == true)才沿用表裡既有的第一筆;沒有這個
//   血緣時一律用登入身分新建一筆,即使表裡已經有別人的資料——避免換一個
//   帳號登入時吃到上一個人的資料。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/migration/coredata_importer_result.dart'
    show kCoreDataImportCompletedKey;
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_controller.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';

import '../../data/test_helpers.dart';

const _loggedInUserId = 'apple-user-onboarding-test';

Future<ProviderContainer> _container({
  bool seedExistingUser = false,
  bool coreDataImportCompleted = false,
}) async {
  SharedPreferences.setMockInitialValues({
    kAppleUserIdKey: _loggedInUserId,
    kAppleUserNameKey: 'Onboarding Tester',
    kAppleUserEmailKey: 'onboarding-tester@example.com',
    if (coreDataImportCompleted) kCoreDataImportCompletedKey: true,
  });
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  if (seedExistingUser) {
    await seedTestUser(db, id: 'legacy-imported-user');
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
  group('complete() 有有效體重', () {
    test('寫入所有 prefs 欄位、建 Users row、建初始 BodyWeight、標記完成', () async {
      final container = await _container();
      final notifier = container.read(onboardingControllerProvider.notifier);

      notifier.setWeightText('70.5');
      notifier.setHeightText('175');
      notifier.setGender('男性');
      notifier.setAgeText('30');
      notifier.setTargetWeightText('65');
      notifier.setWeeklyGoal(5);

      await notifier.complete();

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getDouble(kUserCurrentWeightKey), 70.5);
      expect(prefs.getDouble(kUserHeightKey), 175);
      expect(prefs.getString(kUserGenderKey), '男性');
      expect(prefs.getInt(kUserAgeKey), 30);
      expect(prefs.getDouble(kUserTargetWeightKey), 65);
      expect(prefs.getInt(kWeeklyWorkoutGoalKey), 5);
      expect(container.read(onboardingStatusProvider), isTrue);

      final db = container.read(appDatabaseProvider);
      final users = await db.select(db.users).get();
      expect(users, hasLength(1));
      expect(users.single.id, _loggedInUserId);

      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights, hasLength(1));
      expect(bodyWeights.single.weight, 70.5);
      expect(bodyWeights.single.userId, _loggedInUserId);
    });

    test('lb 單位輸入時,換算成 kg 才寫入(對齊 iOS WeightFormatter)', () async {
      final container = await _container();
      final notifier = container.read(onboardingControllerProvider.notifier);

      notifier.setWeightUnit(OnboardingWeightUnit.lb);
      notifier.setWeightText('154'); // ~= 69.85 kg

      await notifier.complete();

      final prefs = container.read(sharedPreferencesProvider);
      final storedKg = prefs.getDouble(kUserCurrentWeightKey);
      expect(storedKg, closeTo(69.85, 0.05));
    });

    test('Drift Users 表已有 CoreData 匯入血緣資料時,沿用既有 row,不新建第二筆', () async {
      final container = await _container(seedExistingUser: true, coreDataImportCompleted: true);
      final notifier = container.read(onboardingControllerProvider.notifier);
      notifier.setWeightText('80');

      await notifier.complete();

      final db = container.read(appDatabaseProvider);
      final users = await db.select(db.users).get();
      expect(users, hasLength(1));
      expect(users.single.id, 'legacy-imported-user');

      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights.single.userId, 'legacy-imported-user');
    });

    test('Drift Users 表已有資料但沒有 CoreData 匯入血緣時,不沿用,改用登入身分新建一筆', () async {
      final container = await _container(seedExistingUser: true);
      final notifier = container.read(onboardingControllerProvider.notifier);
      notifier.setWeightText('80');

      await notifier.complete();

      final db = container.read(appDatabaseProvider);
      final users = await db.select(db.users).get();
      expect(users, hasLength(2));
      expect(users.map((u) => u.id), containsAll(['legacy-imported-user', _loggedInUserId]));

      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights.single.userId, _loggedInUserId);
    });
  });

  group('complete() 體重欄位無效(對等「跳過教學」在填體重前按下)', () {
    test('仍然完成 Onboarding、建 Users row,但不建 BodyWeight', () async {
      final container = await _container();
      final notifier = container.read(onboardingControllerProvider.notifier);
      // weightText 維持預設空字串,不呼叫 setWeightText。

      await notifier.complete();

      expect(container.read(onboardingStatusProvider), isTrue);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kUserCurrentWeightKey), isFalse);

      final db = container.read(appDatabaseProvider);
      final users = await db.select(db.users).get();
      expect(users, hasLength(1));
      expect(users.single.id, _loggedInUserId);

      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights, isEmpty);
    });
  });

  group('OnboardingDraft.isWeightValid', () {
    test('空字串或無法解析的字串視為無效', () {
      const draft = OnboardingDraft();
      expect(draft.isWeightValid, isFalse);
      expect(draft.copyWith(weightText: 'abc').isWeightValid, isFalse);
    });

    test('可解析成 double 的字串視為有效', () {
      const draft = OnboardingDraft();
      expect(draft.copyWith(weightText: '70').isWeightValid, isTrue);
      expect(draft.copyWith(weightText: '70.5').isWeightValid, isTrue);
    });
  });
}
