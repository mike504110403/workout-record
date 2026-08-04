// SessionController seam:build() 從 SharedPreferences 讀初始狀態、
// signInTest()/signOut() 寫回 SharedPreferences 並更新 state、
// signInWithApple() 在沒有原生 Apple 登入管道(測試環境)時要優雅失敗而不是
// 讓例外往外炸。

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/db/app_database.dart';
import 'package:workout_record/data/migration/coredata_importer_result.dart';
import 'package:workout_record/data/migration/legacy_prefs_importer.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_controller.dart'
    show kUserCurrentWeightKey, kUserGenderKey;
import 'package:workout_record/features/onboarding/onboarding_status.dart';

import '../../data/test_helpers.dart';

/// 專給「確認清除時 DB 清空失敗」測試用的假 DB——只覆寫
/// [AppDatabase.resetForNewOwner] 讓它拋例外,其餘(onCreate/seedIfEmpty 等)
/// 完全是真正的 Drift 行為,不需要碰任何 native API 就能製造出「清空失敗」
/// 的情境。
class _ThrowingResetDb extends AppDatabase {
  _ThrowingResetDb() : super.forTesting(NativeDatabase.memory());

  @override
  Future<void> resetForNewOwner() async {
    throw Exception('boom: 模擬清空 DB 失敗');
  }
}

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

      // build() 已經把 onboardingStatusProvider 讀成 true(對應上面 mock 的
      // kHasCompletedOnboardingKey: true)——先讀一次讓它被實際初始化,才能
      // 驗證下面 signOut() 之後這個 provider 的記憶體值真的被 invalidate
      // 重新讀成 false,不是只清了 prefs、provider 記憶體值卻沒跟上(blocker
      // 修復:router.dart 讀的是 provider 記憶體值,不是 prefs)。
      expect(container.read(onboardingStatusProvider), isTrue);

      await container.read(sessionControllerProvider.notifier).signOut();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.appleUserId, isNull);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kAppleUserIdKey), isFalse);
      expect(prefs.containsKey('user_gender'), isFalse);
      expect(prefs.containsKey('user_current_weight'), isFalse);
      expect(prefs.containsKey(kHasCompletedOnboardingKey), isFalse);

      // provider 記憶體值(不是被測方法回傳值)是真正的參照物:signOut()
      // 必須 invalidate onboardingStatusProvider,不能只清 prefs。
      expect(container.read(onboardingStatusProvider), isFalse);
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
        'onboarding 個資與完成旗標消失(含 provider 記憶體值)、隱私三 key 與裝置層級'
        '測試登入 id 仍在、owner 換成新帳號、session 建立、裝置層匯入退休、'
        '上一位帳號的 legacy 個資與匯入統計 prefs 一併清除', () async {
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
        // 模擬「舊帳號這台裝置上已經跑過一次 CoreData 匯入」的裝置狀態——
        // 確認清除必須把這些旗標退休掉,否則重啟後 main.dart 的
        // importIfNeeded 會把前人的舊 iOS SQLite 歷史匯回給新帳號。
        kCoreDataImportCompletedKey: true,
        kCoreDataImportFailedPermanentlyKey: false,
        kCoreDataImportAttemptsKey: 2,
        kLegacyPrefsImportCompletedKey: true,
        // 上一位帳號的 legacy 個資 + 匯入統計殘留。
        'legacy_user_name': '舊使用者',
        'legacy_user_email': 'old@example.com',
        'legacy_user_gender': '男性',
        'legacy_user_age': 30,
        'legacy_user_height': 175.0,
        'legacy_user_current_weight': 70.0,
        'legacy_user_target_weight': 65.0,
        'legacy_global_settings_json': '{"weightUnit":"kg"}',
        'legacy_current_user_id': oldOwner,
        'legacy_weekly_workout_goal': 3,
        'legacy_unlocked_achievements_json': '["first_workout"]',
        'legacy_last_viewed_achievements_date_millis': 1234567890,
        kCoreDataImportTableCountsKey: '{"workouts":1}',
        kCoreDataImportSkippedCountsKey: '{}',
        kCoreDataImportDedupedCountsKey: '{}',
        kCoreDataImportCreatedPlaceholdersKey: '{}',
        kCoreDataImportVerifiedCountsKey: '{"workouts":1}',
      });

      // build() 已把 onboardingStatusProvider 讀成 true——先讀一次觸發初始化。
      expect(container.read(onboardingStatusProvider), isTrue);

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

      // provider 記憶體值(router.dart 實際讀的東西)也要跟著清乾淨,不是
      // 只清 prefs——這是 blocker 修復的核心斷言。
      expect(container.read(onboardingStatusProvider), isFalse);

      // 裝置層匯入退休:重啟後 importIfNeeded 必須直接 skip,不會把前人的
      // 舊 iOS SQLite 歷史匯回給新帳號。
      expect(prefs.getBool(kCoreDataImportCompletedKey), isTrue);
      expect(prefs.getBool(kCoreDataImportFailedPermanentlyKey), isFalse);
      expect(prefs.getInt(kCoreDataImportAttemptsKey), 0);
      expect(prefs.getBool(kLegacyPrefsImportCompletedKey), isTrue);

      // 上一位帳號的 legacy 個資殘留全數清除(顯式清單)。
      for (final key in kLegacyPrefsPersonalDataKeys) {
        expect(prefs.containsKey(key), isFalse, reason: '$key 應已被清除');
      }
      // 上一位帳號的匯入統計殘留全數清除(顯式清單)。
      for (final key in kCoreDataImportStatsKeys) {
        expect(prefs.containsKey(key), isFalse, reason: '$key 應已被清除');
      }

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

    test(
        '重入防護:清除進行中(async gap 期間)再次呼叫,第二次因 ownerConflict '
        '已被第一次同步清掉而直接安全回傳,不會有兩個清除同時操作同一份 Drift', () async {
      const oldOwner = 'owner-a';
      final container = await _containerWithPrefsAndDb({
        kLocalDataOwnerUserIdKey: oldOwner,
      });
      final db = container.read(appDatabaseProvider);
      await seedTestUser(db, id: oldOwner);

      final notifier = container.read(sessionControllerProvider.notifier);
      final conflictOutcome = await notifier.signInTest();
      expect(conflictOutcome, isA<LoginOwnerConflict>());

      // 不 await 第一次呼叫,立刻發第二次——confirmClearAndContinueLogin()
      // 的同步前綴(讀 pending + 清 ownerConflict/設 isLoading)在遇到第一個
      // `await` 前會整段同步跑完才把控制權交還,所以第二次呼叫看到的
      // state.ownerConflict 一定已經是 null。
      final future1 = notifier.confirmClearAndContinueLogin();
      final outcome2 = await notifier.confirmClearAndContinueLogin();

      expect(outcome2, isA<LoginFailure>());

      final outcome1 = await future1;
      expect(outcome1, isA<LoginSuccess>());

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isTrue);
      expect(state.ownerConflict, isNull);
    });

    test(
        '清空 DB 失敗(例外)時吃下例外、走一般化錯誤文案,isLoading 收尾為 false、'
        'ownerConflict 已清、不建立 session', () async {
      const oldOwner = 'owner-a';
      SharedPreferences.setMockInitialValues({kLocalDataOwnerUserIdKey: oldOwner});
      final prefs = await SharedPreferences.getInstance();
      final db = _ThrowingResetDb();
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

      final notifier = container.read(sessionControllerProvider.notifier);
      final conflictOutcome = await notifier.signInTest();
      expect(conflictOutcome, isA<LoginOwnerConflict>());

      final outcome = await notifier.confirmClearAndContinueLogin();

      expect(outcome, isA<LoginFailure>());
      final state = container.read(sessionControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.ownerConflict, isNull);
      expect(state.errorMessage, isNotNull);
      expect(state.isLoggedIn, isFalse);

      // owner 沒被誤認領成新身分——清除沒成功就不該動 owner key。
      expect(prefs.getString(kLocalDataOwnerUserIdKey), oldOwner);
    });

    test('確認清除:自訂動作(isSystem=false,個資)一併清空,系統動作庫重種回 66 筆', () async {
      const oldOwner = 'owner-a';
      const incomingUserId = 'device-test-uuid';
      final container = await _containerWithPrefsAndDb({
        kLocalDataOwnerUserIdKey: oldOwner,
        kTestLoginUserIdPrefsKey: incomingUserId,
      });
      final db = container.read(appDatabaseProvider);
      await seedTestUser(db, id: oldOwner);

      final systemBefore = await db.select(db.exercises).get();
      expect(systemBefore.where((e) => e.isSystem).length, 66);

      final now = DateTime.now();
      await db.into(db.exercises).insert(
            ExercisesCompanion.insert(
              id: 'custom-ex-1',
              name: '舊使用者自訂動作',
              categoryId: 'custom',
              type: 'strength',
              isSystem: const Value(false),
              isActive: const Value(true),
              userId: const Value(oldOwner),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final notifier = container.read(sessionControllerProvider.notifier);
      final conflictOutcome = await notifier.signInTest();
      expect(conflictOutcome, isA<LoginOwnerConflict>());

      final confirmOutcome = await notifier.confirmClearAndContinueLogin();
      expect(confirmOutcome, isA<LoginSuccess>());

      // 參照物是直接 SELECT,不是清空方法的回傳值。
      final afterAll = await db.select(db.exercises).get();
      expect(afterAll.any((e) => e.id == 'custom-ex-1'), isFalse); // 自訂動作(個資)已刪
      expect(afterAll.where((e) => e.isSystem).length, 66); // 系統動作庫重種回滿額
      expect(afterAll.length, 66); // 沒有任何非系統動作殘留
    });
  });

  test(
      '守門測試:AppDatabase.resetForNewOwner() 手寫的 11 張表清單須涵蓋 db.allTables '
      '全部的表——schema 之後新增第 12 張表卻忘記補進 resetForNewOwner() 時,這裡會先紅,'
      '不能靠帳號隔離悄悄漏資料才發現', () async {
    final db = openTestDatabase();
    addTearDown(() => db.close());
    // resetForNewOwner() 目前手動列出 11 個 delete(見 app_database.dart)——
    // 這裡不重複那份清單本身(重複清單無法防「兩邊一起漏改」),只守住表數
    // 對得上,數字對不上時就是清單漏了新表。
    expect(db.allTables.length, 11);
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
