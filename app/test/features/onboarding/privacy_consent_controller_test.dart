// PrivacyConsentController seam:兩個勾選框都是本地狀態,只有
// agreeAndContinue() 在兩者皆勾時才寫入 SharedPreferences 三個 key(對等
// iOS PrivacyConsentView 按鈕的 disabled 條件)。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/privacy_consent_controller.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('初始狀態:兩個勾選框皆未勾,isFullyAgreed 為 false', () async {
    final container = await _container();
    final state = container.read(privacyConsentControllerProvider);
    expect(state.hasAgreedToAnalytics, isFalse);
    expect(state.hasAgreedToPrivacy, isFalse);
    expect(state.isFullyAgreed, isFalse);
  });

  test('只勾一個時,isFullyAgreed 仍是 false', () async {
    final container = await _container();
    final notifier = container.read(privacyConsentControllerProvider.notifier);

    notifier.setAnalyticsAgreed(true);
    expect(container.read(privacyConsentControllerProvider).isFullyAgreed, isFalse);

    notifier.setPrivacyAgreed(true);
    expect(container.read(privacyConsentControllerProvider).isFullyAgreed, isTrue);
  });

  test('agreeAndContinue():兩者皆勾才寫入 SharedPreferences 三個 key', () async {
    final container = await _container();
    final notifier = container.read(privacyConsentControllerProvider.notifier);

    // 只勾一個就呼叫 agreeAndContinue,應該是 no-op。
    notifier.setAnalyticsAgreed(true);
    await notifier.agreeAndContinue();
    final prefsAfterPartial = container.read(sharedPreferencesProvider);
    expect(prefsAfterPartial.containsKey(kHasAgreedToPrivacyKey), isFalse);

    notifier.setPrivacyAgreed(true);
    await notifier.agreeAndContinue();

    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getBool(kHasAgreedToAnalyticsKey), isTrue);
    expect(prefs.getBool(kHasAgreedToPrivacyKey), isTrue);
    expect(prefs.containsKey(kPrivacyConsentDateKey), isTrue);

    final state = container.read(privacyConsentControllerProvider);
    expect(state.isFullyAgreed, isTrue);
    expect(state.consentDate, isNotNull);
  });
}
