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

import '../../core/utils/uuid.dart';
import '../onboarding/onboarding_controller.dart' show kOnboardingPersonalDataKeys;
import '../onboarding/onboarding_status.dart' show kHasCompletedOnboardingKey;
import 'shared_preferences_provider.dart';

const kAppleUserIdKey = 'apple_user_id';
const kAppleUserNameKey = 'apple_user_name';
const kAppleUserEmailKey = 'apple_user_email';

/// 模擬器 / Android / Web 共用的測試登入身分(姓名/信箱固定,id 是裝置產生
/// 的 UUID,見 [SessionController.signInTest] 開頭註解)。
const kTestLoginUserName = '測試用戶';
const kTestLoginUserEmail = 'test@example.com';

/// 測試登入身分的 UUID 存在哪個 prefs key——裝置層級,不隨登出清除(見
/// [SessionController.signOut])。
const kTestLoginUserIdPrefsKey = 'test_login_user_id';

const _genericLoginErrorMessage = '登入失敗,請稍後再試';

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

  /// 真機 Apple ID 登入(對等 iOS `handleAppleIDCredential`)。使用者取消
  /// 授權(canceled)靜默處理,不當錯誤;其他失敗一律給一般化文案,不把
  /// exception 內容塞進 UI。
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
        state = state.copyWith(isLoading: false, errorMessage: _genericLoginErrorMessage);
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
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        state = state.copyWith(isLoading: false, clearError: true);
        return;
      }
      state = state.copyWith(isLoading: false, errorMessage: _genericLoginErrorMessage);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _genericLoginErrorMessage);
    }
  }

  /// 模擬器 / Android / Web 的測試登入 fallback(對等 iOS
  /// `handleSimulatorLogin`)。身分不再用共用常數——首次測試登入時生成 UUID
  /// 存進 prefs,之後沿用同一個 id,避免未來接上同步後所有測試登入用戶
  /// 撞成同一個帳號。
  Future<void> signInTest() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      var testUserId = prefs.getString(kTestLoginUserIdPrefsKey);
      if (testUserId == null || testUserId.isEmpty) {
        testUserId = generateUuidV4();
        await prefs.setString(kTestLoginUserIdPrefsKey, testUserId);
      }

      await _persistSession(
        userId: testUserId,
        userName: kTestLoginUserName,
        userEmail: kTestLoginUserEmail,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _genericLoginErrorMessage);
    }
  }

  /// 清掉目前的錯誤訊息(對等錯誤彈窗顯示過一次就消化掉,是一次性事件)。
  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(clearError: true);
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

  /// 登出:清 session 三個 key,並清掉 onboarding 個人資料(顯式列舉的
  /// [kOnboardingPersonalDataKeys],見 features/onboarding/onboarding_controller.dart
  /// ——不再用 `user_` 前綴掃描 prefs 全部 key,避免隱式契約:哪些 key 算
  /// 「Onboarding 個資」由 onboarding 那側明確列出,這裡照單清除)與
  /// `has_completed_onboarding` 旗標,避免下一個換上來的帳號(不同 Apple ID
  /// 或重新測試登入)直接吃到前一個人的 Onboarding 資料。
  ///
  /// 刻意偏離 iOS 現況(iOS 版登出不清 Onboarding 資料)——iOS 是單帳號本機
  /// App,沒有換帳號吃到別人資料的疑慮,Flutter 版三平台 + 未來多帳號同步
  /// 才需要這層保護。隱私同意三個 key 是裝置層級的同意紀錄,不受影響。
  ///
  /// DB 層帳號隔離(換帳號時清掉 Drift 裡屬於其他 userId 的資料,或查詢一律
  /// 帶 userId 篩選)待決策(見 review 2026-07-30),本次不做——目前僅清
  /// prefs 側的個資,Drift 資料表本身不受 signOut 影響。
  Future<void> signOut() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(kAppleUserIdKey);
    await prefs.remove(kAppleUserNameKey);
    await prefs.remove(kAppleUserEmailKey);

    for (final key in kOnboardingPersonalDataKeys) {
      await prefs.remove(key);
    }
    await prefs.remove(kHasCompletedOnboardingKey);

    state = const SessionState();
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);
