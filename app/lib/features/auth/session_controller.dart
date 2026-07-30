// 登入 session 控制。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Services/AppleIDAuthService.swift`
// 的角色,但這裡刻意只做「本機 session」——不接任何後端 / 真 Auth token,
// 帳號身分就是 SharedPreferences 裡的三個 key。
//
// key 命名對應 iOS 的 AppleIDUserID/UserName/UserEmail(UserDefaults),但
// 刻意換成新的 snake_case key(`apple_user_id` 等),不是同一份——舊資料
// 匯入(legacy_prefs_importer.dart)刻意不搬登入身分,見該檔案開頭註解。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'shared_preferences_provider.dart';

const kAppleUserIdKey = 'apple_user_id';
const kAppleUserNameKey = 'apple_user_name';
const kAppleUserEmailKey = 'apple_user_email';

/// 模擬器 / Android / Web 共用的測試登入身分,對等 iOS
/// `AppleIDLoginView.handleSimulatorLogin()` 的模擬器測試登入。
const kTestLoginUserId = 'flutter.test.user.12345';
const kTestLoginUserName = '測試用戶';
const kTestLoginUserEmail = 'test@example.com';

class SessionState {
  const SessionState({
    this.appleUserId,
    this.appleUserName,
    this.appleUserEmail,
    this.isLoading = false,
    this.errorMessage,
  });

  final String? appleUserId;
  final String? appleUserName;
  final String? appleUserEmail;
  final bool isLoading;
  final String? errorMessage;

  bool get isLoggedIn => appleUserId != null && appleUserId!.isNotEmpty;

  SessionState copyWith({
    String? appleUserId,
    String? appleUserName,
    String? appleUserEmail,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SessionState(
      appleUserId: appleUserId ?? this.appleUserId,
      appleUserName: appleUserName ?? this.appleUserName,
      appleUserEmail: appleUserEmail ?? this.appleUserEmail,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return SessionState(
      appleUserId: prefs.getString(kAppleUserIdKey),
      appleUserName: prefs.getString(kAppleUserNameKey),
      appleUserEmail: prefs.getString(kAppleUserEmailKey),
    );
  }

  /// 真機 Apple ID 登入(對等 iOS `handleAppleIDCredential`)。
  Future<void> signInWithApple() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final userId = credential.userIdentifier;
      if (userId == null || userId.isEmpty) {
        state = state.copyWith(isLoading: false, errorMessage: '登入失敗: 找不到使用者識別碼');
        return;
      }

      final fullName = [credential.givenName, credential.familyName]
          .where((part) => part != null && part.isNotEmpty)
          .join(' ');
      final userName = fullName.isNotEmpty ? fullName : '用戶';
      final userEmail = credential.email ?? '未提供電子郵件';

      await _persistSession(
        userId: userId,
        userName: userName,
        userEmail: userEmail,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: '登入失敗: $e');
    }
  }

  /// 模擬器 / Android / Web 的測試登入 fallback(對等 iOS
  /// `handleSimulatorLogin`)。
  Future<void> signInTest() async {
    state = state.copyWith(isLoading: true, clearError: true);
    await _persistSession(
      userId: kTestLoginUserId,
      userName: kTestLoginUserName,
      userEmail: kTestLoginUserEmail,
    );
  }

  Future<void> _persistSession({
    required String userId,
    required String userName,
    required String userEmail,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(kAppleUserIdKey, userId);
    await prefs.setString(kAppleUserNameKey, userName);
    await prefs.setString(kAppleUserEmailKey, userEmail);

    state = SessionState(
      appleUserId: userId,
      appleUserName: userName,
      appleUserEmail: userEmail,
      isLoading: false,
    );
  }

  /// 登出:清 session 三個 key,Onboarding 完成旗標不清(對等 iOS 現況)。
  Future<void> signOut() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(kAppleUserIdKey);
    await prefs.remove(kAppleUserNameKey);
    await prefs.remove(kAppleUserEmailKey);
    state = const SessionState();
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);
