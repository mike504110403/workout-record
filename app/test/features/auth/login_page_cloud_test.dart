// LoginPage 雲端模式:測試登入按鈕不顯示;有原生 Apple 登入的平台顯示真
// Apple 按鈕,沒有的(Web/Android)顯示明確提示而不是按鈕。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:workout_record/features/auth/cloud_auth.dart';
import 'package:workout_record/features/auth/login_page.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';

class _NoopCloudAuth implements CloudAuthService {
  @override
  CloudAuthUser? get currentUser => null;

  @override
  Future<CloudAppleSignInResult> signInWithApple() => throw UnimplementedError();

  @override
  Future<void> signOut() async {}
}

Future<void> _pump(WidgetTester tester, {required bool nativeApple}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cloudAuthServiceProvider.overrideWithValue(_NoopCloudAuth()),
        nativeAppleSignInAvailableProvider.overrideWithValue(nativeApple),
        // 即使 showTestLogin 條件成立(debug build),雲端模式也不顯示測試登入。
        showTestLoginProvider.overrideWithValue(true),
      ],
      child: const MaterialApp(home: LoginPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('雲端模式 + 有原生 Apple 登入:顯示 Apple 按鈕,不顯示測試登入', (tester) async {
    await _pump(tester, nativeApple: true);

    expect(find.byType(SignInWithAppleButton), findsOneWidget);
    expect(find.byKey(const Key('testLoginButton')), findsNothing);
    expect(find.byKey(const Key('appleSignInUnavailableNotice')), findsNothing);
  });

  testWidgets('雲端模式 + 無原生 Apple 登入(Web/Android):顯示明確提示,不顯示任何登入按鈕',
      (tester) async {
    await _pump(tester, nativeApple: false);

    expect(find.byKey(const Key('appleSignInUnavailableNotice')), findsOneWidget);
    expect(find.text(kAppleSignInUnsupportedMessage), findsOneWidget);
    expect(find.byType(SignInWithAppleButton), findsNothing);
    expect(find.byKey(const Key('testLoginButton')), findsNothing);
  });
}
