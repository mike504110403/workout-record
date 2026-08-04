// SessionController seam:build() 從 SharedPreferences 讀初始狀態、
// signInTest()/signOut() 寫回 SharedPreferences 並更新 state、
// signInWithApple() 在沒有原生 Apple 登入管道(測試環境)時要優雅失敗而不是
// 讓例外往外炸。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/db/app_database.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_controller.dart'
    show kUserCurrentWeightKey, kUserGenderKey;
import 'package:workout_record/features/onboarding/onboarding_status.dart';

import '../../data/test_helpers.dart';

Future<ProviderContainer> _containerWithPrefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

/// 帳號隔離測試用:除了 mock prefs,還要疊一顆真的 in-memory Drift DB(換帳號
/// 衝突確認清除的流程要真的清 Drift,不能只驗 prefs)。呼叫端負責在需要時
/// 自行 seed 資料;這裡只負責開庫、掛 override、收尾關庫。
Future<ProviderContainer> _containerWithPrefsAndDb(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
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
  return container;
}

void main() {
  group('build', () {
    test('SharedPreferences 沒有任何 apple_user_* key 時,isLoggedIn 為 false', () async {
      final container = await _containerWithPrefs({});
      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.appleUserId, isNull);
    });

    test('SharedPreferences 已有 apple_user_id 時,直接以此還原成已登入狀態', () async {
      final container = await _containerWithPrefs({
        kAppleUserIdKey: 'existing-user',
        kAppleUserNameKey: 'Existing User',
        kAppleUserEmailKey: 'existing@example.com',
      });
      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isTrue);
      expect(state.appleUserName, 'Existing User');
      expect(state.appleUserEmail, 'existing@example.com');
    });
  });

  group('signInTest', () {
    test('首次測試登入時產生 UUID 身分,寫入 SharedPreferences 並更新 state', () async {
      final container = await _containerWithPrefs({});
      await container.read(sessionControllerProvider.notifier).signInTest();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isTrue);
      expect(state.appleUserId, isNotNull);
      expect(state.appleUserId, isNotEmpty);
      expect(state.appleUserName, kTestLoginUserName);
      expect(state.isLoading, isFalse);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kAppleUserIdKey), state.appleUserId);
      expect(prefs.getString(kTestLoginUserIdPrefsKey), state.appleUserId);
    });

    test('第二次測試登入沿用同一個 UUID 身分,不重新生成', () async {
      final container = await _containerWithPrefs({});
      final notifier = container.read(sessionControllerProvider.notifier);

      await notifier.signInTest();
      final firstId = container.read(sessionControllerProvider).appleUserId;

      await notifier.signOut();
      await notifier.signInTest();
      final secondId = container.read(sessionControllerProvider).appleUserId;

      expect(secondId, firstId);
    });
  });

  group('signOut', () {
    test('清掉三個 session key、顯式列舉的 Onboarding 個資 key 與完成旗標', () async {
      final container = await _containerWithPrefs({
        kAppleUserIdKey: 'existing-user',
        kAppleUserNameKey: 'Existing User',
        kAppleUserEmailKey: 'existing@example.com',
        kHasCompletedOnboardingKey: true,
        'user_gender': '男性',
        'user_current_weight': 70.0,
      });

      await container.read(sessionControllerProvider.notifier).signOut();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.appleUserId, isNull);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kAppleUserIdKey), isFalse);
      expect(prefs.containsKey('user_gender'), isFalse);
      expect(prefs.containsKey('user_current_weight'), isFalse);
      expect(prefs.containsKey(kHasCompletedOnboardingKey), isFalse);
    });

    test('顯式契約:不在 kOnboardingPersonalDataKeys 清單內的 user_ 前綴 key 不會被清除', () async {
      // 對照舊行為(掃描所有 user_ 前綴 key)——改成顯式列舉清單後,清單外的
      // key(即使剛好也是 user_ 前綴)不再被隱式掃到,見
      // onboarding_controller.dart 的 kOnboardingPersonalDataKeys 註解。
      final container = await _containerWithPrefs({
        kAppleUserIdKey: 'existing-user',
        'user_not_an_onboarding_key': 'should survive',
      });

      await container.read(sessionControllerProvider.notifier).signOut();

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('user_not_an_onboarding_key'), 'should survive');
    });

    test('隱私同意三個 key 是裝置層級,登出不清', () async {
      final container = await _containerWithPrefs({
        kAppleUserIdKey: 'existing-user',
        'has_agreed_to_analytics': true,
        'has_agreed_to_privacy': true,
        'privacy_consent_date': 1234567890,
      });

      await container.read(sessionControllerProvider.notifier).signOut();

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getBool('has_agreed_to_analytics'), isTrue);
      expect(prefs.getBool('has_agreed_to_privacy'), isTrue);
      expect(prefs.getInt('privacy_consent_date'), 1234567890);
    });

    test('測試登入 UUID(test_login_user_id)是裝置層級,登出不清', () async {
      final container = await _containerWithPrefs({});
      final notifier = container.read(sessionControllerProvider.notifier);
      await notifier.signInTest();
      final testId = container.read(sessionControllerProvider).appleUserId;

      await notifier.signOut();

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kTestLoginUserIdPrefsKey), testId);
    });
  });

  group('signInWithApple', () {
    test('測試環境沒有原生 Apple 登入管道時,優雅失敗並記錄一般化錯誤訊息', () async {
      final container = await _containerWithPrefs({});
      await container.read(sessionControllerProvider.notifier).signInWithApple();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNotNull);
    });
  });

  group('clearError', () {
    test('清掉目前的錯誤訊息', () async {
      final container = await _containerWithPrefs({});
      final notifier = container.read(sessionControllerProvider.notifier);
      await notifier.signInWithApple();
      expect(container.read(sessionControllerProvider).errorMessage, isNotNull);

      notifier.clearError();

      expect(container.read(sessionControllerProvider).errorMessage, isNull);
    });
  });

  // 帳號隔離(見 .claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md):
  // 本機 Drift 永遠只屬於一個帳號,owner 記在 kLocalDataOwnerUserIdKey。
  group('帳號隔離 — owner 認領', () {
    test('無 owner 時,首次登入直接認領——owner key 寫入為這次登入的身分', () async {
      final container = await _containerWithPrefsAndDb({});
      final outcome = await container.read(sessionControllerProvider.notifier).signInTest();

      expect(outcome, isA<LoginSuccess>());
      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isTrue);
      expect(state.ownerConflict, isNull);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), state.appleUserId);
    });

    test('owner 就是自己時,無 conflict、照常完成登入、Drift 資料不動', () async {
      final container = await _containerWithPrefsAndDb({});
      final notifier = container.read(sessionControllerProvider.notifier);

      final first = await notifier.signInTest();
      expect(first, isA<LoginSuccess>());
      final owner = container.read(sharedPreferencesProvider).getString(kLocalDataOwnerUserIdKey);

      final db = container.read(appDatabaseProvider);
      await seedTestUser(db, id: owner!);
      final now = DateTime.now();
      await db.into(db.bodyWeights).insert(
            BodyWeightsCompanion.insert(
              id: 'bw1',
              userId: owner,
              measuredAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      // test_login_user_id 是裝置層級 key,登出不清,重登會沿用同一個身分
      // ——對應「同帳號重登」情境。
      await notifier.signOut();
      final second = await notifier.signInTest();

      expect(second, isA<LoginSuccess>());
      final state = container.read(sessionControllerProvider);
      expect(state.appleUserId, owner);
      expect(state.ownerConflict, isNull);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), owner);

      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights, hasLength(1));
    });
  });

  group('帳號隔離 — owner 衝突', () {
    test('owner 是別人時,回傳 conflict,不清資料、不認領、不建立 session', () async {
      const oldOwner = 'owner-a';
      final container = await _containerWithPrefsAndDb({
        kLocalDataOwnerUserIdKey: oldOwner,
      });
      final db = container.read(appDatabaseProvider);
      await seedTestUser(db, id: oldOwner);
      final now = DateTime.now();
      await db.into(db.bodyWeights).insert(
            BodyWeightsCompanion.insert(
              id: 'bw1',
              userId: oldOwner,
              measuredAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      // signInTest() 首次呼叫會生成一個新 UUID 當測試登入身分,必定不等於
      // oldOwner,對應「異帳號登入」情境。
      final outcome = await container.read(sessionControllerProvider.notifier).signInTest();

      expect(outcome, isA<LoginOwnerConflict>());
      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.ownerConflict, isNotNull);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), oldOwner);

      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights, hasLength(1));
    });

    test(
        '確認清除:多表清空(Workouts/WorkoutExercises/WorkoutSets/BodyWeights/Users)、'
        'onboarding 個資與完成旗標消失、隱私三 key 與裝置層級測試登入 id 仍在、'
        'owner 換成新帳號、session 建立', () async {
      const oldOwner = 'owner-a';
      const incomingUserId = 'device-test-uuid';
      final container = await _containerWithPrefsAndDb({
        kLocalDataOwnerUserIdKey: oldOwner,
        kTestLoginUserIdPrefsKey: incomingUserId,
        kUserGenderKey: '男性',
        kUserCurrentWeightKey: 70.0,
        kHasCompletedOnboardingKey: true,
        'has_agreed_to_analytics': true,
        'has_agreed_to_privacy': true,
        'privacy_consent_date': 1234567890,
      });

      final db = container.read(appDatabaseProvider);
      await seedTestUser(db, id: oldOwner);
      final exerciseId = (await db.select(db.exercises).get()).first.id;
      final now = DateTime.now();
      await db.into(db.workouts).insert(
            WorkoutsCompanion.insert(
              id: 'w1',
              userId: oldOwner,
              startedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.workoutExercises).insert(
            WorkoutExercisesCompanion.insert(
              id: 'we1',
              workoutId: 'w1',
              exerciseId: exerciseId,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.workoutSets).insert(
            WorkoutSetsCompanion.insert(
              id: 'ws1',
              workoutExerciseId: 'we1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.bodyWeights).insert(
            BodyWeightsCompanion.insert(
              id: 'bw1',
              userId: oldOwner,
              measuredAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final notifier = container.read(sessionControllerProvider.notifier);
      final conflictOutcome = await notifier.signInTest();
      expect(conflictOutcome, isA<LoginOwnerConflict>());

      final confirmOutcome = await notifier.confirmClearAndContinueLogin();
      expect(confirmOutcome, isA<LoginSuccess>());

      // 逐表斷言 = 0,參照物是直接 SELECT COUNT,不是清空方法的回傳值。
      expect(await db.select(db.workouts).get(), isEmpty);
      expect(await db.select(db.workoutExercises).get(), isEmpty);
      expect(await db.select(db.workoutSets).get(), isEmpty);
      expect(await db.select(db.bodyWeights).get(), isEmpty);
      expect(
        await (db.select(db.users)..where((t) => t.id.equals(oldOwner))).getSingleOrNull(),
        isNull,
      );

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kUserGenderKey), isFalse);
      expect(prefs.containsKey(kUserCurrentWeightKey), isFalse);
      expect(prefs.containsKey(kHasCompletedOnboardingKey), isFalse);
      expect(prefs.getBool('has_agreed_to_analytics'), isTrue);
      expect(prefs.getBool('has_agreed_to_privacy'), isTrue);
      expect(prefs.getInt('privacy_consent_date'), 1234567890);
      expect(prefs.getString(kTestLoginUserIdPrefsKey), incomingUserId);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), incomingUserId);

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isTrue);
      expect(state.appleUserId, incomingUserId);
      expect(state.ownerConflict, isNull);
    });

    test('取消:資料完好、owner 不變、不認領、不建立 session', () async {
      const oldOwner = 'owner-a';
      final container = await _containerWithPrefsAndDb({
        kLocalDataOwnerUserIdKey: oldOwner,
      });
      final db = container.read(appDatabaseProvider);
      await seedTestUser(db, id: oldOwner);
      final now = DateTime.now();
      await db.into(db.bodyWeights).insert(
            BodyWeightsCompanion.insert(
              id: 'bw1',
              userId: oldOwner,
              measuredAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final notifier = container.read(sessionControllerProvider.notifier);
      final conflictOutcome = await notifier.signInTest();
      expect(conflictOutcome, isA<LoginOwnerConflict>());

      notifier.cancelOwnerConflict();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.ownerConflict, isNull);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), oldOwner);

      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights, hasLength(1));
    });

    test('沒有待確認的 conflict 時呼叫 confirmClearAndContinueLogin() 是安全的 no-op', () async {
      final container = await _containerWithPrefsAndDb({});
      final notifier = container.read(sessionControllerProvider.notifier);

      final outcome = await notifier.confirmClearAndContinueLogin();

      expect(outcome, isA<LoginFailure>());
      expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
    });
  });

  group('帳號隔離 — signOut 不動 owner 與 Drift', () {
    test('signOut 不清 kLocalDataOwnerUserIdKey、不清 Drift 資料', () async {
      final container = await _containerWithPrefsAndDb({});
      final notifier = container.read(sessionControllerProvider.notifier);
      await notifier.signInTest();
      final owner = container.read(sharedPreferencesProvider).getString(kLocalDataOwnerUserIdKey);

      final db = container.read(appDatabaseProvider);
      await seedTestUser(db, id: owner!);
      final now = DateTime.now();
      await db.into(db.bodyWeights).insert(
            BodyWeightsCompanion.insert(
              id: 'bw1',
              userId: owner,
              measuredAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await notifier.signOut();

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), owner);

      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights, hasLength(1));
    });
  });
}
