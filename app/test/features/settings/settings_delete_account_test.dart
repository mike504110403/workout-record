// SettingsPage 刪除帳號:只在雲端模式顯示;兩段確認後才呼叫雲端刪除;
// 失敗提示且維持登入。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:workout_record/data/migration/legacy_coredata_files.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/cloud_auth.dart';
import 'package:workout_record/features/auth/login_page.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/settings_page.dart';

import '../../data/test_helpers.dart';

class _FakeCloudAuth implements CloudAuthService {
  Object? deleteError;
  int deleteCalls = 0;

  @override
  CloudAuthUser? get currentUser => const CloudAuthUser(id: 'auth-uid-1');

  @override
  Future<CloudAppleSignInResult> signInWithApple() => throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    final error = deleteError;
    if (error != null) throw error;
  }
}

class _FakeRevocation implements AppleRevocationService {
  Object? requestError;
  Object? revokeError;
  int requestCalls = 0;
  int revokeCalls = 0;

  @override
  Future<String> requestAppleAuthorizationCode() async {
    requestCalls++;
    final error = requestError;
    if (error != null) throw error;
    return 'CODE';
  }

  @override
  Future<void> revokeAppleAuthorization(String authorizationCode) async {
    revokeCalls++;
    final error = revokeError;
    if (error != null) throw error;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  CloudAuthService? cloud,
  AppleRevocationService? revocation,
}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: 'auth-uid-1'});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      cloudAuthServiceProvider.overrideWithValue(cloud),
      appleRevocationServiceProvider.overrideWithValue(revocation),
      // 指向不存在的目錄:刪檔邏輯在 widget test 的 FakeAsync 下不跑真實 I/O。
      legacyCoreDataFilesProvider.overrideWithValue(
        LegacyCoreDataFiles(supportDirPathProvider: () async => '/nonexistent-legacy-dir'),
      ),
      nativeAppleSignInAvailableProvider.overrideWithValue(revocation != null),
      // MethodChannel 呼叫在 widget test 的 FakeAsync 下不會完成,直接換成立即完成的假件。
      legacyUserDefaultsClearerProvider.overrideWithValue(() async {}),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tapDelete(WidgetTester tester) async {
  final tile = find.byKey(const Key('deleteAccountButton'));
  await tester.scrollUntilVisible(tile, 200);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('本機模式不顯示刪除帳號', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('deleteAccountButton')), findsNothing);
  });

  testWidgets('第一段按取消:不呼叫雲端', (tester) async {
    final cloud = _FakeCloudAuth();
    final container = await _pump(tester, cloud: cloud);

    await _tapDelete(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(cloud.deleteCalls, 0);
    expect(container.read(sessionControllerProvider).isLoggedIn, isTrue);
  });

  testWidgets('第二段按取消:不呼叫雲端', (tester) async {
    final cloud = _FakeCloudAuth();
    await _pump(tester, cloud: cloud);

    await _tapDelete(tester);
    await tester.tap(find.byKey(const Key('deleteAccountContinue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(cloud.deleteCalls, 0);
  });

  testWidgets('兩段都確認:呼叫雲端刪除並登出', (tester) async {
    final cloud = _FakeCloudAuth();
    final container = await _pump(tester, cloud: cloud);

    await _tapDelete(tester);
    await tester.tap(find.byKey(const Key('deleteAccountContinue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAccountConfirm')));
    await tester.pumpAndSettle();

    expect(cloud.deleteCalls, 1);
    expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
  });

  testWidgets('雲端失敗:提示錯誤、維持登入', (tester) async {
    final cloud = _FakeCloudAuth()..deleteError = Exception('network');
    final container = await _pump(tester, cloud: cloud);

    await _tapDelete(tester);
    await tester.tap(find.byKey(const Key('deleteAccountContinue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAccountConfirm')));
    await tester.pumpAndSettle();

    expect(find.text('刪除帳號失敗,請確認網路後再試一次'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(container.read(sessionControllerProvider).isLoggedIn, isTrue);
  });

  Future<void> confirmBothDialogs(WidgetTester tester) async {
    await _tapDelete(tester);
    await tester.tap(find.byKey(const Key('deleteAccountContinue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAccountConfirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('取消 Apple 重新授權:不撤銷、不刪帳號、維持登入、沒有失敗提示', (tester) async {
    final cloud = _FakeCloudAuth();
    final revocation = _FakeRevocation()
      ..requestError = const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'canceled',
      );
    final container = await _pump(tester, cloud: cloud, revocation: revocation);

    await confirmBothDialogs(tester);

    expect(revocation.requestCalls, 1);
    expect(revocation.revokeCalls, 0);
    expect(cloud.deleteCalls, 0);
    expect(container.read(sessionControllerProvider).isLoggedIn, isTrue);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Apple 撤銷失敗:帳號仍刪除並登出,UI 顯示手動移除的提示', (tester) async {
    final cloud = _FakeCloudAuth();
    final revocation = _FakeRevocation()..revokeError = Exception('502');
    final container = await _pump(tester, cloud: cloud, revocation: revocation);

    await confirmBothDialogs(tester);

    expect(cloud.deleteCalls, 1);
    expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
    // 提示不再由設定頁以 SnackBar 彈(登出後設定頁會離場):記進 postDeleteNoticeProvider,
    // 由登入頁顯示——見下方 GoRouter 流程測試。
    expect(container.read(postDeleteNoticeProvider), kAppleRevokeFailedMessage);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Apple 撤銷失敗 + 真實路由登出跳轉:登入頁以 AlertDialog 顯示提示,按「知道了」才關', (tester) async {
    final cloud = _FakeCloudAuth();
    final revocation = _FakeRevocation()..revokeError = Exception('502');
    SharedPreferences.setMockInitialValues({kAppleUserIdKey: 'auth-uid-1'});
    final prefs = await SharedPreferences.getInstance();
    final db = openTestDatabase();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        cloudAuthServiceProvider.overrideWithValue(cloud),
        appleRevocationServiceProvider.overrideWithValue(revocation),
        legacyCoreDataFilesProvider.overrideWithValue(
          LegacyCoreDataFiles(supportDirPathProvider: () async => '/nonexistent-legacy-dir'),
        ),
        nativeAppleSignInAvailableProvider.overrideWithValue(true),
        legacyUserDefaultsClearerProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    // 與 router.dart 同結構:session 變動 → 重新評估 redirect,登出就換成登入頁(設定頁的
    // route 被移除)。這正是「疊在設定頁上的 SnackBar/Dialog 會消失」的情境。
    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    container.listen(sessionControllerProvider, (_, _) => refresh.value++);
    final router = GoRouter(
      initialLocation: '/settings',
      refreshListenable: refresh,
      redirect: (context, state) {
        final loggedIn = container.read(sessionControllerProvider).isLoggedIn;
        if (!loggedIn && state.matchedLocation != '/login') return '/login';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => shell,
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsPage())]),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await confirmBothDialogs(tester);

    expect(find.byType(LoginPage), findsOneWidget, reason: '已登出並跳轉到登入頁');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(kAppleRevokeFailedMessage), findsOneWidget);
    expect(container.read(postDeleteNoticeProvider), isNull, reason: '一次性事件,彈出後清掉');

    // 點遮罩不會關(barrierDismissible: false),要按「知道了」。
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.text(kAppleRevokeFailedMessage), findsOneWidget);

    await tester.tap(find.byKey(const Key('postDeleteNoticeAck')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Apple 撤銷成功:刪除並登出,沒有任何提示', (tester) async {
    final cloud = _FakeCloudAuth();
    final revocation = _FakeRevocation();
    final container = await _pump(tester, cloud: cloud, revocation: revocation);

    await confirmBothDialogs(tester);

    expect(revocation.revokeCalls, 1);
    expect(cloud.deleteCalls, 1);
    expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });
}
