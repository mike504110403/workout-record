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
import '../../data/migration/coredata_importer_result.dart'
    show
        kCoreDataImportAttemptsKey,
        kCoreDataImportCompletedKey,
        kCoreDataImportFailedPermanentlyKey,
        kCoreDataImportStatsKeys,
        kCoreDataImportedUserIdKey;
import '../../data/migration/legacy_prefs_importer.dart'
    show kLegacyPrefsImportCompletedKey, kLegacyPrefsPersonalDataKeys;
import '../../data/providers.dart' show appDatabaseProvider;
import '../onboarding/onboarding_controller.dart' show kOnboardingPersonalDataKeys;
import '../onboarding/onboarding_status.dart'
    show kHasCompletedOnboardingKey, onboardingStatusProvider;
import 'shared_preferences_provider.dart';

const kAppleUserIdKey = 'apple_user_id';
const kAppleUserNameKey = 'apple_user_name';
const kAppleUserEmailKey = 'apple_user_email';

/// 本機 Drift 資料的擁有者(帳號隔離,見
/// `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`)。本機
/// Drift 永遠只屬於一個帳號:這個 key 存那個帳號的登入身分 id(Apple
/// userIdentifier 或 [kTestLoginUserIdPrefsKey] 的測試登入 UUID)。跨登出
/// 持續存在(見 [SessionController.signOut] 的說明),只有偵測到「別的」
/// 登入身分且使用者二次確認後才會換人(見 [SessionController.confirmClearAndContinueLogin])。
const kLocalDataOwnerUserIdKey = 'local_data_owner_user_id';

/// 模擬器 / Android / Web 共用的測試登入身分(姓名/信箱固定,id 是裝置產生
/// 的 UUID,見 [SessionController.signInTest] 開頭註解)。
const kTestLoginUserName = '測試用戶';
const kTestLoginUserEmail = 'test@example.com';

/// 測試登入身分的 UUID 存在哪個 prefs key——裝置層級,不隨登出清除(見
/// [SessionController.signOut])。
const kTestLoginUserIdPrefsKey = 'test_login_user_id';

const _genericLoginErrorMessage = '登入失敗,請稍後再試';

/// 登入流程的結果——controller 不自己彈 UI,只回傳這個型別描述狀態,
/// 呼叫端(login_page)依此決定要不要彈警告對話框(seam 設計,見帳號隔離
/// 決策文件與波 2 brief)。同樣的資訊也會反映在 [SessionState.ownerConflict]
/// 上,方便 UI 用既有的 `ref.listen<SessionState>` 反應式更新;回傳值則讓
/// controller 測試不需要額外 pump 就能直接斷言結果。
sealed class LoginOutcome {
  const LoginOutcome();
}

/// 登入成功:session 已建立。若這是這台裝置第一次有人登入,也已完成本機
/// 資料 owner 認領;若登入者本來就是 owner,資料原封不動。
class LoginSuccess extends LoginOutcome {
  const LoginSuccess();
}

/// 登入身分與目前本機資料 owner 不同——尚未清除任何資料、尚未認領、尚未
/// 建立 session。呼叫端須彈警告對話框二次確認:
/// - 確認 → 呼叫 [SessionController.confirmClearAndContinueLogin]。
/// - 取消 → 呼叫 [SessionController.cancelOwnerConflict](或什麼都不做,
///   狀態就留在 conflict,下一次同一身分登入會再次回傳同一個結果)。
///
/// **勿覆寫 `==`/`hashCode`。** `login_page.dart` 用 `!=` 比對這個型別的
/// instance 判斷「要不要彈警告對話框」,刻意走預設的 identity 比較——每次
/// controller 偵測到衝突都會 new 一個 instance,「同一個 instance 沒變」不
/// 重複彈,「換一個新 instance」(即使欄位內容一模一樣,例如同一身分連續
/// 觸發兩次衝突)一定要再彈一次。若之後改成 value equality(欄位相同視為
/// 同一個),欄位內容相同的連續衝突會被 `ref.listen` 的 previous != next
/// 判斷成「沒變」而悄悄吃掉第二次警告,使用者可能因此在沒看到警告的情況下
/// 被清空資料。
class LoginOwnerConflict extends LoginOutcome {
  const LoginOwnerConflict({
    required this.pendingUserId,
    required this.pendingUserName,
    required this.pendingUserEmail,
  });

  final String pendingUserId;
  final String pendingUserName;
  final String pendingUserEmail;
}

/// 登入失敗(例如 Apple 授權失敗、使用者取消)。錯誤文案走既有的
/// [SessionState.errorMessage] + `ref.listen` 那條路顯示,這個型別只是讓
/// 呼叫端能用 switch 窮舉所有結果。
class LoginFailure extends LoginOutcome {
  const LoginFailure();
}

class SessionState {
  const SessionState({
    this.appleUserId,
    this.appleUserName,
    this.appleUserEmail,
    this.isLoading = false,
    this.errorMessage,
    this.ownerConflict,
  });

  final String? appleUserId;
  final String? appleUserName;
  final String? appleUserEmail;
  final bool isLoading;
  final String? errorMessage;

  /// 非 null 代表目前有一筆待確認的「換帳號」衝突(見 [LoginOwnerConflict])
  /// ——login_page 應該彈警告對話框,確認/取消後這個欄位就會被清掉。
  final LoginOwnerConflict? ownerConflict;

  bool get isLoggedIn => appleUserId != null && appleUserId!.isNotEmpty;

  SessionState copyWith({
    String? appleUserId,
    String? appleUserName,
    String? appleUserEmail,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    LoginOwnerConflict? ownerConflict,
    bool clearOwnerConflict = false,
  }) {
    return SessionState(
      appleUserId: appleUserId ?? this.appleUserId,
      appleUserName: appleUserName ?? this.appleUserName,
      appleUserEmail: appleUserEmail ?? this.appleUserEmail,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      ownerConflict: clearOwnerConflict ? null : (ownerConflict ?? this.ownerConflict),
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
  /// exception 內容塞進 UI。拿到身分後交給 [_completeLoginWithOwnerCheck]
  /// 做帳號隔離的 owner 檢查(見該方法文件)。
  Future<LoginOutcome> signInWithApple() async {
    state = state.copyWith(isLoading: true, clearError: true, clearOwnerConflict: true);
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
        return const LoginFailure();
      }

      final fullName = [credential.givenName, credential.familyName]
          .where((part) => part != null && part.isNotEmpty)
          .join(' ');
      final userName = fullName.isNotEmpty ? fullName : '用戶';
      final userEmail = credential.email ?? '未提供電子郵件';

      return await _completeLoginWithOwnerCheck(
        userId: userId,
        userName: userName,
        userEmail: userEmail,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        state = state.copyWith(isLoading: false, clearError: true);
        return const LoginFailure();
      }
      state = state.copyWith(isLoading: false, errorMessage: _genericLoginErrorMessage);
      return const LoginFailure();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _genericLoginErrorMessage);
      return const LoginFailure();
    }
  }

  /// 模擬器 / Android / Web 的測試登入 fallback(對等 iOS
  /// `handleSimulatorLogin`)。身分不再用共用常數——首次測試登入時生成 UUID
  /// 存進 prefs,之後沿用同一個 id,避免未來接上同步後所有測試登入用戶
  /// 撞成同一個帳號。拿到身分後交給 [_completeLoginWithOwnerCheck] 做帳號
  /// 隔離的 owner 檢查(見該方法文件)。
  Future<LoginOutcome> signInTest() async {
    state = state.copyWith(isLoading: true, clearError: true, clearOwnerConflict: true);
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      var testUserId = prefs.getString(kTestLoginUserIdPrefsKey);
      if (testUserId == null || testUserId.isEmpty) {
        testUserId = generateUuidV4();
        await prefs.setString(kTestLoginUserIdPrefsKey, testUserId);
      }

      return await _completeLoginWithOwnerCheck(
        userId: testUserId,
        userName: kTestLoginUserName,
        userEmail: kTestLoginUserEmail,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _genericLoginErrorMessage);
      return const LoginFailure();
    }
  }

  /// 帳號隔離核心邏輯(見 `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`
  /// 行為規格 1-3),兩條登入路(Apple / 測試登入)拿到身分後都走這裡:
  /// - 本機還沒有 owner → 認領(寫入 [kLocalDataOwnerUserIdKey] = 這次登入的
  ///   身分),照常完成登入。血緣 key([kCoreDataImportedUserIdKey])在這個
  ///   分支刻意不動——第一個認領的帳號要完整享有既有血緣行為(見
  ///   [confirmClearAndContinueLogin] 的一次性消耗說明)。
  /// - owner 就是自己 → 資料不動,照常完成登入。
  /// - owner 是別人 → 不清除、不認領、不建立 session,回傳
  ///   [LoginOwnerConflict] 讓呼叫端(login_page)彈警告對話框二次確認。
  Future<LoginOutcome> _completeLoginWithOwnerCheck({
    required String userId,
    required String userName,
    required String userEmail,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final ownerId = prefs.getString(kLocalDataOwnerUserIdKey);

    if (ownerId == null || ownerId.isEmpty) {
      await prefs.setString(kLocalDataOwnerUserIdKey, userId);
    } else if (ownerId != userId) {
      final conflict = LoginOwnerConflict(
        pendingUserId: userId,
        pendingUserName: userName,
        pendingUserEmail: userEmail,
      );
      state = state.copyWith(isLoading: false, ownerConflict: conflict);
      return conflict;
    }

    await _persistSession(userId: userId, userName: userName, userEmail: userEmail);
    return const LoginSuccess();
  }

  /// 警告對話框「確認清除並繼續」後呼叫:清空 Drift 全表(見
  /// [AppDatabase.resetForNewOwner])+ Onboarding 個資 prefs
  /// ([kOnboardingPersonalDataKeys])+ 完成旗標([kHasCompletedOnboardingKey])
  /// +血緣 key([kCoreDataImportedUserIdKey],一次性消耗——這個 key 只服務
  /// 「第一個認領本機資料的帳號」,換人時連同它指向的 Users row 一起在
  /// [AppDatabase.resetForNewOwner] 裡被清掉,這裡額外刪 key 本身是防禦性
  /// 收尾,確保沒有殘留的 prefs 值可能被誤讀)+ **退休裝置層匯入**(否則
  /// 重啟後 `main.dart` 的 `importIfNeeded` 會把舊 iOS SQLite 的前人歷史
  /// 匯回給新帳號,見「實作補充」節,security review 2026-08-04 major):
  /// CoreData 匯入完成旗標設 true、失敗旗標與重試次數歸零、legacy prefs
  /// 匯入旗標設 true,連同上一位帳號留下的 legacy 個資與匯入統計 prefs 一併
  /// 清除,然後認領 owner 為這次的登入身分、完成登入。
  ///
  /// 呼叫前提:[SessionState.ownerConflict] 不為 null——沒有待確認的衝突時
  /// 直接 no-op 並回傳 [LoginFailure],不會誤觸發清除。守門判斷與清掉
  /// `ownerConflict`/設 `isLoading: true` 刻意放在同一個同步區塊(方法一開頭,
  /// 中間沒有任何 `await`)——避免 async gap 期間被重入:第二次呼叫在第一次
  /// 的清除還沒做完前進來,會因為 `ownerConflict` 已經被第一次呼叫同步清掉
  /// 而直接落入 no-op 分支,不會有兩個清除同時對同一份 Drift 資料操作。
  ///
  /// 失敗(例如清空 DB 時拋例外)不讓例外往外炸——吃下來,走既有的
  /// [SessionState.errorMessage] 一般化文案路徑,`isLoading` 收尾為 false、
  /// `ownerConflict` 維持已清除(不重新彈同一個衝突,使用者可以重新登入
  /// 觸發新的一輪判斷)。
  Future<LoginOutcome> confirmClearAndContinueLogin() async {
    final pending = state.ownerConflict;
    if (pending == null) return const LoginFailure();
    state = state.copyWith(isLoading: true, clearOwnerConflict: true);

    try {
      final db = ref.read(appDatabaseProvider);
      await db.resetForNewOwner();

      final prefs = ref.read(sharedPreferencesProvider);
      for (final key in kOnboardingPersonalDataKeys) {
        await prefs.remove(key);
      }
      await prefs.remove(kHasCompletedOnboardingKey);
      ref.invalidate(onboardingStatusProvider);
      await prefs.remove(kCoreDataImportedUserIdKey);

      // 退休裝置層匯入——標成「已匯入過」讓 importIfNeeded 之後直接 skip,
      // 不會把前人的舊 iOS SQLite 歷史匯回給新帳號。
      await prefs.setBool(kCoreDataImportCompletedKey, true);
      await prefs.setBool(kCoreDataImportFailedPermanentlyKey, false);
      await prefs.setInt(kCoreDataImportAttemptsKey, 0);
      await prefs.setBool(kLegacyPrefsImportCompletedKey, true);

      // 上一位帳號殘留的 legacy 個資 + 匯入統計 prefs 一併清除(顯式清單,
      // 不做前綴掃描)。
      for (final key in kLegacyPrefsPersonalDataKeys) {
        await prefs.remove(key);
      }
      for (final key in kCoreDataImportStatsKeys) {
        await prefs.remove(key);
      }

      await prefs.setString(kLocalDataOwnerUserIdKey, pending.pendingUserId);

      await _persistSession(
        userId: pending.pendingUserId,
        userName: pending.pendingUserName,
        userEmail: pending.pendingUserEmail,
      );
      return const LoginSuccess();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        clearOwnerConflict: true,
        errorMessage: _genericLoginErrorMessage,
      );
      return const LoginFailure();
    }
  }

  /// 警告對話框「取消」後呼叫:不清除任何東西、不認領、不建立 session,
  /// 只是把待確認的衝突狀態收掉,留在登入頁。
  void cancelOwnerConflict() {
    if (state.ownerConflict == null) return;
    state = state.copyWith(isLoading: false, clearOwnerConflict: true);
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
  /// DB 層帳號隔離(見 `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`)
  /// 刻意**不**掛在 signOut 上——[kLocalDataOwnerUserIdKey] 與 Drift 資料
  /// 都要跨登出持續存在,同帳號登出後回來才能無縫接續使用;真正觸發清除
  /// 的是下一次登入時偵測到「別的」帳號([_completeLoginWithOwnerCheck] +
  /// [confirmClearAndContinueLogin]),不是這裡。
  Future<void> signOut() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(kAppleUserIdKey);
    await prefs.remove(kAppleUserNameKey);
    await prefs.remove(kAppleUserEmailKey);

    for (final key in kOnboardingPersonalDataKeys) {
      await prefs.remove(key);
    }
    await prefs.remove(kHasCompletedOnboardingKey);
    ref.invalidate(onboardingStatusProvider);

    state = const SessionState();
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);
