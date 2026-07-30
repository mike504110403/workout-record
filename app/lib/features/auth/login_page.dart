// 登入頁。文案逐字對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Auth/AppleIDLoginView.swift`。
//
// 三平台按鈕邏輯(對等 iOS `#if targetEnvironment(simulator)`):
// - iOS 真機:sign_in_with_apple 的真 Apple ID 登入按鈕。
// - 模擬器 / Android / Web:「測試登入」fallback 按鈕。
// - Google 登入:占位、disabled,標示「即將推出」——真 OAuth 掛同步波,
//   本波不接,不得新增 google_sign_in 依賴。
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'session_controller.dart';

/// iOS 模擬器把 `SIMULATOR_DEVICE_NAME` 塞進 process 環境變數,原生 Swift
/// 用 `#if targetEnvironment(simulator)` 編譯期判斷,Flutter 沒有對應的編譯期
/// 旗標,改用這個執行期訊號對等判斷。
bool _isIosSimulator() {
  if (kIsWeb || !Platform.isIOS) return false;
  return Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');
}

bool _showRealAppleSignIn() {
  if (kIsWeb || !Platform.isIOS) return false;
  return !_isIosSimulator();
}

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

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
                if (_showRealAppleSignIn())
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
