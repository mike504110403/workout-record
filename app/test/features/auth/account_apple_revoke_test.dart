// 帳號相關的 Apple 與舊資料處理(SessionController):
// 1. 刪帳號:iOS 重新授權 → 撤銷 Apple 授權(在 RPC 刪帳號之前)→ 刪帳號 → 刪舊 CoreData 三檔;
//    取消授權整個中止;撤銷失敗不擋刪帳號但回報。
// 2. 首次登入比對舊 iOS 的 Apple ID:不同 → owner conflict,相同/無舊值/無匯入資料 → 認領。

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionResponse, SupabaseClient;
import 'package:workout_record/data/migration/coredata_importer_result.dart'
    show kCoreDataImportedUserIdKey;
import 'package:workout_record/data/migration/legacy_coredata_files.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/cloud_auth.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';

import '../../data/test_helpers.dart';

/// 兩個假件寫進同一份事件紀錄,才能斷言「撤銷在 RPC 之前」的先後順序。
class _FakeCloud implements CloudAuthService {
  _FakeCloud(this.log, {this.current, this.deleteError, this.nextResult});

  final List<String> log;
  CloudAuthUser? current;
  Object? deleteError;
  CloudAppleSignInResult? nextResult;

  @override
  CloudAuthUser? get currentUser => current;

  @override
  Future<CloudAppleSignInResult> signInWithApple() async {
    current = nextResult!.user;
    return nextResult!;
  }

  @override
  Future<void> signOut() async => current = null;

  @override
  Future<void> deleteAccount() async {
    log.add('deleteAccount');
    final error = deleteError;
    if (error != null) throw error;
  }
}

class _FakeRevocation implements AppleRevocationService {
  _FakeRevocation(this.log, {this.requestError, this.revokeError});

  final List<String> log;
  Object? requestError;
  Object? revokeError;

  @override
  Future<String> requestAppleAuthorizationCode() async {
    log.add('requestCode');
    final error = requestError;
    if (error != null) throw error;
    return 'CODE-1';
  }

  @override
  Future<void> revokeAppleAuthorization(String authorizationCode) async {
    log.add('revoke:$authorizationCode');
    final error = revokeError;
    if (error != null) throw error;
  }
}

/// 授權碼用假的、撤銷走真正的 [SupabaseAppleRevocationService](注入假 invoker),
/// 這樣能測到 cloud_auth.dart 裡 timeout 的實作。
class _CodeThenRealRevoke implements AppleRevocationService {
  _CodeThenRealRevoke(this.log, this.real);

  final List<String> log;
  final SupabaseAppleRevocationService real;

  @override
  Future<String> requestAppleAuthorizationCode() async {
    log.add('requestCode');
    return 'CODE-1';
  }

  @override
  Future<void> revokeAppleAuthorization(String authorizationCode) =>
      real.revokeAppleAuthorization(authorizationCode);
}

const _canceled = SignInWithAppleAuthorizationException(
  code: AuthorizationErrorCode.canceled,
  message: 'canceled',
);

const _uid = 'auth-uid-1';
const _legacyFiles = ['WorkoutRecord.sqlite', 'WorkoutRecord.sqlite-wal', 'WorkoutRecord.sqlite-shm'];

class _Env {
  _Env(this.container, this.supportDir, this.userDefaultsClearCalls);

  final ProviderContainer container;
  final Directory supportDir;

  /// 「清舊 UserDefaults」被呼叫的次數(每次呼叫加一筆)。
  final List<String> userDefaultsClearCalls;

  SessionController get session => container.read(sessionControllerProvider.notifier);

  List<bool> legacyFilesExist() =>
      [for (final f in _legacyFiles) File(p.join(supportDir.path, f)).existsSync()];
}

Future<_Env> _setUp(
  Map<String, Object> prefsValues, {
  required _FakeCloud cloud,
  AppleRevocationService? revocation,
  bool nativeApple = true,
  String? legacyAppleId,
  Future<String?> Function()? legacyAppleIdReader,
  // 舊 sqlite 三檔是否預先存在(刪帳號測試要有;首次登入比對測試依情境決定)。
  bool createLegacyFiles = true,
  // 替換「清舊 UserDefaults」的實作,預設記錄呼叫次數到 [clearCalls]。
  Future<void> Function()? userDefaultsClearer,
  LegacyCoreDataFiles? legacyFilesOverride,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  final supportDir = Directory.systemTemp.createTempSync('legacy_coredata_test_');
  if (createLegacyFiles) {
    for (final f in _legacyFiles) {
      File(p.join(supportDir.path, f)).writeAsStringSync('old');
    }
  }
  final clearCalls = <String>[];
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      cloudAuthServiceProvider.overrideWithValue(cloud),
      appleRevocationServiceProvider.overrideWithValue(revocation),
      nativeAppleSignInAvailableProvider.overrideWithValue(nativeApple),
      legacyCoreDataFilesProvider.overrideWithValue(
        legacyFilesOverride ?? LegacyCoreDataFiles(supportDirPathProvider: () async => supportDir.path),
      ),
      legacyUserDefaultsClearerProvider.overrideWithValue(() async {
        clearCalls.add('clear');
        await userDefaultsClearer?.call();
      }),
      legacyAppleUserIdReaderProvider.overrideWithValue(legacyAppleIdReader ?? () async => legacyAppleId),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
    if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
  });
  return _Env(container, supportDir, clearCalls);
}

Map<String, Object> get _loggedIn => {
      kAppleUserIdKey: _uid,
      kLocalDataOwnerUserIdKey: _uid,
    };

void main() {
  group('刪帳號撤銷 Apple 授權', () {
    test('成功:順序 = 重新授權 → 撤銷 → RPC 刪帳號;舊 sqlite 三檔被刪', () async {
      final log = <String>[];
      final env = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(log, current: const CloudAuthUser(id: _uid)),
        revocation: _FakeRevocation(log),
      );
      expect(env.legacyFilesExist(), [true, true, true]);

      final result = await env.session.deleteAccount();

      expect(log, ['requestCode', 'revoke:CODE-1', 'deleteAccount']);
      expect(result, DeleteAccountResult.deleted);
      expect(env.legacyFilesExist(), [false, false, false]);
      expect(env.container.read(sessionControllerProvider).isLoggedIn, isFalse);
    });

    test('使用者取消 Apple 重新授權:整個中止,不撤銷、不刪帳號、不動本機與舊檔', () async {
      final log = <String>[];
      final env = await _setUp(
        {..._loggedIn, kCoreDataImportedUserIdKey: 'legacy-user'},
        cloud: _FakeCloud(log, current: const CloudAuthUser(id: _uid)),
        revocation: _FakeRevocation(log, requestError: _canceled),
      );
      await seedTestUser(env.container.read(appDatabaseProvider), id: _uid);

      final result = await env.session.deleteAccount();

      expect(result, DeleteAccountResult.cancelled);
      expect(log, ['requestCode'], reason: '取消後不得撤銷、不得呼叫 RPC');
      expect(env.legacyFilesExist(), [true, true, true]);
      expect(env.container.read(sessionControllerProvider).isLoggedIn, isTrue);
      final db = env.container.read(appDatabaseProvider);
      expect(await db.select(db.users).get(), hasLength(1));
      final prefs = env.container.read(sharedPreferencesProvider);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), _uid);
      expect(prefs.getString(kCoreDataImportedUserIdKey), 'legacy-user');
    });

    test('撤銷失敗:不擋刪帳號,仍完成並回 deletedRevokeFailed', () async {
      final log = <String>[];
      final env = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(log, current: const CloudAuthUser(id: _uid)),
        revocation: _FakeRevocation(log, revokeError: Exception('apple-revoke 502')),
      );

      final result = await env.session.deleteAccount();

      expect(log, ['requestCode', 'revoke:CODE-1', 'deleteAccount']);
      expect(result, DeleteAccountResult.deletedRevokeFailed);
      expect(env.legacyFilesExist(), [false, false, false]);
      expect(env.container.read(sessionControllerProvider).isLoggedIn, isFalse);
    });

    test('Apple 重新授權出非取消的錯:略過撤銷、仍刪帳號並回 deletedRevokeFailed', () async {
      final log = <String>[];
      final env = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(log, current: const CloudAuthUser(id: _uid)),
        revocation: _FakeRevocation(log, requestError: StateError('no code')),
      );

      final result = await env.session.deleteAccount();

      expect(log, ['requestCode', 'deleteAccount']);
      expect(result, DeleteAccountResult.deletedRevokeFailed);
    });

    test('RPC 刪帳號失敗:回 failed,本機登入態與舊檔都不動', () async {
      final log = <String>[];
      final env = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(log, current: const CloudAuthUser(id: _uid), deleteError: Exception('network')),
        revocation: _FakeRevocation(log),
      );

      final result = await env.session.deleteAccount();

      expect(result, DeleteAccountResult.failed);
      expect(env.legacyFilesExist(), [true, true, true]);
      expect(env.container.read(sessionControllerProvider).isLoggedIn, isTrue);
    });

    test('非 iOS(沒有原生 Apple 登入):略過 Apple 那段,其餘照做', () async {
      final log = <String>[];
      final env = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(log, current: const CloudAuthUser(id: _uid)),
        revocation: _FakeRevocation(log),
        nativeApple: false,
      );

      final result = await env.session.deleteAccount();

      expect(log, ['deleteAccount']);
      expect(result, DeleteAccountResult.deleted);
      expect(env.legacyFilesExist(), [false, false, false]);
    });

    test('成功:一併清舊 UserDefaults(Apple ID/個資殘留),且只在 RPC 成功之後', () async {
      final log = <String>[];
      final env = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(log, current: const CloudAuthUser(id: _uid)),
        revocation: _FakeRevocation(log),
        userDefaultsClearer: () async => log.add('clearUserDefaults'),
      );

      final result = await env.session.deleteAccount();

      expect(result, DeleteAccountResult.deleted);
      expect(log, ['requestCode', 'revoke:CODE-1', 'deleteAccount', 'clearUserDefaults']);
      expect(env.userDefaultsClearCalls, hasLength(1));
    });

    test('取消 Apple 授權 / RPC 刪帳號失敗:不清舊 UserDefaults', () async {
      final cancelled = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(<String>[], current: const CloudAuthUser(id: _uid)),
        revocation: _FakeRevocation(<String>[], requestError: _canceled),
      );
      await cancelled.session.deleteAccount();
      expect(cancelled.userDefaultsClearCalls, isEmpty);

      final rpcFailed = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(<String>[], current: const CloudAuthUser(id: _uid), deleteError: Exception('network')),
        revocation: _FakeRevocation(<String>[]),
      );
      await rpcFailed.session.deleteAccount();
      expect(rpcFailed.userDefaultsClearCalls, isEmpty);
    });

    test('清舊 UserDefaults 丟例外:不影響刪帳號結果(仍 deleted、舊檔已刪、已登出)', () async {
      final log = <String>[];
      final env = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(log, current: const CloudAuthUser(id: _uid)),
        revocation: _FakeRevocation(log),
        userDefaultsClearer: () async => throw StateError('native broken'),
      );

      final result = await env.session.deleteAccount();

      expect(result, DeleteAccountResult.deleted);
      expect(env.userDefaultsClearCalls, hasLength(1));
      expect(env.legacyFilesExist(), [false, false, false]);
      expect(env.container.read(sessionControllerProvider).isLoggedIn, isFalse);
    });

    test('撤銷失敗 → 登入頁通知被記下;撤銷成功 / 取消 / RPC 失敗 → 沒有通知', () async {
      Future<String?> noticeAfter(_FakeCloud cloud, _FakeRevocation revocation) async {
        final env = await _setUp(_loggedIn, cloud: cloud, revocation: revocation);
        await env.session.deleteAccount();
        return env.container.read(postDeleteNoticeProvider);
      }

      const me = CloudAuthUser(id: _uid);
      expect(
        await noticeAfter(_FakeCloud(<String>[], current: me), _FakeRevocation(<String>[], revokeError: Exception('x'))),
        kAppleRevokeFailedMessage,
      );
      expect(await noticeAfter(_FakeCloud(<String>[], current: me), _FakeRevocation(<String>[])), isNull);
      expect(
        await noticeAfter(
          _FakeCloud(<String>[], current: me),
          _FakeRevocation(<String>[], requestError: _canceled),
        ),
        isNull,
      );
      expect(
        await noticeAfter(
          _FakeCloud(<String>[], current: me, deleteError: Exception('network')),
          _FakeRevocation(<String>[], revokeError: Exception('x')),
        ),
        isNull,
        reason: '帳號沒刪成功就不該說「帳號已刪除」',
      );
    });

    test('撤銷逾時(TimeoutException):視同撤銷失敗,仍刪帳號並回 deletedRevokeFailed', () async {
      final log = <String>[];
      final client = SupabaseClient('http://localhost:54321', 'anon-key');
      addTearDown(client.dispose);
      final real = SupabaseAppleRevocationService(
        client,
        invoker: (name, body) => Completer<FunctionResponse>().future, // 永遠不回應
        timeout: const Duration(milliseconds: 20),
      );
      final env = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(log, current: const CloudAuthUser(id: _uid)),
        revocation: _CodeThenRealRevoke(log, real),
      );

      final result = await env.session.deleteAccount();

      expect(log, ['requestCode', 'deleteAccount']);
      expect(result, DeleteAccountResult.deletedRevokeFailed);
      expect(env.legacyFilesExist(), [false, false, false]);
    });

    test('只有部分舊檔存在(沒有 -wal/-shm)也能刪,不報錯', () async {
      final log = <String>[];
      final env = await _setUp(
        _loggedIn,
        cloud: _FakeCloud(log, current: const CloudAuthUser(id: _uid)),
      );
      File(p.join(env.supportDir.path, 'WorkoutRecord.sqlite-wal')).deleteSync();
      File(p.join(env.supportDir.path, 'WorkoutRecord.sqlite-shm')).deleteSync();

      final result = await env.session.deleteAccount();

      expect(result, DeleteAccountResult.deleted);
      expect(env.legacyFilesExist(), [false, false, false]);
    });
  });

  group('首次登入比對舊 iOS 的 Apple ID', () {
    Future<_Env> setUp({
      required Map<String, Object> prefs,
      required String? legacyAppleId,
      required String? newAppleId,
      bool legacyFiles = false,
      LegacyCoreDataFiles? legacyFilesOverride,
    }) {
      final cloud = _FakeCloud(
        <String>[],
        nextResult: CloudAppleSignInResult(
          user: const CloudAuthUser(id: _uid),
          appleUserIdentifier: newAppleId,
        ),
      );
      return _setUp(
        prefs,
        cloud: cloud,
        legacyAppleId: legacyAppleId,
        createLegacyFiles: legacyFiles,
        legacyFilesOverride: legacyFilesOverride,
      );
    }

    test('有匯入資料、舊 Apple ID 與這次不同 → owner conflict,不認領、不登入', () async {
      final env = await setUp(
        prefs: {kCoreDataImportedUserIdKey: 'legacy-user'},
        legacyAppleId: 'old-apple-id',
        newAppleId: 'someone-else',
      );

      final outcome = await env.session.signInWithApple();

      expect(outcome, isA<LoginOwnerConflict>());
      final state = env.container.read(sessionControllerProvider);
      expect(state.ownerConflict, isNotNull);
      expect(state.isLoggedIn, isFalse);
      final prefs = env.container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kLocalDataOwnerUserIdKey), isFalse);
      expect(prefs.getString(kCoreDataImportedUserIdKey), 'legacy-user', reason: '衝突階段不清任何資料');
    });

    test('舊 Apple ID 與這次相同 → 照舊認領', () async {
      final env = await setUp(
        prefs: {kCoreDataImportedUserIdKey: 'legacy-user'},
        legacyAppleId: 'same-apple-id',
        newAppleId: 'same-apple-id',
      );

      final outcome = await env.session.signInWithApple();

      expect(outcome, isA<LoginSuccess>());
      expect(env.container.read(sharedPreferencesProvider).getString(kLocalDataOwnerUserIdKey), _uid);
    });

    test('沒有舊 Apple ID 值 → 照舊認領', () async {
      final env = await setUp(
        prefs: {kCoreDataImportedUserIdKey: 'legacy-user'},
        legacyAppleId: null,
        newAppleId: 'someone',
      );

      final outcome = await env.session.signInWithApple();

      expect(outcome, isA<LoginSuccess>());
      expect(env.container.read(sharedPreferencesProvider).getString(kLocalDataOwnerUserIdKey), _uid);
    });

    test('本機沒有 CoreData 匯入的資料(全新安裝)→ 即使舊值不同也認領', () async {
      final env = await setUp(
        prefs: {},
        legacyAppleId: 'old-apple-id',
        newAppleId: 'someone-else',
      );

      final outcome = await env.session.signInWithApple();

      expect(outcome, isA<LoginSuccess>());
    });

    test('Apple 沒回 userIdentifier → 無從比對,照舊認領', () async {
      final env = await setUp(
        prefs: {kCoreDataImportedUserIdKey: 'legacy-user'},
        legacyAppleId: 'old-apple-id',
        newAppleId: null,
      );

      final outcome = await env.session.signInWithApple();

      expect(outcome, isA<LoginSuccess>());
    });

    test('匯入未完成/失敗(沒有血緣 key)但舊 sqlite 還在、舊 Apple ID 不同 → owner conflict', () async {
      final env = await setUp(
        prefs: {},
        legacyFiles: true,
        legacyAppleId: 'old-apple-id',
        newAppleId: 'someone-else',
      );

      final outcome = await env.session.signInWithApple();

      expect(outcome, isA<LoginOwnerConflict>());
      expect(env.container.read(sharedPreferencesProvider).containsKey(kLocalDataOwnerUserIdKey), isFalse);
    });

    test('舊 sqlite 還在、舊 Apple ID 相同 / 沒有舊值 → 照舊認領', () async {
      for (final legacyId in <String?>['same-apple-id', null]) {
        final env = await setUp(
          prefs: {},
          legacyFiles: true,
          legacyAppleId: legacyId,
          newAppleId: 'same-apple-id',
        );

        final outcome = await env.session.signInWithApple();

        expect(outcome, isA<LoginSuccess>(), reason: 'legacyId=$legacyId');
      }
    });

    test('沒有血緣 key、舊 sqlite 也不在 → 即使舊值不同也認領', () async {
      final env = await setUp(
        prefs: {},
        legacyFiles: false,
        legacyAppleId: 'old-apple-id',
        newAppleId: 'someone-else',
      );

      expect(await env.session.signInWithApple(), isA<LoginSuccess>());
    });

    test('查舊 sqlite 是否存在失敗(目錄查不到)→ fail-open 照舊認領', () async {
      final env = await setUp(
        prefs: {},
        legacyFilesOverride: LegacyCoreDataFiles(supportDirPathProvider: () async => throw StateError('no dir')),
        legacyAppleId: 'old-apple-id',
        newAppleId: 'someone-else',
      );

      expect(await env.session.signInWithApple(), isA<LoginSuccess>());
    });

    test('conflict 後確認清除 → 清掉匯入血緣並由新帳號認領(沿用既有流程)', () async {
      final env = await setUp(
        prefs: {kCoreDataImportedUserIdKey: 'legacy-user'},
        legacyAppleId: 'old-apple-id',
        newAppleId: 'someone-else',
      );
      await env.session.signInWithApple();

      final outcome = await env.session.confirmClearAndContinueLogin();

      expect(outcome, isA<LoginSuccess>());
      final prefs = env.container.read(sharedPreferencesProvider);
      expect(prefs.getString(kLocalDataOwnerUserIdKey), _uid);
      expect(prefs.containsKey(kCoreDataImportedUserIdKey), isFalse);
    });

    test('讀舊值丟例外(非 iOS 等)→ 視為沒有舊值,照舊認領', () async {
      final cloud = _FakeCloud(
        <String>[],
        nextResult: const CloudAppleSignInResult(
          user: CloudAuthUser(id: _uid),
          appleUserIdentifier: 'someone-else',
        ),
      );
      final env = await _setUp(
        {kCoreDataImportedUserIdKey: 'legacy-user'},
        cloud: cloud,
        legacyAppleIdReader: () async => throw StateError('channel broken'),
      );

      final outcome = await env.session.signInWithApple();

      expect(outcome, isA<LoginSuccess>());
      expect(env.container.read(sharedPreferencesProvider).getString(kLocalDataOwnerUserIdKey), _uid);
    });

    test('預設讀法在沒有原生端時回 null,不拋(確實走到 MissingPluginException)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('com.mikelin.workitout/legacy_prefs');
      // 先證明這個環境下直接呼叫會是 MissingPluginException,下面的 null 才是「吞掉它」的結果。
      await expectLater(channel.invokeMethod<String>('getLegacyAppleUserId'), throwsA(isA<MissingPluginException>()));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(await container.read(legacyAppleUserIdReaderProvider)(), isNull);
    });

    test('預設讀法:原生端有回值就原樣回傳(channel 與 method 名稱正確)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('com.mikelin.workitout/legacy_prefs');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return 'apple-id-from-native';
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(await container.read(legacyAppleUserIdReaderProvider)(), 'apple-id-from-native');
      expect(calls, ['getLegacyAppleUserId']);
    });

    test('預設清法:Dart 端呼叫 clearLegacyUserDefaults;沒有原生端時不拋', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('com.mikelin.workitout/legacy_prefs');
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 沒有原生端(MissingPluginException)→ 吞掉。
      await container.read(legacyUserDefaultsClearerProvider)();

      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await container.read(legacyUserDefaultsClearerProvider)();
      expect(calls, ['clearLegacyUserDefaults']);

      // 原生端丟錯 → 同樣吞掉。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom');
      });
      await container.read(legacyUserDefaultsClearerProvider)();
    });

    test('已有 owner 且就是自己 → 不再比對舊 Apple ID(只有首次認領才比)', () async {
      final env = await setUp(
        prefs: {kCoreDataImportedUserIdKey: 'legacy-user', kLocalDataOwnerUserIdKey: _uid},
        legacyAppleId: 'old-apple-id',
        newAppleId: 'someone-else',
      );

      final outcome = await env.session.signInWithApple();

      expect(outcome, isA<LoginSuccess>());
    });
  });

  group('LegacyCoreDataFiles.exists', () {
    test('主檔存在 → true;只剩 -wal/-shm 或全無 → false;目錄查不到 → false', () async {
      final dir = Directory.systemTemp.createTempSync('legacy_exists_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final files = LegacyCoreDataFiles(supportDirPathProvider: () async => dir.path);

      expect(await files.exists(), isFalse);

      File(p.join(dir.path, 'WorkoutRecord.sqlite-wal')).writeAsStringSync('x');
      expect(await files.exists(), isFalse, reason: '只看主檔');

      File(p.join(dir.path, 'WorkoutRecord.sqlite')).writeAsStringSync('x');
      expect(await files.exists(), isTrue);

      final broken = LegacyCoreDataFiles(supportDirPathProvider: () async => throw StateError('no dir'));
      expect(await broken.exists(), isFalse);
    });
  });

  group('SupabaseAppleRevocationService.revokeAppleAuthorization', () {
    SupabaseAppleRevocationService build(EdgeFunctionInvoker invoker, {Duration? timeout}) {
      final client = SupabaseClient('http://localhost:54321', 'anon-key');
      addTearDown(client.dispose);
      return SupabaseAppleRevocationService(
        client,
        invoker: invoker,
        timeout: timeout ?? kAppleRevokeInvokeTimeout,
      );
    }

    test('預設逾時是 15 秒', () {
      expect(kAppleRevokeInvokeTimeout, const Duration(seconds: 15));
    });

    test('Edge Function 超過 timeout 沒回應 → 拋 TimeoutException', () async {
      final service = build(
        (name, body) => Completer<FunctionResponse>().future,
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(service.revokeAppleAuthorization('CODE'), throwsA(isA<TimeoutException>()));
    });

    test('呼叫 apple-revoke 並帶 authorizationCode;{ok:true} 通過,其餘回應拋錯', () async {
      final calls = <String>[];
      final ok = build((name, body) async {
        calls.add('$name:${body['authorizationCode']}');
        return const FunctionResponse(status: 200, data: {'ok': true});
      });
      await ok.revokeAppleAuthorization('CODE-9');
      expect(calls, ['apple-revoke:CODE-9']);

      final bad = build((name, body) async => const FunctionResponse(status: 200, data: {'ok': false}));
      await expectLater(bad.revokeAppleAuthorization('C'), throwsA(isA<StateError>()));
      final non200 = build((name, body) async => const FunctionResponse(status: 400, data: {'ok': false}));
      await expectLater(non200.revokeAppleAuthorization('C'), throwsA(isA<StateError>()));
    });
  });
}
