// 帳號隔離的「真實組裝路徑」整合測試(見
// `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md` 與波 2
// brief 驗收標準第 6、4 點)。
//
// 用真 in-memory Drift + mock prefs + 真 ProviderContainer,串接
// SessionController + OnboardingController + autoCompleteOnboardingForUpgradedUsersIfNeeded
// 三者的真實互動,不 override 掉任何一段待測邏輯——owner 檢查、血緣判斷、
// Onboarding 完成流程全部走生產程式碼。
//
// 情境設計:裝置一開始有 CoreData 匯入血緣(coredata_imported_user_id 指向
// 一筆既有 Users row),模擬「舊 App 升級用戶」的裝置狀態。
// - 帳號 A 是這台裝置第一個登入的帳號(owner 從無到有的認領)——應該完整
//   享有血緣行為:Onboarding 自動跳過、_ensureUserRow 沿用既有 row,不新建
//   第二筆。
// - 帳號 B 換帳號登入,觸發 owner 衝突,確認清除後——血緣不得再綁定給 B:
//   舊 Users row 應該已經隨 Drift 全表清空一起消失,B 走全新 Onboarding、
//   新建自己的 Users row。
//
// 因為 signInTest() 的測試登入身分是「裝置層級 UUID,重登沿用同一個」,這裡
// 用直接改寫 kTestLoginUserIdPrefsKey 模擬「換一個登入身分出現」——這只是
// 換掉『誰在敲門』,owner 檢查、血緣判斷、清空/認領的邏輯本身完全沒有被
// stub 掉,仍是生產程式碼在跑。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/db/app_database.dart';
import 'package:workout_record/data/migration/coredata_importer_result.dart'
    show kCoreDataImportedUserIdKey;
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_controller.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';

import '../../data/test_helpers.dart';

const _legacyImportedUserId = 'legacy-imported-user';

void main() {
  test(
      '血緣情境:帳號 A 首登認領後完整沿用匯入 row + 自動跳過 Onboarding;'
      '帳號 B 確認清除登入後不綁到舊 row、須走全新 Onboarding', () async {
    SharedPreferences.setMockInitialValues({
      kCoreDataImportedUserIdKey: _legacyImportedUserId,
    });
    final prefs = await SharedPreferences.getInstance();
    final db = openTestDatabase();
    await seedTestUser(db, id: _legacyImportedUserId);

    // 舊資料再加一筆體重紀錄,證明「確認清除」是真的清 Drift,不是只清
    // Users 表。
    final now = DateTime.now();
    await db.into(db.bodyWeights).insert(
          BodyWeightsCompanion.insert(
            id: 'legacy-bw',
            userId: _legacyImportedUserId,
            measuredAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final session = container.read(sessionControllerProvider.notifier);
    final onboarding = container.read(onboardingControllerProvider.notifier);

    // ---- 帳號 A:這台裝置第一個登入的帳號(owner 從無到有) ----
    final aOutcome = await session.signInTest();
    expect(aOutcome, isA<LoginSuccess>());
    final userIdA = container.read(sessionControllerProvider).appleUserId;
    expect(userIdA, isNotNull);

    final ownerAfterA = prefs.getString(kLocalDataOwnerUserIdKey);
    expect(ownerAfterA, userIdA);

    // 升級用戶自動跳過檢查(main.dart 開機流程的同一個函式):血緣仍在,
    // 應該直接標記完成,不需要 A 真的跑一次 Onboarding 精靈。
    await autoCompleteOnboardingForUpgradedUsersIfNeeded(container);
    expect(container.read(onboardingStatusProvider), isTrue);

    // 即使 A 還是跑了一次 Onboarding(例如設定頁重新進入),_ensureUserRow
    // 仍應沿用既有的匯入 row,不新建第二筆、不補初始體重。
    onboarding.setWeightText('80');
    await onboarding.complete();

    final usersAfterA = await db.select(db.users).get();
    expect(usersAfterA, hasLength(1));
    expect(usersAfterA.single.id, _legacyImportedUserId);

    final bodyWeightsAfterA = await db.select(db.bodyWeights).get();
    expect(bodyWeightsAfterA, hasLength(1)); // 沿用既有 row,沒有補寫初始體重
    expect(bodyWeightsAfterA.single.id, 'legacy-bw');

    // ---- 帳號 B:換一個登入身分出現,觸發 owner 衝突 ----
    // 真實 UI 流程裡,login_page 只在登出狀態才會顯示,所以「換帳號登入」前
    // 一定先經過 signOut()——owner key 與 Drift 資料跨登出持續存在(驗收
    // 標準第 7 點),簽出後才輪到 B 的登入嘗試觸發 owner 衝突。
    await session.signOut();
    expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);
    expect(prefs.getString(kLocalDataOwnerUserIdKey), ownerAfterA); // owner 不受 signOut 影響
    expect(await db.select(db.users).get(), hasLength(1)); // Drift 不受 signOut 影響

    const userIdB = 'device-b-test-login-uuid';
    await prefs.setString(kTestLoginUserIdPrefsKey, userIdB);

    final conflictOutcome = await session.signInTest();
    expect(conflictOutcome, isA<LoginOwnerConflict>());
    expect(container.read(sessionControllerProvider).isLoggedIn, isFalse);

    // 確認前,舊資料原封不動、血緣 key 也還在。
    expect(await db.select(db.users).get(), hasLength(1));
    expect(prefs.getString(kCoreDataImportedUserIdKey), _legacyImportedUserId);

    final confirmOutcome = await session.confirmClearAndContinueLogin();
    expect(confirmOutcome, isA<LoginSuccess>());
    expect(container.read(sessionControllerProvider).appleUserId, userIdB);
    expect(prefs.getString(kLocalDataOwnerUserIdKey), userIdB);

    // 血緣 key 一次性消耗:清除後不得再綁定任何後續帳號。
    expect(prefs.containsKey(kCoreDataImportedUserIdKey), isFalse);
    // 完成旗標走 prefs 層級核對(對齊既有 signOut 測試的做法)——
    // onboardingStatusProvider 的 in-memory state 只在明確呼叫
    // markCompleted() 時才更新,不會因為底層 prefs 被外部改寫就自動重讀,
    // 這裡驗證的是 confirmClearAndContinueLogin() 真的把 prefs 的旗標移除。
    expect(prefs.containsKey(kHasCompletedOnboardingKey), isFalse);

    // Drift 全表已清空(舊 Users row 與其體重紀錄都不在了)。
    expect(await db.select(db.users).get(), isEmpty);
    expect(await db.select(db.bodyWeights).get(), isEmpty);

    // B 走全新 Onboarding:_ensureUserRow 找不到血緣可沿用,必須用自己的
    // 登入身分新建一筆,並補寫初始體重(真正的新使用者)。
    onboarding.setWeightText('65');
    await onboarding.complete();

    final usersAfterB = await db.select(db.users).get();
    expect(usersAfterB, hasLength(1));
    expect(usersAfterB.single.id, userIdB);
    expect(usersAfterB.single.id, isNot(_legacyImportedUserId));

    final bodyWeightsAfterB = await db.select(db.bodyWeights).get();
    expect(bodyWeightsAfterB, hasLength(1));
    expect(bodyWeightsAfterB.single.userId, userIdB);
    expect(bodyWeightsAfterB.single.weight, 65);
  });
}
