// 登入頁。文案逐字對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Auth/AppleIDLoginView.swift`。
//
// 三平台按鈕邏輯(對等 iOS `#if targetEnvironment(simulator)`,但涵蓋範圍
// 更廣,見 [showTestLoginProvider] 開頭註解):
// - iOS release build:sign_in_with_apple 的真 Apple ID 登入按鈕。
// - iOS debug/profile build、Android、Web:「測試登入」fallback 按鈕。
// - Google 登入:占位、disabled,標示「即將推出」——真 OAuth 掛同步波,
//   本波不接,不得新增 google_sign_in 依賴。
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'session_controller.dart';

/// 是否顯示測試登入 fallback 按鈕。對等 iOS `#if targetEnvironment(simulator)`
/// 的精神,但改用「是不是 release build」判斷:
/// - debug / profile build(含 iOS 模擬器與真機):一律顯示。
/// - Web:一律顯示(沒有 release/debug 的 App Store 上架顧慮)。
/// - Android:同步波前還沒有真 OAuth,一律顯示。
/// - iOS release build:不顯示,只能用真 Apple ID 登入——`kReleaseMode` 是
///   編譯期常數,但 `Platform.isAndroid` 是執行期訊號,不是編譯期就被消去
///   的死碼,所以整個 `||` 運算式不是編譯期常數。實際效果是:iOS release
///   build 執行到這裡時,`!kReleaseMode` 恆為 false、`kIsWeb` 恆為 false、
///   `Platform.isAndroid` 在 iOS 裝置上恆為 false,三者都不成立,沒有其他
///   觸發路徑會讓這個 provider 在 iOS release build 回傳 true。
///
/// 抽成 provider 是為了讓測試可以覆寫這個條件,不用真的切換編譯模式——見
/// [LoginPage.build] 的 `showRealAppleSignIn`:它直接用這個 provider 的值
/// 決定要不要顯示真 Apple 登入按鈕,不額外疊加 `Platform.isIOS` 判斷(那個
/// 判斷在 `flutter test` host 上恆為 false,會讓這個 provider 的覆寫失去
/// 意義——`showTestLoginProvider` 的 false 分支本來就只在 iOS release
/// build 成立,`!kIsWeb && !Platform.isAndroid` 已經蘊含 iOS,重複檢查
/// `Platform.isIOS` 是多餘且不可測的)。
final showTestLoginProvider = Provider<bool>((ref) {
  return !kReleaseMode || kIsWeb || Platform.isAndroid;
});

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final showTestLogin = ref.watch(showTestLoginProvider);
    final showRealAppleSignIn = !showTestLogin;

    ref.listen<SessionState>(sessionControllerProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('登入錯誤'),
            content: Text(next.errorMessage ?? '未知錯誤'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('確定'),
              ),
            ],
          ),
        );
        // 錯誤是一次性事件:彈完立刻清掉,讓下一次即使是同一則錯誤訊息也能
        // 再次觸發 ref.listen 的 previous != next 比較。
        ref.read(sessionControllerProvider.notifier).clearError();
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 32),
                Text(
                  '歡迎使用 WorkoutRecord',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  '請使用 Apple ID 登入以開始使用',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (showRealAppleSignIn)
                  SignInWithAppleButton(
                    onPressed: () =>
                        ref.read(sessionControllerProvider.notifier).signInWithApple(),
                  )
                else
                  SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: ElevatedButton(
                      key: const Key('testLoginButton'),
                      onPressed: () =>
                          ref.read(sessionControllerProvider.notifier).signInTest(),
                      child: const Text('測試登入'),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: OutlinedButton(
                    key: const Key('googleSignInPlaceholderButton'),
                    onPressed: null,
                    child: const Text('使用 Google 登入(即將推出)'),
                  ),
                ),
                if (session.isLoading) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '登入中...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '隱私保護',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const _PrivacyBullet('使用 Apple ID 安全登入'),
                      const _PrivacyBullet('訓練記錄僅儲存於您的裝置本機'),
                      const _PrivacyBullet('僅收集必要的帳號資訊'),
                      const _PrivacyBullet('不用於廣告或第三方分享'),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyBullet extends StatelessWidget {
  const _PrivacyBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
