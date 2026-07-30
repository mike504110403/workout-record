// SessionController seam:build() 從 SharedPreferences 讀初始狀態、
// signInTest()/signOut() 寫回 SharedPreferences 並更新 state、
// signInWithApple() 在沒有原生 Apple 登入管道(測試環境)時要優雅失敗而不是
// 讓例外往外炸。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';

Future<ProviderContainer> _containerWithPrefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('build', () {
    test('SharedPreferences 沒有任何 apple_user_* key 時,isLoggedIn 為 false', () async {
      final container = await _containerWithPrefs({});
      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.appleUserId, isNull);
    });

    test('SharedPreferences 已有 apple_user_id 時,直接以此還原成已登入狀態', () async {
      final container = await _containerWithPrefs({
        kAppleUserIdKey: 'existing-user',
        kAppleUserNameKey: 'Existing User',
        kAppleUserEmailKey: 'existing@example.com',
      });
      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isTrue);
      expect(state.appleUserName, 'Existing User');
      expect(state.appleUserEmail, 'existing@example.com');
    });
  });

  group('signInTest', () {
    test('首次測試登入時產生 UUID 身分,寫入 SharedPreferences 並更新 state', () async {
      final container = await _containerWithPrefs({});
      await container.read(sessionControllerProvider.notifier).signInTest();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isTrue);
      expect(state.appleUserId, isNotNull);
      expect(state.appleUserId, isNotEmpty);
      expect(state.appleUserName, kTestLoginUserName);
      expect(state.isLoading, isFalse);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kAppleUserIdKey), state.appleUserId);
      expect(prefs.getString(kTestLoginUserIdPrefsKey), state.appleUserId);
    });

    test('第二次測試登入沿用同一個 UUID 身分,不重新生成', () async {
      final container = await _containerWithPrefs({});
      final notifier = container.read(sessionControllerProvider.notifier);

      await notifier.signInTest();
      final firstId = container.read(sessionControllerProvider).appleUserId;

      await notifier.signOut();
      await notifier.signInTest();
      final secondId = container.read(sessionControllerProvider).appleUserId;

      expect(secondId, firstId);
    });
  });

  group('signOut', () {
    test('清掉三個 session key、顯式列舉的 Onboarding 個資 key 與完成旗標', () async {
      final container = await _containerWithPrefs({
        kAppleUserIdKey: 'existing-user',
        kAppleUserNameKey: 'Existing User',
        kAppleUserEmailKey: 'existing@example.com',
        kHasCompletedOnboardingKey: true,
        'user_gender': '男性',
        'user_current_weight': 70.0,
      });

      await container.read(sessionControllerProvider.notifier).signOut();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.appleUserId, isNull);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kAppleUserIdKey), isFalse);
      expect(prefs.containsKey('user_gender'), isFalse);
      expect(prefs.containsKey('user_current_weight'), isFalse);
      expect(prefs.containsKey(kHasCompletedOnboardingKey), isFalse);
    });

    test('顯式契約:不在 kOnboardingPersonalDataKeys 清單內的 user_ 前綴 key 不會被清除', () async {
      // 對照舊行為(掃描所有 user_ 前綴 key)——改成顯式列舉清單後,清單外的
      // key(即使剛好也是 user_ 前綴)不再被隱式掃到,見
      // onboarding_controller.dart 的 kOnboardingPersonalDataKeys 註解。
      final container = await _containerWithPrefs({
        kAppleUserIdKey: 'existing-user',
        'user_not_an_onboarding_key': 'should survive',
      });

      await container.read(sessionControllerProvider.notifier).signOut();

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('user_not_an_onboarding_key'), 'should survive');
    });

    test('隱私同意三個 key 是裝置層級,登出不清', () async {
      final container = await _containerWithPrefs({
        kAppleUserIdKey: 'existing-user',
        'has_agreed_to_analytics': true,
        'has_agreed_to_privacy': true,
        'privacy_consent_date': 1234567890,
      });

      await container.read(sessionControllerProvider.notifier).signOut();

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getBool('has_agreed_to_analytics'), isTrue);
      expect(prefs.getBool('has_agreed_to_privacy'), isTrue);
      expect(prefs.getInt('privacy_consent_date'), 1234567890);
    });

    test('測試登入 UUID(test_login_user_id)是裝置層級,登出不清', () async {
      final container = await _containerWithPrefs({});
      final notifier = container.read(sessionControllerProvider.notifier);
      await notifier.signInTest();
      final testId = container.read(sessionControllerProvider).appleUserId;

      await notifier.signOut();

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kTestLoginUserIdPrefsKey), testId);
    });
  });

  group('signInWithApple', () {
    test('測試環境沒有原生 Apple 登入管道時,優雅失敗並記錄一般化錯誤訊息', () async {
      final container = await _containerWithPrefs({});
      await container.read(sessionControllerProvider.notifier).signInWithApple();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNotNull);
    });
  });

  group('clearError', () {
    test('清掉目前的錯誤訊息', () async {
      final container = await _containerWithPrefs({});
      final notifier = container.read(sessionControllerProvider.notifier);
      await notifier.signInWithApple();
      expect(container.read(sessionControllerProvider).errorMessage, isNotNull);

      notifier.clearError();

      expect(container.read(sessionControllerProvider).errorMessage, isNull);
    });
  });
}
