// OnboardingController.complete() seam 測試,對照 iOS
// `OnboardingState.complete()` 的行為:
// - 不論體重欄位有沒有效,complete() 都會確保有一筆 Users row——Users row
//   跟體重是否有效是兩件獨立的事(見 onboarding_controller.dart 開頭註解)。
// - 有效體重且是「本次新建」的使用者 row 時,才另外寫入
//   user_current_weight + 建立初始 BodyWeight(重複初始體重回歸修正,見
//   review 2026-07-30);體重無效(例如透過「跳過教學」在還沒填體重時就
//   完成)一樣能完成 Onboarding,只是不建體重資料——這是刻意對齊 iOS 的
//   寬鬆規則。
// - 完成後一定會標記 has_completed_onboarding = true。
// - 找不到登入身分對應的既有 row 時:只有 prefs 存在
//   coredata_imported_user_id 且該 id 對應的 row 真的存在(這台裝置有明確
//   的 CoreData 匯入血緣)才沿用該 row;沒有這個血緣時一律用登入身分新建
//   一筆,即使表裡已經有別人的資料——避免換一個帳號登入時吃到上一個人的
//   資料。沿用既有 row 一律不算「新建」,不會再寫一筆初始體重。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/migration/coredata_importer_result.dart'
    show kCoreDataImportedUserIdKey;
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_controller.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';

import '../../data/test_helpers.dart';

const _loggedInUserId = 'apple-user-onboarding-test';

Future<ProviderContainer> _container({
  bool seedExistingUser = false,
  String? importedUserId,
}) async {
  final prefsValues = <String, Object>{
    kAppleUserIdKey: _loggedInUserId,
    kAppleUserNameKey: 'Onboarding Tester',
    kAppleUserEmailKey: 'onboarding-tester@example.com',
  };
  if (importedUserId != null) {
    prefsValues[kCoreDataImportedUserIdKey] = importedUserId;
  }
  SharedPreferences.setMockInitialValues(prefsValues);
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

    test('有 coredata_imported_user_id 且該 row 存在時,沿用既有 row,不新建第二筆、不寫初始體重',
        () async {
      final container =
          await _container(seedExistingUser: true, importedUserId: 'legacy-imported-user');
      final notifier = container.read(onboardingControllerProvider.notifier);
      notifier.setWeightText('80');

      await notifier.complete();

      final db = container.read(appDatabaseProvider);
      final users = await db.select(db.users).get();
      expect(users, hasLength(1));
      expect(users.single.id, 'legacy-imported-user');

      // 沿用既有 row(非新建)→ 不寫初始體重(重複初始體重回歸修正)。
      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights, isEmpty);
    });

    test('Drift Users 表已有資料但沒有 coredata_imported_user_id 時,不沿用,改用登入身分新建一筆並寫初始體重',
        () async {
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

    test('coredata_imported_user_id 存在但該 row 已不存在時,不沿用,改用登入身分新建一筆', () async {
      final container = await _container(seedExistingUser: true, importedUserId: 'ghost-id');
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

    test('同帳號登出→重登→再完成 Onboarding → BodyWeights 仍只有 1 筆(重複初始體重回歸修正)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = openTestDatabase();
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

      final session = container.read(sessionControllerProvider.notifier);
      final onboarding = container.read(onboardingControllerProvider.notifier);

      // 首次測試登入 + 完成 Onboarding:新建使用者,寫入初始體重。
      await session.signInTest();
      onboarding.setWeightText('70');
      await onboarding.complete();

      // 登出後,test_login_user_id 是裝置層級 key、不受 signOut 影響
      // (見 session_controller_test.dart),所以重新測試登入會沿用同一個
      // 帳號 id,對應到「同帳號重登」的情境。
      await session.signOut();
      await session.signInTest();
      onboarding.setWeightText('72');
      await onboarding.complete();

      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights, hasLength(1));
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
