// SessionController 雲端模式(Supabase Auth)seam:以 [cloudAuthServiceProvider]
// override 成假件,驗證登入成功 userId = auth uid、ensure(authUid) 只在
// Onboarding 已完成時呼叫(2026-11-10 裁示 A)、啟動以 Supabase session 恢復
// 登入態、登出呼叫 auth.signOut 並清本機個資、帳號隔離改用 auth uid 比對。
// 非雲端模式的行為由 session_controller_test.dart 覆蓋(不受影響)。

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:workout_record/data/db/app_database.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/user_repository.dart';
import 'package:workout_record/features/auth/cloud_auth.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_controller.dart'
    show kUserCurrentWeightKey;
import 'package:workout_record/features/onboarding/onboarding_status.dart';

import 'package:workout_record/data/migration/coredata_importer_result.dart';

import '../../data/test_helpers.dart';

class _FakeCloudAuth implements CloudAuthService {
  _FakeCloudAuth({CloudAuthUser? current}) : _current = current;

  CloudAuthUser? _current;
  CloudAppleSignInResult? nextResult;
  Object? signInError;
  Object? signOutError;
  int signInCalls = 0;
  int signOutCalls = 0;
  Object? deleteError;
  int deleteCalls = 0;

  @override
  CloudAuthUser? get currentUser => _current;

  @override
  Future<CloudAppleSignInResult> signInWithApple() async {
    signInCalls++;
    final error = signInError;
    if (error != null) throw error;
    final result = nextResult!;
    _current = result.user;
    return result;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _current = null;
    final error = signOutError;
    if (error != null) throw error;
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    final error = deleteError;
    if (error != null) throw error;
    _current = null;
  }
}

class _RecordingUserRepo implements UserRepository {
  final ensured = <({String id, String? name, String? email})>[];
  Object? ensureError;

  @override
  Future<bool> ensure(String id, {String? name, String? email}) async {
    final error = ensureError;
    if (error != null) throw error;
    ensured.add((id: id, name: name, email: email));
    return true;
  }

  @override
  Future<User?> getById(String id) async => null;
}

CloudAppleSignInResult _appleResult(
  String uid, {
  String? givenName,
  String? familyName,
  String? appleEmail,
  String? authEmail,
}) =>
    CloudAppleSignInResult(
      user: CloudAuthUser(id: uid, email: authEmail),
      givenName: givenName,
      familyName: familyName,
      appleEmail: appleEmail,
    );

Future<ProviderContainer> _container(
  Map<String, Object> prefsValues, {
  required _FakeCloudAuth cloud,
  _RecordingUserRepo? userRepo,
  Stream<DateTime>? sessionEnded,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      cloudAuthServiceProvider.overrideWithValue(cloud),
      if (sessionEnded != null) cloudSessionEndedProvider.overrideWith((ref) => sessionEnded),
      if (userRepo != null) userRepositoryProvider.overrideWithValue(userRepo),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return container;
}

void main() {
  group('雲端登入', () {
    test('登入成功:session userId = auth uid,prefs 與 owner 都寫 auth uid,姓名照 Apple 首次給的預填',
        () async {
      final cloud = _FakeCloudAuth()
        ..nextResult = _appleResult(
          'auth-uid-1',
          givenName: '小明',
          familyName: '王',
          appleEmail: 'apple@example.com',
        );
      final container = await _container({}, cloud: cloud, userRepo: _RecordingUserRepo());

      final outcome = await container.read(sessionControllerProvider.notifier).signInWithApple();

      expect(outcome, isA<LoginSuccess>());
      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isTrue);
      expect(state.appleUserId, 'auth-uid-1');
      expect(state.appleUserName, '小明 王');
      expect(state.appleUserEmail, 'apple@example.com');
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kAppleUserIdKey), 'auth-uid-1');
      expect(prefs.getString(kLocalDataOwnerUserIdKey), 'auth-uid-1');
      expect(cloud.signInCalls, 1);
    });

    test('Apple 沒給姓名/信箱時:姓名退回「用戶」,信箱退回 Supabase 帳號信箱', () async {
      final cloud = _FakeCloudAuth()
        ..nextResult = _appleResult('auth-uid-1', authEmail: 'relay@privaterelay.appleid.com');
      final container = await _container({}, cloud: cloud, userRepo: _RecordingUserRepo());

      await container.read(sessionControllerProvider.notifier).signInWithApple();

      final state = container.read(sessionControllerProvider);
      expect(state.appleUserName, '用戶');
      expect(state.appleUserEmail, 'relay@privaterelay.appleid.com');
    });

    test('Onboarding 已完成時,登入後呼叫 UserRepository.ensure(authUid)', () async {
      final cloud = _FakeCloudAuth()..nextResult = _appleResult('auth-uid-1', givenName: 'A');
      final userRepo = _RecordingUserRepo();
      final container = await _container(
        {kHasCompletedOnboardingKey: true},
        cloud: cloud,
        userRepo: userRepo,
      );

      await container.read(sessionControllerProvider.notifier).signInWithApple();

      expect(userRepo.ensured, hasLength(1));
      expect(userRepo.ensured.single.id, 'auth-uid-1');
      expect(userRepo.ensured.single.name, 'A');
    });

    test('Onboarding 未完成時,登入不呼叫 ensure(交給 Onboarding 判斷 isNewUser)', () async {
      final cloud = _FakeCloudAuth()..nextResult = _appleResult('auth-uid-1');
      final userRepo = _RecordingUserRepo();
      final container = await _container({}, cloud: cloud, userRepo: userRepo);

      final outcome = await container.read(sessionControllerProvider.notifier).signInWithApple();

      expect(outcome, isA<LoginSuccess>());
      expect(userRepo.ensured, isEmpty);
    });

    test('ensure 失敗:登入失敗、不建立 session、盡力登出 Supabase', () async {
      final cloud = _FakeCloudAuth()..nextResult = _appleResult('auth-uid-1');
      final userRepo = _RecordingUserRepo()..ensureError = Exception('network down');
      final container = await _container(
        {kHasCompletedOnboardingKey: true},
        cloud: cloud,
        userRepo: userRepo,
      );

      final outcome = await container.read(sessionControllerProvider.notifier).signInWithApple();

      expect(outcome, isA<LoginFailure>());
      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNotNull);
      expect(container.read(sharedPreferencesProvider).getString(kAppleUserIdKey), isNull);
      expect(cloud.signOutCalls, 1);
    });

    test('使用者取消 Apple 授權:靜默失敗,不顯示錯誤', () async {
      final cloud = _FakeCloudAuth()
        ..signInError = const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'canceled',
        );
      final container = await _container({}, cloud: cloud);

      final outcome = await container.read(sessionControllerProvider.notifier).signInWithApple();

      expect(outcome, isA<LoginFailure>());
      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('平台沒有原生 Apple 登入(Web/Android):給明確提示,不崩潰', () async {
      final cloud = _FakeCloudAuth()..signInError = UnsupportedError('no native apple');
      final container = await _container({}, cloud: cloud);

      final outcome = await container.read(sessionControllerProvider.notifier).signInWithApple();

      expect(outcome, isA<LoginFailure>());
      expect(container.read(sessionControllerProvider).errorMessage, kAppleSignInUnsupportedMessage);
    });

    test('Supabase signInWithIdToken 失敗:一般化錯誤文案', () async {
      final cloud = _FakeCloudAuth()..signInError = Exception('invalid id token');
      final container = await _container({}, cloud: cloud);

      final outcome = await container.read(sessionControllerProvider.notifier).signInWithApple();

      expect(outcome, isA<LoginFailure>());
      final state = container.read(sessionControllerProvider);
      expect(state.errorMessage, isNotNull);
      expect(state.errorMessage, isNot(kAppleSignInUnsupportedMessage));
    });

    test('雲端模式不支援測試登入:回 LoginFailure 並給提示,不寫身分', () async {
      final cloud = _FakeCloudAuth();
      final container = await _container({}, cloud: cloud);

      final outcome = await container.read(sessionControllerProvider.notifier).signInTest();

      expect(outcome, isA<LoginFailure>());
      expect(
        container.read(sessionControllerProvider).errorMessage,
        kTestLoginUnavailableInCloudMessage,
      );
      expect(container.read(sharedPreferencesProvider).getString(kAppleUserIdKey), isNull);
    });
  });

  group('雲端帳號隔離(auth uid 比對)', () {
    test('owner 是別的身分時回傳 conflict,不建立 session;取消會登出 Supabase', () async {
      final cloud = _FakeCloudAuth()..nextResult = _appleResult('auth-uid-new');
      final userRepo = _RecordingUserRepo();
      final container = await _container(
        {kLocalDataOwnerUserIdKey: 'auth-uid-old', kHasCompletedOnboardingKey: true},
        cloud: cloud,
        userRepo: userRepo,
      );
      final notifier = container.read(sessionControllerProvider.notifier);

      final outcome = await notifier.signInWithApple();

      expect(outcome, isA<LoginOwnerConflict>());
      expect((outcome as LoginOwnerConflict).pendingUserId, 'auth-uid-new');
      expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
      expect(userRepo.ensured, isEmpty);

      notifier.cancelOwnerConflict();
      await Future<void>.delayed(Duration.zero);

      expect(cloud.signOutCalls, 1);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), 'auth-uid-old');
      expect(prefs.getString(kAppleUserIdKey), isNull);
    });

    test('確認清除並繼續:owner 換成 auth uid、session userId = auth uid;旗標已清所以不 ensure',
        () async {
      final cloud = _FakeCloudAuth()..nextResult = _appleResult('auth-uid-new');
      final userRepo = _RecordingUserRepo();
      final container = await _container(
        {kLocalDataOwnerUserIdKey: 'auth-uid-old', kHasCompletedOnboardingKey: true},
        cloud: cloud,
        userRepo: userRepo,
      );
      final notifier = container.read(sessionControllerProvider.notifier);

      await notifier.signInWithApple();
      final outcome = await notifier.confirmClearAndContinueLogin();

      expect(outcome, isA<LoginSuccess>());
      final state = container.read(sessionControllerProvider);
      expect(state.appleUserId, 'auth-uid-new');
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), 'auth-uid-new');
      expect(prefs.getBool(kHasCompletedOnboardingKey), isNull);
      expect(userRepo.ensured, isEmpty);
    });

    test('owner 就是同一個 auth uid:照常登入', () async {
      final cloud = _FakeCloudAuth()..nextResult = _appleResult('auth-uid-1');
      final container = await _container(
        {kLocalDataOwnerUserIdKey: 'auth-uid-1'},
        cloud: cloud,
        userRepo: _RecordingUserRepo(),
      );

      final outcome = await container.read(sessionControllerProvider.notifier).signInWithApple();

      expect(outcome, isA<LoginSuccess>());
    });
  });

  group('啟動恢復 session', () {
    test('Supabase 有 session 且 prefs 身分相符:恢復成已登入,userId = auth uid', () async {
      final cloud = _FakeCloudAuth(current: const CloudAuthUser(id: 'auth-uid-1'));
      final container = await _container({
        kAppleUserIdKey: 'auth-uid-1',
        kAppleUserNameKey: '小明 王',
        kAppleUserEmailKey: 'apple@example.com',
      }, cloud: cloud);

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isTrue);
      expect(state.appleUserId, 'auth-uid-1');
      expect(state.appleUserName, '小明 王');
      expect(state.appleUserEmail, 'apple@example.com');
    });

    test('沒有 Supabase session:即使 prefs 有舊身分也視為未登入', () async {
      final cloud = _FakeCloudAuth();
      final container = await _container({kAppleUserIdKey: 'auth-uid-1'}, cloud: cloud);

      expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
    });

    test('Supabase session 與 prefs 身分不符(例如卡在 owner 衝突時重啟):視為未登入', () async {
      final cloud = _FakeCloudAuth(current: const CloudAuthUser(id: 'auth-uid-new'));
      final container = await _container({kAppleUserIdKey: 'auth-uid-old'}, cloud: cloud);

      expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
    });

    test('ensureCloudUserRowOnRestore:已登入且 Onboarding 已完成 → ensure(authUid)', () async {
      final cloud = _FakeCloudAuth(current: const CloudAuthUser(id: 'auth-uid-1'));
      final userRepo = _RecordingUserRepo();
      final container = await _container(
        {kAppleUserIdKey: 'auth-uid-1', kHasCompletedOnboardingKey: true},
        cloud: cloud,
        userRepo: userRepo,
      );

      await container.read(sessionControllerProvider.notifier).ensureCloudUserRowOnRestore();

      expect(userRepo.ensured.map((e) => e.id), ['auth-uid-1']);
    });

    test('ensureCloudUserRowOnRestore:Onboarding 未完成或未登入 → 不 ensure', () async {
      final userRepo = _RecordingUserRepo();
      final notOnboarded = await _container(
        {kAppleUserIdKey: 'auth-uid-1'},
        cloud: _FakeCloudAuth(current: const CloudAuthUser(id: 'auth-uid-1')),
        userRepo: userRepo,
      );
      await notOnboarded.read(sessionControllerProvider.notifier).ensureCloudUserRowOnRestore();

      final loggedOut = await _container(
        {kHasCompletedOnboardingKey: true},
        cloud: _FakeCloudAuth(),
        userRepo: userRepo,
      );
      await loggedOut.read(sessionControllerProvider.notifier).ensureCloudUserRowOnRestore();

      expect(userRepo.ensured, isEmpty);
    });
  });

  group('雲端登出', () {
    test('呼叫 Supabase signOut,並清 session key 與 Onboarding 個資;owner 保留', () async {
      final cloud = _FakeCloudAuth(current: const CloudAuthUser(id: 'auth-uid-1'));
      final container = await _container({
        kAppleUserIdKey: 'auth-uid-1',
        kAppleUserNameKey: 'A',
        kAppleUserEmailKey: 'a@example.com',
        kLocalDataOwnerUserIdKey: 'auth-uid-1',
        kHasCompletedOnboardingKey: true,
        kUserCurrentWeightKey: 70.0,
      }, cloud: cloud);
      expect(container.read(sessionControllerProvider).isLoggedIn, isTrue);

      await container.read(sessionControllerProvider.notifier).signOut();

      expect(cloud.signOutCalls, 1);
      expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kAppleUserIdKey), isNull);
      expect(prefs.getString(kAppleUserNameKey), isNull);
      expect(prefs.getString(kAppleUserEmailKey), isNull);
      expect(prefs.getBool(kHasCompletedOnboardingKey), isNull);
      expect(prefs.getDouble(kUserCurrentWeightKey), isNull);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), 'auth-uid-1');
    });

    test('Supabase signOut 失敗(斷網)時,本機登出照樣完成', () async {
      final cloud = _FakeCloudAuth(current: const CloudAuthUser(id: 'auth-uid-1'))
        ..signOutError = Exception('offline');
      final container = await _container({kAppleUserIdKey: 'auth-uid-1'}, cloud: cloud);

      await container.read(sessionControllerProvider.notifier).signOut();

      expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
      expect(container.read(sharedPreferencesProvider).getString(kAppleUserIdKey), isNull);
    });
  });

  group('Supabase session 被動結束(onAuthStateChange signedOut)', () {
    test('已登入時收到 signedOut 事件 → 本機登入態與個資清除', () async {
      final events = StreamController<DateTime>();
      addTearDown(events.close);
      final cloud = _FakeCloudAuth(current: const CloudAuthUser(id: 'auth-uid-1'));
      final container = await _container(
        {
          kAppleUserIdKey: 'auth-uid-1',
          kAppleUserNameKey: 'Mike',
          kHasCompletedOnboardingKey: true,
        },
        cloud: cloud,
        sessionEnded: events.stream,
      );
      expect(container.read(sessionControllerProvider).isLoggedIn, isTrue);
      container.listen(cloudSessionEndedProvider, (_, _) {});

      events.add(DateTime.now());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kAppleUserIdKey), isFalse);
      expect(prefs.containsKey(kHasCompletedOnboardingKey), isFalse);
      expect(cloud.signOutCalls, 0, reason: '被動結束不需再呼叫雲端 signOut');
    });

    test('未收到事件時維持登入', () async {
      final events = StreamController<DateTime>();
      addTearDown(events.close);
      final cloud = _FakeCloudAuth(current: const CloudAuthUser(id: 'auth-uid-1'));
      final container = await _container(
        {kAppleUserIdKey: 'auth-uid-1', kHasCompletedOnboardingKey: true},
        cloud: cloud,
        sessionEnded: events.stream,
      );
      container.listen(cloudSessionEndedProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionControllerProvider).isLoggedIn, isTrue);
    });
  });
  group('刪除帳號', () {
    Future<int> userRows(ProviderContainer c) async {
      final db = c.read(appDatabaseProvider);
      return (await db.select(db.users).get()).length;
    }

    test('成功:呼叫雲端刪除 → 本機 Drift 清空、退休舊 iOS 匯入、移除 owner、登出', () async {
      final cloud = _FakeCloudAuth(current: const CloudAuthUser(id: 'auth-uid-1'));
      final container = await _container(
        {
          kAppleUserIdKey: 'auth-uid-1',
          kHasCompletedOnboardingKey: true,
          kLocalDataOwnerUserIdKey: 'auth-uid-1',
          'offline_workout_draft.v1.w1': '{}',
          'offline_cache.user.v1.auth-uid-1': '{}',
          'offline_cache.exercises.v1.auth-uid-1.false': '[]',
        },
        cloud: cloud,
      );
      await seedTestUser(container.read(appDatabaseProvider), id: 'auth-uid-1');
      expect(await userRows(container), 1);

      final ok = await container.read(sessionControllerProvider.notifier).deleteAccount();

      expect(ok, isTrue);
      expect(cloud.deleteCalls, 1);
      expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
      expect(await userRows(container), 0);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kAppleUserIdKey), isFalse);
      expect(prefs.containsKey(kLocalDataOwnerUserIdKey), isFalse);
      expect(prefs.containsKey(kHasCompletedOnboardingKey), isFalse);
      expect(prefs.getBool(kCoreDataImportCompletedKey), isTrue,
          reason: '舊 iOS 資料不可在下次登入時被重新匯入/上傳');
      expect(prefs.getKeys().where((k) => k.startsWith('offline_')), isEmpty,
          reason: '離線草稿與快取一併清除');
    });

    test('雲端刪除失敗:回 false,本機登入態與資料都不動', () async {
      final cloud = _FakeCloudAuth(current: const CloudAuthUser(id: 'auth-uid-1'))
        ..deleteError = Exception('network');
      final container = await _container(
        {
          kAppleUserIdKey: 'auth-uid-1',
          kHasCompletedOnboardingKey: true,
          kLocalDataOwnerUserIdKey: 'auth-uid-1',
        },
        cloud: cloud,
      );
      await seedTestUser(container.read(appDatabaseProvider), id: 'auth-uid-1');

      final ok = await container.read(sessionControllerProvider.notifier).deleteAccount();

      expect(ok, isFalse);
      expect(container.read(sessionControllerProvider).isLoggedIn, isTrue);
      expect(await userRows(container), 1);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), 'auth-uid-1');
      expect(cloud.signOutCalls, 0);
    });

    test('未登入時不呼叫雲端', () async {
      final cloud = _FakeCloudAuth();
      final container = await _container({}, cloud: cloud);

      final ok = await container.read(sessionControllerProvider.notifier).deleteAccount();

      expect(ok, isFalse);
      expect(cloud.deleteCalls, 0);
    });
  });
}
