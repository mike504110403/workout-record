// LoginPage widget seam:標題/副標文案存在、測試登入按鈕存在(測試環境不是
// iOS 真機,一律走 fallback 按鈕)、Google 登入佔位按鈕存在且 disabled、
// 點下測試登入後 session 變成已登入。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:workout_record/features/auth/login_page.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';

Future<void> _pumpLoginPage(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: LoginPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('顯示標題、副標與隱私保護四點說明', (tester) async {
    await _pumpLoginPage(tester);

    expect(find.text('歡迎使用 WorkoutRecord'), findsOneWidget);
    expect(find.text('請使用 Apple ID 登入以開始使用'), findsOneWidget);
    expect(find.text('隱私保護'), findsOneWidget);
    expect(find.text('使用 Apple ID 安全登入'), findsOneWidget);
    expect(find.text('訓練記錄僅儲存於您的裝置本機'), findsOneWidget);
    expect(find.text('僅收集必要的帳號資訊'), findsOneWidget);
    expect(find.text('不用於廣告或第三方分享'), findsOneWidget);
  });

  testWidgets('測試環境(非 iOS 真機)顯示測試登入 fallback 按鈕', (tester) async {
    await _pumpLoginPage(tester);
    expect(find.byKey(const Key('testLoginButton')), findsOneWidget);
  });

  testWidgets('showTestLoginProvider 覆寫為 false 時,顯示真 Apple 登入按鈕而非測試登入按鈕',
      (tester) async {
    // 讓 provider 抽象的理由成立(見 login_page.dart showTestLoginProvider
    // 開頭註解):不用真的切到 iOS release build,直接覆寫這個 provider 就能
    // 驗證「不顯示測試登入時,走真 Apple 登入按鈕」這條路徑。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          showTestLoginProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SignInWithAppleButton), findsOneWidget);
    expect(find.byKey(const Key('testLoginButton')), findsNothing);
  });

  testWidgets('Google 登入是 disabled 的佔位按鈕', (tester) async {
    await _pumpLoginPage(tester);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('googleSignInPlaceholderButton')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('使用 Google 登入(即將推出)'), findsOneWidget);
  });

  testWidgets('點下測試登入後,session 變成已登入', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('testLoginButton')));
    await tester.pumpAndSettle();

    expect(container.read(sessionControllerProvider).isLoggedIn, isTrue);
  });
}
