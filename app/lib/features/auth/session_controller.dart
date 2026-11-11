// 登入 session 控制。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Services/AppleIDAuthService.swift`
// 的角色。兩種模式(切換點 [cloudAuthServiceProvider],見 cloud_auth.dart):
// - 雲端模式(Supabase):Apple 登入走 `signInWithIdToken`,session 的
//   userId([SessionState.appleUserId])是 **Supabase auth uid**;啟動時以
//   Supabase 既有 session 恢復登入態;登出同時 `auth.signOut()`。
// - 非雲端模式(USE_MOCK / 測試 / 未設定 Supabase):維持原本的「本機
//   session」——不接任何後端,帳號身分就是 SharedPreferences 裡的三個 key。
// 兩種模式都把身分寫進同樣三個 prefs key,帳號隔離(owner 比對)邏輯共用。
//
// key 命名對應 iOS 的 AppleIDUserID/UserName/UserEmail(UserDefaults),但
// 刻意換成新的 snake_case key(`apple_user_id` 等),不是同一份——舊資料
// 匯入(legacy_prefs_importer.dart)刻意不搬登入身分,見該檔案開頭註解。
import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
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
import '../../data/migration/legacy_coredata_files.dart'
    show
        legacyAppleUserIdReaderProvider,
        legacyCoreDataFilesProvider,
        legacyUserDefaultsClearerProvider;
import '../../data/migration/legacy_prefs_importer.dart'
    show kLegacyPrefsImportCompletedKey, kLegacyPrefsPersonalDataKeys;
import '../../data/providers.dart' show appDatabaseProvider, userRepositoryProvider;
import '../../data/repositories/offline/offline_prefs_keys.dart';
import '../onboarding/onboarding_controller.dart' show kOnboardingPersonalDataKeys;
import '../onboarding/onboarding_status.dart'
    show kHasCompletedOnboardingKey, onboardingStatusProvider;
import 'cloud_auth.dart';
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

/// 刪帳號時 Apple 授權沒能撤銷(帳號本身已刪成功)的提示——撤銷失敗不擋刪帳號,
/// 但要讓使用者知道還有一步可以手動做。
const kAppleRevokeFailedMessage =
    'Apple 授權未能撤銷,可到 iPhone 設定 > Apple ID > 使用 Apple 登入 手動移除';

/// 刪帳號成功後、登出之前由 [SessionController.deleteAccount] 設定的「登入頁要顯示的
/// 一次性通知」(目前只有 [kAppleRevokeFailedMessage])。
///
/// 為什麼不在設定頁彈:登出會讓 GoRouter redirect 回登入頁,設定頁的 route 被移除,
/// 疊在它上面的 SnackBar/Dialog 會一起消失(實測 root navigator 上的 dialog 也會被帶走),
/// 使用者就看不到「還要手動移除 Apple 授權」。所以改在刪帳號流程裡先記下,由登入頁
/// 顯示、使用者按「知道了」才關。
class PostDeleteNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String message) => state = message;

  void clear() => state = null;
}

final postDeleteNoticeProvider = NotifierProvider<PostDeleteNotice, String?>(PostDeleteNotice.new);

/// 雲端模式在沒有原生 Apple 登入的平台(Web/Android)按下 Apple 登入時的文案。
const kAppleSignInUnsupportedMessage = '此平台暫不支援 Apple 登入,請改用 iPhone 登入';

/// 雲端模式下測試登入不可用(測試登入的本機 UUID 不是 Supabase 登入者)。
const kTestLoginUnavailableInCloudMessage = '雲端模式不支援測試登入';

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

/// [SessionController.deleteAccount] 的結果。
enum DeleteAccountResult {
  /// 雲端帳號已刪、Apple 授權已撤銷(或本來就不需要撤銷:非 iOS)、本機已清、已登出。
  deleted,

  /// 帳號已刪、本機已清、已登出,但 Apple 授權沒撤銷成功——提示
  /// [kAppleRevokeFailedMessage] 已由 deleteAccount 記進 [postDeleteNoticeProvider],
  /// 登入頁會顯示(設定頁隨登出離場,在那裡彈會看不到)。
  deletedRevokeFailed,

  /// 使用者在 Apple 重新授權時取消——整個刪除中止,什麼都沒動,UI 不顯示錯誤。
  cancelled,

  /// 雲端刪除失敗(或不在雲端模式/未登入),本機什麼都沒動,可重試。
  failed,
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
  /// 啟動還原登入態。
  ///
  /// 雲端模式:以 Supabase 既有 session(supabase_flutter 從本機儲存恢復)為準,
  /// 而且 prefs 的 [kAppleUserIdKey] 必須等於該 auth uid 才算已登入——prefs
  /// 只在 [_persistSession] 寫入,也就是通過帳號隔離 owner 檢查後;Supabase
  /// 已登入但還卡在 owner 衝突(或衝突時 App 被砍掉)的情況不能靠重啟繞過
  /// 警告對話框直接進 App。沒有 Supabase session 一律未登入(不看 prefs)。
  @override
  SessionState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final cloud = ref.watch(cloudAuthServiceProvider);
    if (cloud != null) {
      // Supabase session 被動結束(refresh 失敗/遠端登出)→ 收掉本機登入態。
      // 主動 signOut 也會觸發此事件,_clearLocalSession 可重入,無副作用。
      ref.listen(cloudSessionEndedProvider, (_, next) {
        if (next.hasValue && state.isLoggedIn) {
          unawaited(_clearLocalSession());
        }
      });
      final user = cloud.currentUser;
      if (user == null || prefs.getString(kAppleUserIdKey) != user.id) {
        return const SessionState();
      }
      return SessionState(
        appleUserId: user.id,
        appleUserName: prefs.getString(kAppleUserNameKey),
        appleUserEmail: prefs.getString(kAppleUserEmailKey),
      );
    }
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
  ///
  /// 雲端模式改走 [_signInWithAppleCloud](Supabase `signInWithIdToken`)。
  Future<LoginOutcome> signInWithApple() async {
    final cloud = ref.read(cloudAuthServiceProvider);
    if (cloud != null) return _signInWithAppleCloud(cloud);

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
        appleUserIdentifier: userId,
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

  /// 雲端模式的 Apple 登入:原生 Apple 授權(帶 SHA-256 nonce)→ Supabase
  /// `signInWithIdToken`,以 auth uid 當登入身分交給
  /// [_completeLoginWithOwnerCheck](帳號隔離比對也用 auth uid)。姓名/信箱
  /// 規則同本機版(Apple 只在首次授權給姓名;信箱缺時退回 Supabase 帳號信箱)。
  ///
  /// Supabase 已登入但後續步驟(owner 檢查、ensure users row)失敗時,盡力
  /// `auth.signOut()` 收掉半套 session,再走一般化錯誤文案。
  Future<LoginOutcome> _signInWithAppleCloud(CloudAuthService cloud) async {
    state = state.copyWith(isLoading: true, clearError: true, clearOwnerConflict: true);

    final CloudAppleSignInResult result;
    try {
      result = await cloud.signInWithApple();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        state = state.copyWith(isLoading: false, clearError: true);
        return const LoginFailure();
      }
      state = state.copyWith(isLoading: false, errorMessage: _genericLoginErrorMessage);
      return const LoginFailure();
    } on UnsupportedError {
      state = state.copyWith(isLoading: false, errorMessage: kAppleSignInUnsupportedMessage);
      return const LoginFailure();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _genericLoginErrorMessage);
      return const LoginFailure();
    }

    try {
      final fullName = [result.givenName, result.familyName]
          .where((part) => part != null && part.isNotEmpty)
          .join(' ');
      final userName = fullName.isNotEmpty ? fullName : '用戶';
      final userEmail = result.appleEmail ?? result.user.email ?? '未提供電子郵件';

      return await _completeLoginWithOwnerCheck(
        userId: result.user.id,
        userName: userName,
        userEmail: userEmail,
        appleUserIdentifier: result.appleUserIdentifier,
      );
    } catch (e) {
      await _cloudSignOutQuietly();
      state = state.copyWith(isLoading: false, errorMessage: _genericLoginErrorMessage);
      return const LoginFailure();
    }
  }

  /// 模擬器 / Android / Web 的測試登入 fallback(對等 iOS
  /// `handleSimulatorLogin`)。身分不再用共用常數——首次測試登入時生成 UUID
  /// 存進 prefs,之後沿用同一個 id,避免未來接上同步後所有測試登入用戶
  /// 撞成同一個帳號。拿到身分後交給 [_completeLoginWithOwnerCheck] 做帳號
  /// 隔離的 owner 檢查(見該方法文件)。
  ///
  /// 雲端模式不可用(登入頁也不顯示按鈕):直接回 [LoginFailure] 並給
  /// [kTestLoginUnavailableInCloudMessage]。
  Future<LoginOutcome> signInTest() async {
    if (ref.read(cloudAuthServiceProvider) != null) {
      state = state.copyWith(
        isLoading: false,
        clearOwnerConflict: true,
        errorMessage: kTestLoginUnavailableInCloudMessage,
      );
      return const LoginFailure();
    }
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
  ///   身分),照常完成登入;**例外**:本機有 CoreData 匯入的舊資料、舊 iOS
  ///   留下的 `AppleIDUserID` 存在、且跟這次的 [appleUserIdentifier] 不同
  ///   (共用裝置,舊資料屬於另一個 Apple ID)→ 走 owner 衝突流程,不直接認領
  ///   (見 [_legacyDataBelongsToAnotherAppleId])。血緣 key([kCoreDataImportedUserIdKey])在這個
  ///   分支刻意不動——第一個認領的帳號要完整享有既有血緣行為(見
  ///   [confirmClearAndContinueLogin] 的一次性消耗說明)。
  /// - owner 就是自己 → 資料不動,照常完成登入。
  /// - owner 是別人 → 不清除、不認領、不建立 session,回傳
  ///   [LoginOwnerConflict] 讓呼叫端(login_page)彈警告對話框二次確認。
  Future<LoginOutcome> _completeLoginWithOwnerCheck({
    required String userId,
    required String userName,
    required String userEmail,
    String? appleUserIdentifier,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final ownerId = prefs.getString(kLocalDataOwnerUserIdKey);

    final noOwnerYet = ownerId == null || ownerId.isEmpty;
    final conflictsWithOwner = !noOwnerYet && ownerId != userId;
    if (conflictsWithOwner ||
        (noOwnerYet && await _legacyDataBelongsToAnotherAppleId(appleUserIdentifier))) {
      final conflict = LoginOwnerConflict(
        pendingUserId: userId,
        pendingUserName: userName,
        pendingUserEmail: userEmail,
      );
      state = state.copyWith(isLoading: false, ownerConflict: conflict);
      return conflict;
    }
    if (noOwnerYet) {
      await prefs.setString(kLocalDataOwnerUserIdKey, userId);
    }

    await _ensureCloudUserRowIfOnboarded(userId: userId, userName: userName, userEmail: userEmail);
    await _persistSession(userId: userId, userName: userName, userEmail: userEmail);
    return const LoginSuccess();
  }

  /// 本機的舊 iOS 資料是不是屬於「別的 Apple ID」。四個條件同時成立才算:
  /// 有 Apple identifier、本機有舊資料、舊 iOS 的 `AppleIDUserID` 讀得到、且兩者
  /// 不同。「有舊資料」= [kCoreDataImportedUserIdKey] 非空(匯入成功時才會寫),
  /// **或**舊 `WorkoutRecord.sqlite` 還在(匯入尚未完成或失敗——這時資料還沒進
  /// Drift,但之後的重試會把它匯進來並被這次登入的人認領,所以同樣要比對)。
  /// 同 team 同 bundle 下同一個 Apple ID 的 identifier 恆等,所以不同 = 不同人。
  ///
  /// 任何一項缺(包含讀舊值失敗)都回 false,維持原本「第一個登入者認領」——
  /// 這是 fail-open,不能因為讀不到舊值就把正牌用戶擋在自己的資料外。
  ///
  /// **注意:identifier 為 null(Apple 沒回,或未來非 Apple 的登入方式如 Google)
  /// 目前同樣 fail-open 直接認領。** 加 Google 登入時必須改成:本機有舊資料、卻拿
  /// 不到可比對的 identifier → 走 owner conflict,否則 Google 登入者能認領別人的
  /// 舊資料。
  Future<bool> _legacyDataBelongsToAnotherAppleId(String? currentAppleUserId) async {
    if (currentAppleUserId == null || currentAppleUserId.isEmpty) return false;
    final imported = ref.read(sharedPreferencesProvider).getString(kCoreDataImportedUserIdKey);
    final hasImportedData = imported != null && imported.isNotEmpty;
    if (!hasImportedData && !await _legacySqliteExists()) return false;
    final String? legacyAppleId;
    try {
      legacyAppleId = await ref.read(legacyAppleUserIdReaderProvider)();
    } catch (_) {
      return false;
    }
    if (legacyAppleId == null || legacyAppleId.isEmpty) return false;
    return legacyAppleId != currentAppleUserId;
  }

  /// 舊 `WorkoutRecord.sqlite` 是否存在;查詢失敗視為不存在(fail-open,同上)。
  Future<bool> _legacySqliteExists() async {
    try {
      return await ref.read(legacyCoreDataFilesProvider).exists();
    } catch (_) {
      return false;
    }
  }

  /// 雲端模式且 Onboarding 已完成時,確保 Supabase `public.users` 有登入者
  /// 那一列(`UserRepository.ensure(authUid)`)——給「略過 Onboarding」的路徑
  /// (同帳號登入時旗標仍在、恢復 session)當安全網,否則各頁 `getById`
  /// 查無此人。Onboarding 未完成時刻意**不**呼叫,交給 OnboardingController
  /// 自己 ensure:它靠 ensure 的「本次新建」結果決定要不要寫初始體重,這裡
  /// 先建列會讓新用戶永遠拿到 isNewUser = false(2026-11-10 裁示 A)。
  /// 非雲端模式 no-op(本機行為不變)。
  Future<void> _ensureCloudUserRowIfOnboarded({
    required String userId,
    required String? userName,
    required String? userEmail,
  }) async {
    if (ref.read(cloudAuthServiceProvider) == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    if (!(prefs.getBool(kHasCompletedOnboardingKey) ?? false)) return;
    await ref.read(userRepositoryProvider).ensure(userId, name: userName, email: userEmail);
  }

  /// 啟動恢復 session 後由 `main.dart` 呼叫一次:雲端模式、已登入且
  /// Onboarding 已完成時 ensure 登入者的 users 列(見
  /// [_ensureCloudUserRowIfOnboarded])。例外往外拋,由呼叫端記錄。
  Future<void> ensureCloudUserRowOnRestore() async {
    final session = state;
    final userId = session.appleUserId;
    if (!session.isLoggedIn || userId == null) return;
    await _ensureCloudUserRowIfOnboarded(
      userId: userId,
      userName: session.appleUserName,
      userEmail: session.appleUserEmail,
    );
  }

  /// 盡力登出 Supabase(雲端模式);失敗吞掉——呼叫點都是收尾路徑,本機
  /// 狀態照常清除。非雲端模式 no-op。
  Future<void> _cloudSignOutQuietly() async {
    final cloud = ref.read(cloudAuthServiceProvider);
    if (cloud == null) return;
    try {
      await cloud.signOut();
    } catch (_) {
      // 收尾路徑:登出 Supabase 失敗不影響本機狀態清除。
    }
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
      await _wipeLocalDataAndRetireImports();
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(kLocalDataOwnerUserIdKey, pending.pendingUserId);

      await _ensureCloudUserRowIfOnboarded(
        userId: pending.pendingUserId,
        userName: pending.pendingUserName,
        userEmail: pending.pendingUserEmail,
      );
      await _persistSession(
        userId: pending.pendingUserId,
        userName: pending.pendingUserName,
        userEmail: pending.pendingUserEmail,
      );
      return const LoginSuccess();
    } catch (e) {
      await _cloudSignOutQuietly();
      state = state.copyWith(
        isLoading: false,
        clearOwnerConflict: true,
        errorMessage: _genericLoginErrorMessage,
      );
      return const LoginFailure();
    }
  }

  /// 清空 Drift 全表 + onboarding 個資與完成旗標 + 血緣 key,並**退休裝置層
  /// 匯入**(標成已匯入,`importIfNeeded` 之後直接 skip,舊 iOS SQLite 的歷史
  /// 不會再被匯回),連同 legacy 個資與匯入統計 prefs。換帳號清除與刪除帳號
  /// 共用;不動 owner key(由呼叫端決定認領或移除)。
  Future<void> _wipeLocalDataAndRetireImports() async {
    final db = ref.read(appDatabaseProvider);
    await db.resetForNewOwner();

    final prefs = ref.read(sharedPreferencesProvider);
    for (final key in kOnboardingPersonalDataKeys) {
      await prefs.remove(key);
    }
    await prefs.remove(kHasCompletedOnboardingKey);
    ref.invalidate(onboardingStatusProvider);
    await prefs.remove(kCoreDataImportedUserIdKey);

    await prefs.setBool(kCoreDataImportCompletedKey, true);
    await prefs.setBool(kCoreDataImportFailedPermanentlyKey, false);
    await prefs.setInt(kCoreDataImportAttemptsKey, 0);
    await prefs.setBool(kLegacyPrefsImportCompletedKey, true);

    // 顯式清單,不做前綴掃描。
    for (final key in kLegacyPrefsPersonalDataKeys) {
      await prefs.remove(key);
    }
    for (final key in kCoreDataImportStatsKeys) {
      await prefs.remove(key);
    }
    // 雲端模式的離線草稿與快取(offline/ 三個裝飾器,key 皆帶命名空間前綴)。
    for (final key in prefs.getKeys().toList()) {
      if (kOfflinePrefsKeyPrefixes.any(key.startsWith)) await prefs.remove(key);
    }
  }

  /// 刪除帳號(只在雲端模式且已登入時有效)。順序:
  /// 1. iOS 才做:重新跑 Apple 授權取得 authorizationCode。使用者取消 → 回
  ///    [DeleteAccountResult.cancelled],整個刪除中止、什麼都不動。其他授權錯誤
  ///    視同撤銷失敗(下一步跳過、不擋刪帳號)。
  /// 2. 呼叫 `apple-revoke` 撤銷 Apple 授權——**必須在雲端刪帳號之前**,之後
  ///    使用者 JWT 就失效了。失敗不擋刪帳號,只記 debugPrint 並回
  ///    [DeleteAccountResult.deletedRevokeFailed] 讓 UI 提示手動移除。
  /// 3. 雲端刪除;失敗回 [DeleteAccountResult.failed],本機什麼都不動(使用者可重試;
  ///    Apple 授權若已撤銷不會復原——可接受:帳號還在,下次登入會重新同意授權,Apple
  ///    的 sub 不變、資料不失;重試時會再走一次 1、2,對已撤銷的授權無害)。
  /// 4. 成功後雲端帳號與資料已不可回復,本機接著:清空 Drift 並退休舊 iOS 匯入
  ///    (否則同裝置再登入會把舊資料重新上傳)、移除 owner key、刪舊 CoreData 的
  ///    三個檔與舊 UserDefaults(Mike 裁示:帳號都刪了,舊資料不該留在裝置上)、
  ///    撤銷失敗時記下登入頁要顯示的提示([postDeleteNoticeProvider])、登出。本機清除失敗不改變
  ///    結果(雲端已刪),仍照常登出。
  ///
  /// 非雲端模式、非 iOS(沒有原生 Apple 登入)略過 Apple 那段。
  Future<DeleteAccountResult> deleteAccount() async {
    final cloud = ref.read(cloudAuthServiceProvider);
    if (cloud == null || !state.isLoggedIn) {
      return DeleteAccountResult.failed;
    }

    var appleRevokeFailed = false;
    final revocation = ref.read(appleRevocationServiceProvider);
    if (revocation != null && ref.read(nativeAppleSignInAvailableProvider)) {
      String? code;
      try {
        code = await revocation.requestAppleAuthorizationCode();
      } on SignInWithAppleAuthorizationException catch (e) {
        if (e.code == AuthorizationErrorCode.canceled) {
          return DeleteAccountResult.cancelled;
        }
        debugPrint('刪帳號:Apple 重新授權失敗(${e.code}),略過撤銷');
        appleRevokeFailed = true;
      } catch (e) {
        debugPrint('刪帳號:Apple 重新授權失敗(${e.runtimeType}),略過撤銷');
        appleRevokeFailed = true;
      }
      if (code != null) {
        try {
          await revocation.revokeAppleAuthorization(code);
        } catch (e) {
          // 只印例外型別,不印內容(避免把 Apple/Edge Function 的回應寫進 log)。
          debugPrint('刪帳號:Apple 授權撤銷失敗(${e.runtimeType})');
          appleRevokeFailed = true;
        }
      }
    }

    try {
      await cloud.deleteAccount();
    } catch (_) {
      return DeleteAccountResult.failed;
    }
    try {
      await _wipeLocalDataAndRetireImports();
      await ref.read(sharedPreferencesProvider).remove(kLocalDataOwnerUserIdKey);
    } catch (_) {
      // 雲端已刪,本機清除盡力而為;下一步登出照做。
    }
    try {
      await ref.read(legacyCoreDataFilesProvider).deleteAll();
      // 舊 iOS 留在 UserDefaults 的個資與 AppleIDUserID 一併清(Mike 裁示「刪帳號資料全沒」)。
      await ref.read(legacyUserDefaultsClearerProvider)();
    } catch (_) {
      // 同上:舊檔/舊偏好刪不掉不影響結果(匯入已被退休旗標擋住,不會再讀)。
    }
    // 雲端已刪成功才通知;必須在登出(會觸發 redirect 離開設定頁)之前記下。
    if (appleRevokeFailed) {
      ref.read(postDeleteNoticeProvider.notifier).show(kAppleRevokeFailedMessage);
    }
    await _cloudSignOutQuietly();
    await _clearLocalSession();
    return appleRevokeFailed ? DeleteAccountResult.deletedRevokeFailed : DeleteAccountResult.deleted;
  }

  /// 警告對話框「取消」後呼叫:不清除任何東西、不認領、不建立 session,
  /// 只是把待確認的衝突狀態收掉,留在登入頁。
  ///
  /// 雲端模式另外盡力登出 Supabase:衝突當下 Supabase 已經登入了待確認的
  /// 帳號,取消後不該留著那個 session(重啟也不會因此進 App,見 [build])。
  void cancelOwnerConflict() {
    if (state.ownerConflict == null) return;
    state = state.copyWith(isLoading: false, clearOwnerConflict: true);
    unawaited(_cloudSignOutQuietly());
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
  ///
  /// 雲端模式先 `auth.signOut()`(失敗吞掉,本機清除照做——不能因為斷網就
  /// 讓使用者登出不了)。
  Future<void> signOut() async {
    await _cloudSignOutQuietly();
    await _clearLocalSession();
  }

  /// 清本機 session key 與 onboarding 個資(登出與雲端 session 被動結束共用)。
  Future<void> _clearLocalSession() async {
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
