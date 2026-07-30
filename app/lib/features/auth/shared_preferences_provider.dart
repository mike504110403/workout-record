// 全 App 共用的 SharedPreferences provider。
//
// `SharedPreferences.getInstance()` 是 async,但 App 一啟動(main.dart)就會
// 先 await 拿到實例,再用 ProviderContainer 的 override 把它塞進來,讓
// SessionController / OnboardingController / PrivacyConsentController 都能
// 用 ref.watch 同步讀到已經 ready 的 SharedPreferences,不需要各自處理
// FutureProvider 的 loading 狀態。
//
// 測試一律要覆寫這個 provider(見 test/features/auth、test/features/onboarding
// 底下的用法:`SharedPreferences.setMockInitialValues({...})` +
// `sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance())`)。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider 必須在 main.dart(或測試的 ProviderScope / '
    'ProviderContainer)用實際的 SharedPreferences 實例 override 之後才能使用。',
  );
});
