// CloudUploadController + startCloudUploadTrigger + 升級用戶判斷(雲端模式)+
// CloudUploadStatusTile。Supabase 端以 [cloudUploadSinkProvider] /
// [cloudAuthServiceProvider] / [userRepositoryProvider] override 成假件。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/db/app_database.dart';
import 'package:workout_record/data/migration/cloud_upload.dart';
import 'package:workout_record/data/migration/coredata_importer_result.dart'
    show kCoreDataImportedUserIdKey;
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/user_repository.dart';
import 'package:workout_record/features/auth/cloud_auth.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/cloud_upload/cloud_upload_controller.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/settings/widgets/cloud_upload_status_tile.dart';

import '../../data/test_helpers.dart';
import '../../migration/cloud_upload_fakes.dart';

const uid = 'auth-uid-1';

class _FakeCloudAuth implements CloudAuthService {
  _FakeCloudAuth({this.current});

  CloudAuthUser? current;
  String nextUid = uid;

  @override
  CloudAuthUser? get currentUser => current;

  @override
  Future<CloudAppleSignInResult> signInWithApple() async {
    current = CloudAuthUser(id: nextUid);
    return CloudAppleSignInResult(user: current!, givenName: '小明');
  }

  @override
  Future<void> signOut() async => current = null;
}

/// 模擬 Supabase 版 UserRepository:getById 只認 auth uid(CoreData 舊 id 必拿 null)。
class _CloudLikeUserRepo implements UserRepository {
  final ensured = <String>[];

  @override
  Future<bool> ensure(String id, {String? name, String? email}) async {
    ensured.add(id);
    return true;
  }

  @override
  Future<User?> getById(String id) async => null;
}

class _Harness {
  _Harness(this.container, this.db, this.sink, this.cloud, this.userRepo);

  final ProviderContainer container;
  final AppDatabase db;
  final FakeCloudUploadSink? sink;
  final _FakeCloudAuth cloud;
  final _CloudLikeUserRepo userRepo;

  SharedPreferences get prefs => container.read(sharedPreferencesProvider);
  CloudUploadController get controller => container.read(cloudUploadControllerProvider.notifier);
  CloudUploadStatus get status => container.read(cloudUploadControllerProvider);
}

/// [restored] = 啟動時已有 Supabase session 且 prefs 已登入(恢復 session 情境)。
Future<_Harness> _harness({
  bool cloudMode = true,
  bool restored = true,
  bool seedData = true,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    if (restored) kAppleUserIdKey: uid,
    if (restored) kLocalDataOwnerUserIdKey: uid,
    ...prefs,
  });
  final p = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  if (seedData) await seedLegacyData(db);
  final sink = cloudMode ? await fakeSinkMirroringSeeds(db) : null;
  final cloud = _FakeCloudAuth(current: restored ? const CloudAuthUser(id: uid) : null);
  final userRepo = _CloudLikeUserRepo();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(p),
      appDatabaseProvider.overrideWithValue(db),
      cloudUploadSinkProvider.overrideWithValue(sink),
      cloudAuthServiceProvider.overrideWithValue(cloudMode ? cloud : null),
      userRepositoryProvider.overrideWithValue(userRepo),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return _Harness(container, db, sink, cloud, userRepo);
}

void main() {
  group('CloudUploadController.runIfNeeded', () {
    test('雲端模式、已登入、owner 是自己 → 上傳成功,狀態 succeeded,寫旗標', () async {
      final h = await _harness(prefs: {kHasCompletedOnboardingKey: true});

      final result = await h.controller.runIfNeeded();

      expect(result!.success, isTrue, reason: result.errorMessage);
      expect(h.status.phase, CloudUploadPhase.succeeded);
      expect(h.status.uploadedRows, result.uploadedRows);
      expect(h.sink!.count('workouts'), 1);
      expect(h.sink!.ensured.single.uid, uid, reason: 'Onboarding 已完成 → ensure users 列');
      expect(h.prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);

      // 再跑一次:旗標已寫 → no-op,狀態維持。
      expect(await h.controller.runIfNeeded(), isNull);
    });

    test('Onboarding 未完成 → 照常上傳但不 ensure users 列(裁示 A)', () async {
      final h = await _harness();
      await h.controller.runIfNeeded();
      expect(h.sink!.count('workouts'), 1);
      expect(h.sink!.ensured, isEmpty);
    });

    test('非雲端模式 → no-op', () async {
      final h = await _harness(cloudMode: false);
      expect(await h.controller.runIfNeeded(), isNull);
      expect(h.status.phase, CloudUploadPhase.idle);
    });

    test('未登入 → no-op', () async {
      final h = await _harness(restored: false);
      expect(await h.controller.runIfNeeded(), isNull);
      expect(h.sink!.insertCalls, isEmpty);
    });

    test('本機資料 owner 不是這個 uid(帳號隔離)→ no-op', () async {
      final h = await _harness(prefs: {kLocalDataOwnerUserIdKey: 'someone-else'});
      expect(await h.controller.runIfNeeded(), isNull);
      expect(h.sink!.insertCalls, isEmpty);
    });

    test('本機沒有可上傳資料 → no-op,狀態 idle(不閃上傳中)', () async {
      final h = await _harness(seedData: false);
      expect(await h.controller.runIfNeeded(), isNull);
      expect(h.status.phase, CloudUploadPhase.idle);
    });

    test('失敗 → 狀態 failed;重試 → succeeded 且雲端不重複', () async {
      final h = await _harness();
      h.sink!.failOnTable = 'personal_records';

      final failed = await h.controller.runIfNeeded();
      expect(failed!.success, isFalse);
      expect(h.status.phase, CloudUploadPhase.failed);
      expect(h.status.errorMessage, contains('injected failure'));
      expect(h.prefs.getBool(cloudUploadCompletedKey(uid)), isNull);

      final retried = await h.controller.runIfNeeded();
      expect(retried!.success, isTrue, reason: retried.errorMessage);
      expect(h.status.phase, CloudUploadPhase.succeeded);
      expect(h.sink!.count('workout_sets'), 3);
      expect(h.sink!.count('personal_records'), 1);
    });
  });

  group('startCloudUploadTrigger', () {
    test('恢復 session(啟動時已登入)→ 立即觸發上傳', () async {
      final h = await _harness();
      final sub = startCloudUploadTrigger(h.container);
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(h.sink!.count('workouts'), 1);
    });

    test('啟動時未登入 → 不觸發;登入成功後觸發一次', () async {
      final h = await _harness(restored: false);
      final sub = startCloudUploadTrigger(h.container);
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(h.sink!.insertCalls, isEmpty);

      final outcome = await h.container.read(sessionControllerProvider.notifier).signInWithApple();
      expect(outcome, isA<LoginSuccess>());
      await pumpEventQueue();
      expect(h.sink!.count('workouts'), 1);
      expect(h.prefs.getBool(cloudUploadCompletedKey(uid)), isTrue);
    });
  });

  group('升級用戶判斷(雲端模式)', () {
    test('血緣 key + 本機 Drift 有該使用者 → 標記完成(不再經 Supabase repo 查 CoreData id)', () async {
      final h = await _harness(
        restored: false,
        prefs: {kCoreDataImportedUserIdKey: legacyUserId},
      );

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(h.container);

      expect(h.container.read(onboardingStatusProvider), isTrue);
    });

    test('血緣 key 存在但本機 Drift 沒有該使用者 → 不標記', () async {
      final h = await _harness(
        restored: false,
        seedData: false,
        prefs: {kCoreDataImportedUserIdKey: legacyUserId},
      );

      await autoCompleteOnboardingForUpgradedUsersIfNeeded(h.container);

      expect(h.container.read(onboardingStatusProvider), isFalse);
    });

    test('升級用戶首次雲端登入:ensure(auth uid) users 列,並觸發上傳', () async {
      final h = await _harness(
        restored: false,
        prefs: {kCoreDataImportedUserIdKey: legacyUserId},
      );
      await autoCompleteOnboardingForUpgradedUsersIfNeeded(h.container);
      final sub = startCloudUploadTrigger(h.container);
      addTearDown(sub.close);

      await h.container.read(sessionControllerProvider.notifier).signInWithApple();
      await pumpEventQueue();

      expect(h.userRepo.ensured, [uid]);
      expect(h.sink!.ensured.single.uid, uid);
      expect(h.sink!.count('workouts'), 1);
    });
  });

  group('CloudUploadStatusTile', () {
    Future<void> pumpTile(WidgetTester tester, _Harness h) => tester.pumpWidget(
          UncontrolledProviderScope(
            container: h.container,
            child: const MaterialApp(home: Scaffold(body: CloudUploadStatusTile())),
          ),
        );

    testWidgets('idle 不渲染;失敗顯示重試;按重試成功後顯示筆數', (tester) async {
      final h = await tester.runAsync(() => _harness());
      await pumpTile(tester, h!);
      expect(find.byType(ListTile), findsNothing);

      h.sink!.failOnTable = 'workouts';
      await tester.runAsync(() => h.controller.runIfNeeded());
      await tester.pump();
      expect(find.byKey(const Key('cloudUploadFailed')), findsOneWidget);
      expect(find.text('舊資料上傳雲端失敗'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('cloudUploadRetryButton')));
        // 等 runIfNeeded 跑完(真 I/O 在 runAsync 裡)。
        for (var i = 0; i < 50 && h.status.phase != CloudUploadPhase.succeeded; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(find.byKey(const Key('cloudUploadSucceeded')), findsOneWidget);
      expect(find.textContaining('共 '), findsOneWidget);
    });

    testWidgets('上傳中顯示進度', (tester) async {
      final h = await tester.runAsync(() => _harness());
      await pumpTile(tester, h!);
      h.container.read(cloudUploadControllerProvider.notifier).state =
          const CloudUploadStatus(CloudUploadPhase.uploading);
      await tester.pump();
      expect(find.byKey(const Key('cloudUploadUploading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
