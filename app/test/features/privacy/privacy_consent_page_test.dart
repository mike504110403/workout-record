// PrivacyConsentPage widget seam:兩勾選框皆勾之前「同意並繼續」是
// disabled,勾完才 enabled;文案逐字對照 iOS PrivacyConsentView。勾選框是
// 頁面本地狀態,不透過 controller。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/privacy/privacy_consent_page.dart';

Future<void> _pumpPage(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: PrivacyConsentPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('顯示標題與兩個勾選框文案', (tester) async {
    await _pumpPage(tester);
    expect(find.text('隱私權同意'), findsOneWidget);
    expect(find.text('我同意收集匿名使用數據以改善服務'), findsOneWidget);
    expect(find.text('我已閱讀並同意隱私政策'), findsOneWidget);
  });

  testWidgets('未勾選任何勾選框時,「同意並繼續」是 disabled', (tester) async {
    await _pumpPage(tester);
    final button = tester.widget<FilledButton>(find.byKey(const Key('agreeAndContinueButton')));
    expect(button.onPressed, isNull);
  });

  testWidgets('只勾一個時,「同意並繼續」仍是 disabled', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.byKey(const Key('analyticsConsentCheckbox')));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byKey(const Key('agreeAndContinueButton')));
    expect(button.onPressed, isNull);
  });

  testWidgets('兩個都勾選後,「同意並繼續」變成 enabled', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.byKey(const Key('analyticsConsentCheckbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacyConsentCheckbox')));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byKey(const Key('agreeAndContinueButton')));
    expect(button.onPressed, isNotNull);
  });
}
