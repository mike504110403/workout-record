// SessionController seam:build() 從 SharedPreferences 讀初始狀態、
// signInTest()/signOut() 寫回 SharedPreferences 並更新 state、
// signInWithApple() 在沒有原生 Apple 登入管道(測試環境)時要優雅失敗而不是
// 讓例外往外炸。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';

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
    test('寫入固定的測試登入身分到 SharedPreferences 並更新 state', () async {
      final container = await _containerWithPrefs({});
      await container.read(sessionControllerProvider.notifier).signInTest();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isTrue);
      expect(state.appleUserId, kTestLoginUserId);
      expect(state.appleUserName, kTestLoginUserName);
      expect(state.isLoading, isFalse);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kAppleUserIdKey), kTestLoginUserId);
    });
  });

  group('signOut', () {
    test('清掉三個 session key,onboarding 完成旗標不受影響', () async {
      final container = await _containerWithPrefs({
        kAppleUserIdKey: 'existing-user',
        kAppleUserNameKey: 'Existing User',
        kAppleUserEmailKey: 'existing@example.com',
        'has_completed_onboarding': true,
      });

      await container.read(sessionControllerProvider.notifier).signOut();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.appleUserId, isNull);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.containsKey(kAppleUserIdKey), isFalse);
      expect(prefs.getBool('has_completed_onboarding'), isTrue);
    });
  });

  group('signInWithApple', () {
    test('測試環境沒有原生 Apple 登入管道時,優雅失敗並記錄錯誤訊息', () async {
      final container = await _containerWithPrefs({});
      await container.read(sessionControllerProvider.notifier).signInWithApple();

      final state = container.read(sessionControllerProvider);
      expect(state.isLoggedIn, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNotNull);
    });
  });
}
