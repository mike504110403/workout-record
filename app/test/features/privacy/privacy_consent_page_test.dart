// PrivacyConsentPage widget seam:單一「我已閱讀並同意」勾選框勾之前
// 「同意並繼續」是 disabled,勾了才 enabled;按下後兩個既有同意 key 都寫入
// (舊版兩個勾選框合併成一個,語意不變)。勾選框是頁面本地狀態,不透過
// controller。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';
import 'package:workout_record/features/privacy/privacy_consent_page.dart';

Future<ProviderContainer> _pumpPage(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PrivacyConsentPage()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('顯示標題與單一勾選框文案(舊的兩個勾選框已合併)', (tester) async {
    await _pumpPage(tester);
    expect(find.text('隱私權同意'), findsOneWidget);
    expect(find.text('我已閱讀並同意以上條款，包含將訓練資料儲存於雲端伺服器'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(find.byKey(const Key('analyticsConsentCheckbox')), findsNothing);
    expect(find.text('我已閱讀並同意隱私政策'), findsNothing);
  });

  testWidgets('同意頁內文與隱私政策一致:含 Apple、Supabase 東京、登出不清全部本機資料', (tester) async {
    await _pumpPage(tester);
    expect(find.textContaining('Apple'), findsWidgets);
    expect(find.textContaining('Supabase'), findsWidgets);
    expect(find.textContaining('日本東京'), findsOneWidget);
    // 舊說法「登出時會清除本機的個人資料」「不與第三方分享」與政策矛盾,不得殘留。
    expect(find.text('登出時會清除本機的個人資料'), findsNothing);
    expect(find.textContaining('不與第三方分享您的個人資料'), findsNothing);
    expect(find.textContaining('訓練資料快取、草稿與舊版匯入資料會保留'), findsOneWidget);
    expect(find.textContaining('不會上傳到我們的伺服器'), findsOneWidget);
  });

  testWidgets('未勾選時,「同意並繼續」是 disabled', (tester) async {
    await _pumpPage(tester);
    final button = tester.widget<FilledButton>(find.byKey(const Key('agreeAndContinueButton')));
    expect(button.onPressed, isNull);
  });

  testWidgets('勾一個就夠:「同意並繼續」變成 enabled,取消勾選又 disabled', (tester) async {
    await _pumpPage(tester);
    FilledButton button() =>
        tester.widget<FilledButton>(find.byKey(const Key('agreeAndContinueButton')));

    await tester.tap(find.byKey(const Key('privacyConsentCheckbox')));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('privacyConsentCheckbox')));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);
  });

  testWidgets('勾選後按「同意並繼續」:兩個既有同意 key 與同意日期都寫入', (tester) async {
    final container = await _pumpPage(tester);
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getBool(kHasAgreedToAnalyticsKey), isNull);
    expect(prefs.getBool(kHasAgreedToPrivacyKey), isNull);

    await tester.tap(find.byKey(const Key('privacyConsentCheckbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agreeAndContinueButton')));
    await tester.pumpAndSettle();

    expect(prefs.getBool(kHasAgreedToAnalyticsKey), isTrue);
    expect(prefs.getBool(kHasAgreedToPrivacyKey), isTrue);
    expect(prefs.containsKey(kPrivacyConsentDateKey), isTrue);
    expect(container.read(privacyConsentControllerProvider).isAgreed, isTrue);
  });
}
