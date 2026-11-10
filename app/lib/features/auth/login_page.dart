// 登入頁。文案逐字對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Auth/AppleIDLoginView.swift`。
//
// 三平台按鈕邏輯(對等 iOS `#if targetEnvironment(simulator)`,但涵蓋範圍
// 更廣,見 [showTestLoginProvider] 開頭註解):
// - iOS release build:sign_in_with_apple 的真 Apple ID 登入按鈕。
// - iOS debug/profile build、Android、Web:「測試登入」fallback 按鈕。
// - Google 登入:占位、disabled,標示「即將推出」——真 OAuth 掛同步波,
//   本波不接,不得新增 google_sign_in 依賴。
//
// 雲端模式([cloudAuthServiceProvider] 非 null)覆蓋上面的規則:測試登入
// 不顯示(本機 UUID 不是 Supabase 登入者,資料層會全部失敗);有原生 Apple
// 登入的平台(iOS/macOS)顯示真 Apple 登入按鈕,沒有的(Web/Android)顯示
// 明確提示而不是呼叫(Google 登入之後補)。
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/theme/app_tokens.dart';
import '../settings/about/about_page.dart' show PrivacyPolicyPage;
import 'cloud_auth.dart';
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
    final cloudMode = ref.watch(cloudAuthServiceProvider) != null;
    final nativeAppleAvailable = ref.watch(nativeAppleSignInAvailableProvider);
    final showTestLogin = !cloudMode && ref.watch(showTestLoginProvider);
    final showRealAppleSignIn = cloudMode ? nativeAppleAvailable : !showTestLogin;
    final showAppleUnavailableNotice = cloudMode && !nativeAppleAvailable;

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

      // 帳號隔離(見 `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`)
      // ——controller 只回傳/更新狀態,不自己彈 UI,這裡才是真正決定要不要
      // 彈警告對話框的地方。用 `!=` 比對 [LoginOwnerConflict] 物件(沒有覆寫
      // `==`,走 identity 比較)——每次 controller 偵測到衝突都會建一個新
      // instance,所以「同一個 instance 沒變」不會重複彈,「換一個新 instance」
      // (即使欄位內容一樣)一定會彈,對齊 errorMessage 那條路的一次性事件
      // 精神。
      final conflict = next.ownerConflict;
      if (conflict != null && conflict != previous?.ownerConflict) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            // 防 Android 實體/手勢返回鍵繞過警告對話框直接關掉——這個對話框
            // 只能靠「取消」或「刪除並繼續」兩顆按鈕明確做出選擇,不能被
            // 系統返回手勢當成「取消」悄悄吃掉(那樣使用者會誤以為自己
            // 已經取消,但下一次同一身分登入 controller 又會再彈一次,
            // 行為對得上但體驗詭異,乾脆不給返回鍵這條路)。
            canPop: false,
            child: AlertDialog(
              title: const Text('偵測到不同帳號'),
              content: const Text(
                '此裝置保存了另一個帳號的資料,繼續將永久刪除本機所有訓練紀錄,'
                '並以目前登入的帳號重新開始。確定要繼續嗎?',
              ),
              actions: [
                TextButton(
                  key: const Key('ownerConflictCancelButton'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    ref.read(sessionControllerProvider.notifier).cancelOwnerConflict();
                  },
                  child: const Text('取消'),
                ),
                TextButton(
                  key: const Key('ownerConflictConfirmButton'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    ref.read(sessionControllerProvider.notifier).confirmClearAndContinueLogin();
                  },
                  child: const Text('刪除並繼續'),
                ),
              ],
            ),
          ),
        );
      }
    });

    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: AppSpacing.xxl),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: AppRadius.cardRadius,
                    ),
                    child: Icon(
                      Icons.fitness_center,
                      size: 36,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    '歡迎使用 Work It Out',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '請使用 Apple ID 登入以開始使用',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (showRealAppleSignIn)
                    SignInWithAppleButton(
                      onPressed: () =>
                          ref.read(sessionControllerProvider.notifier).signInWithApple(),
                    )
                  else if (showAppleUnavailableNotice)
                    Text(
                      kAppleSignInUnsupportedMessage,
                      key: const Key('appleSignInUnavailableNotice'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    )
                  else
                    SizedBox(
                      height: AppSizes.buttonHeight,
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('testLoginButton'),
                        onPressed: () =>
                            ref.read(sessionControllerProvider.notifier).signInTest(),
                        child: const Text('測試登入'),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: AppSizes.buttonHeight,
                    width: double.infinity,
                    child: OutlinedButton(
                      key: const Key('googleSignInPlaceholderButton'),
                      onPressed: null,
                      child: const Text('使用 Google 登入(即將推出)'),
                    ),
                  ),
                  if (session.isLoading) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '登入中...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  // 隱私說明條列已移除(與隱私同意頁內容重複),只留入口連結。
                  TextButton(
                    key: const Key('loginPrivacyPolicyLink'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyPage()),
                    ),
                    child: const Text('隱私政策'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
