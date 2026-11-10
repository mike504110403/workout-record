// SettingsPage 刪除帳號:只在雲端模式顯示;兩段確認後才呼叫雲端刪除;
// 失敗提示且維持登入。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/cloud_auth.dart';
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

Future<ProviderContainer> _pump(WidgetTester tester, {CloudAuthService? cloud}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: 'auth-uid-1'});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      cloudAuthServiceProvider.overrideWithValue(cloud),
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
}
