// PrivacyConsentController seam:controller 只反映「已經落地的同意」——
// build() 從 SharedPreferences 還原 consentDate,agreeAndContinue() 無條件
// 寫入三個 key。兩個勾選框是 PrivacyConsentPage 的頁面本地狀態,不在這裡
// (見 test/features/privacy/privacy_consent_page_test.dart)。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';

Future<ProviderContainer> _container([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('初始狀態:SharedPreferences 沒有落地過同意時,isAgreed 為 false', () async {
    final container = await _container();
    final state = container.read(privacyConsentControllerProvider);
    expect(state.consentDate, isNull);
    expect(state.isAgreed, isFalse);
  });

  test('build():SharedPreferences 已有 privacy_consent_date 時直接還原成已同意', () async {
    final now = DateTime.now();
    final container = await _container({
      kPrivacyConsentDateKey: now.millisecondsSinceEpoch,
    });
    final state = container.read(privacyConsentControllerProvider);
    expect(state.isAgreed, isTrue);
    expect(state.consentDate, isNotNull);
  });

  test('agreeAndContinue():無條件寫入三個 key 並更新 state 為已同意', () async {
    final container = await _container();
    final notifier = container.read(privacyConsentControllerProvider.notifier);

    expect(container.read(privacyConsentControllerProvider).isAgreed, isFalse);

    await notifier.agreeAndContinue();

    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getBool(kHasAgreedToAnalyticsKey), isTrue);
    expect(prefs.getBool(kHasAgreedToPrivacyKey), isTrue);
    expect(prefs.containsKey(kPrivacyConsentDateKey), isTrue);

    final state = container.read(privacyConsentControllerProvider);
    expect(state.isAgreed, isTrue);
    expect(state.consentDate, isNotNull);
  });
}
