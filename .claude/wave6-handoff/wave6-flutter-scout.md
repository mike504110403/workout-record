# 波 6 設定 tab 探路報告(Flutter 版,只讀)

專案：/Users/mike/Documents/self/workout-record/app

---

## 1. settings_page 現況

- `lib/features/settings/settings_page.dart:1-58` 全檔:`ConsumerWidget`,`Scaffold` + `AppBar(title: '設定')` + `ListView`。內容目前只有三塊：
  - `SizedBox(height:24)` + 置中「設定」標題文字(:36-38)
  - `ImportRetryTile()`(:40,見下方 3.)——只在 CoreData 匯入永久失敗旗標為 true 時才渲染,平常不可見
  - 一顆 `signOutButton`(:42-47)→ `_confirmSignOut`(:10-30)彈 `AlertDialog` 二次確認 → 確認才呼叫 `sessionControllerProvider.notifier.signOut()`
- 沒有任何「個人資料 / 單位 / 版本資訊 / 隱私」相關 UI,是純 placeholder。
- **Router 掛法**:`lib/router.dart:165-172` — `StatefulShellBranch` 的第 5 個 branch,`path: '/settings'`,`builder: (context, state) => const SettingsPage()`。是 5-tab shell 的固定分頁(非 Navigator.push),`_AppShell._destinations`(:194-220)第五項是「設定」圖示+label。目前 `_refreshForBranch`(:241-262)沒有掛「切到設定分頁要 invalidate 誰」的邏輯(其餘三分頁——首頁/數據/歷史——都有掛),波 6 若設定頁有需要跟著換帳號/資料變動刷新的內容,這條線目前是空的,需自行判斷是否要補。
- 既有 widget 測試:`test/features/settings/settings_logout_test.dart` 全檔——只覆蓋登出按鈕流程(顯示/取消/確認登出清 session),不涉及本波要加的內容。

---

## 2. legacy_prefs_importer 全量對帳

檔案:`lib/data/migration/legacy_prefs_importer.dart`。`importIfNeeded()`(:104-)只在 iOS 且尚未跑過時執行,從原生 MethodChannel(`com.mikelin.workitout/legacy_prefs`)拿 raw map,寫進 `shared_preferences`。**完整清單**(legacy key → SharedPreferences 型別 → 消費方):

| legacy key(dest) | 型別 | 來源(rawKey / GlobalSettings) | 程式碼行 | 消費方(grep 全 lib/ 結果) |
|---|---|---|---|---|
| `legacy_global_settings_json` | String | globalSettingsJson blob 本身 | :129-138 | 無(僅暫存,拆解後不再被讀) |
| `legacy_current_user_id` | String | rawKey `currentUserId` | :194 | 無(僅出現在 `kLegacyPrefsPersonalDataKeys` 清單,供 session_controller 換帳號清除用) |
| `legacy_weight_unit` | String | GlobalSettings.weightUnit / rawKey `weightUnit` | :203-207 | **write-only,無消費方** |
| `legacy_theme` | String | GlobalSettings.theme / rawKey `theme` | :209-213 | **write-only,無消費方** |
| `legacy_one_rm_formula` | String | GlobalSettings.oneRMFormula / rawKey `oneRMFormula` | :215-219 | **write-only,無消費方** |
| `legacy_default_rest_time` | int | GlobalSettings.defaultRestTime | :221-224 | **write-only,無消費方** |
| `legacy_show_volume_in_stats` | bool | GlobalSettings.showVolumeInStats | :226-229 | **write-only,無消費方** |
| `legacy_enable_haptic_feedback` | bool | GlobalSettings.enableHapticFeedback / rawKey | :231-235 | **write-only,無消費方** |
| `legacy_auto_save_workout` | bool | GlobalSettings.autoSaveWorkout | :237-240 | **write-only,無消費方** |
| `legacy_user_name` | String | rawKey `userName` | :243 | 無獨立讀取(僅在清除清單裡) |
| `legacy_user_email` | String | rawKey `userEmail` | :244 | 同上 |
| `legacy_user_gender` | String | rawKey `userGender` | :245 | 同上 |
| `legacy_user_age` | int | rawKey `userAge` | :246 | 同上 |
| `legacy_user_height` | double | rawKey `userHeight` | :247 | 同上 |
| `legacy_user_current_weight` | double | rawKey `userCurrentWeight` | :248 | 同上 |
| `legacy_user_target_weight` | double | rawKey `userTargetWeight` | :249 | 同上 |
| `legacy_weekly_workout_goal` | int | rawKey `weeklyWorkoutGoal` | :250 | 同上 |
| `legacy_is_dark_mode` | bool | rawKey `isDarkMode` | :253 | **write-only,無消費方** |
| `legacy_reminder_time_millis` | int | rawKey `reminderTimeMillis` | :254 | **write-only,無消費方** |
| `legacy_last_viewed_achievements_date_millis` | int | rawKey `lastViewedAchievementsDateMillis` | :255-258 | 無(僅清除清單) |
| `legacy_unlocked_achievements_json` | String | rawKey `unlockedAchievementsJson` | :259-262 | 無(僅清除清單) |
| `legacy_accent_color_r/g/b/a` | double×4 | rawKey `accentColorR/G/B/A` | :265-270 | **write-only,無消費方** |

**結論**:grep 全 `lib/`(排除 importer 自身)顯示——除了 `lib/features/auth/session_controller.dart` 把 `kLegacyPrefsPersonalDataKeys`(:24-46,importer 檔內定義的顯式清單:`legacy_user_name/email/gender/age/height/current_weight/target_weight/global_settings_json/current_user_id/weekly_workout_goal/unlocked_achievements_json/last_viewed_achievements_date_millis`)整包當「換帳號要清除的個資」用(見下方 3.),以及 `lib/features/onboarding/onboarding_controller.dart:12-16` 一句註解提及命名慣例對齊——**沒有任何檔案讀取這些 `legacy_*` key 的值**。全部 22 個目標 key 目前都是 write-only,波 6 若要用它們做「Onboarding 前帶入舊偏好」的預填,現在完全沒接。
  - 特別確認題:單位偏好(`legacy_weight_unit`)、提醒設定(`legacy_reminder_time_millis`)、使用者名稱/email(`legacy_user_name`/`legacy_user_email`)、成就 JSON(`legacy_unlocked_achievements_json`)——**四者皆 write-only,無讀取方**。成就功能在 Flutter 側完全不存在(grep `achievement|Achievement` 全 lib/ 僅命中 migration 檔本身,無結果見下一行)。
  - 驗證命令與結果:`grep -rln "achievement\|Achievement" --include="*.dart" lib/ | grep -v migration` → 空輸出。

---

## 3. 既有可接資產

### GoalSettingsPage(波 5 產物)
- `lib/features/goals/goal_settings_page.dart:34-39`:`GoalSettingsPage extends ConsumerStatefulWidget`,zero-arg const,自帶 `Scaffold`+`AppBar('目標設定')`。
- 進入點:`lib/features/dashboard/dashboard_page.dart:64` — `Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GoalSettingsPage()))`,掛在 Dashboard 的 `GoalProgressSection.onTap`(:52-65),**不掛 router**。
- 呈現兩欄:週訓練次數目標(0-14,存 `Drift UserGoal.weeklyWorkoutGoal`)、目標體重(20-300kg,存 `Drift UserGoal.targetWeight`,留空存 null)——真正資料源是 `userGoalRepositoryProvider`(Drift),**不是** prefs 的 `kWeeklyWorkoutGoalKey`/`kUserTargetWeightKey`(那兩個 prefs key 只在 onboarding 完成時寫一次,write-only,見上節確認)。
- `goal_settings_controller.dart:1-9` 開頭注解自陳:UserGoal schema 還有六肌群容量目標、`restDayReminder` 等欄位「本頁不呈現,波 6 以後才有 UI」——**這是 brief 明講留給波 6 的擴充點**。

### session/登出既有機制(波 2 產物,`lib/features/auth/session_controller.dart`)
- `signOut()`(:378-391):清 `kAppleUserIdKey`/`kAppleUserNameKey`/`kAppleUserEmailKey` 三個 prefs key + `kOnboardingPersonalDataKeys` 個資清單 + `kHasCompletedOnboardingKey`,`invalidate(onboardingStatusProvider)`,state 重置為 `const SessionState()`。**刻意不清** `kLocalDataOwnerUserIdKey`(帳號隔離 owner,跨登出持續存在,:373-377 有說明)、不清隱私同意三個 key(:370-371)。
- `confirmClearAndContinueLogin()`(:280-329):換帳號二次確認後的完整清除流程——重置 Drift 全表(`db.resetForNewOwner()`)、清 `kOnboardingPersonalDataKeys`、清血緣 key、退休裝置層匯入旗標(CoreData + legacy prefs 皆標記完成防重跑)、清 `kLegacyPrefsPersonalDataKeys`(:306-308)與 `kCoreDataImportStatsKeys`,最後認領新 owner 並建立 session。
- `cancelOwnerConflict()`(:333-336):取消換帳號,只清 `ownerConflict` 狀態。
- `_completeLoginWithOwnerCheck` / `LoginOwnerConflict` / `LoginSuccess` / `LoginFailure`:登入結果 sealed class,設定頁若要做「切換帳號」入口可能要重用這條登入 seam,但目前設定頁完全沒有登入/換帳號按鈕,只有純登出。

### 隱私同意流(`lib/features/privacy/privacy_consent_controller.dart` 全檔 57 行)
- 三個 key:`kHasAgreedToAnalyticsKey`/`kHasAgreedToPrivacyKey`/`kPrivacyConsentDateKey`(:15-17)。`PrivacyConsentState.isAgreed`(:25)= `consentDate != null`。`agreeAndContinue()`(:42-50)一次性寫入三個 key。
- App 掛法:`lib/app.dart:23-32`——`MaterialApp.router.builder` 裡,`isLoggedIn && !hasAgreed` 時整個 App 被 `PrivacyConsentPage` 蓋掉(浮層,非 route)。
- **沒有「撤回同意」或「查看同意狀態」的既有方法**——controller 只有 `build()`(讀)與 `agreeAndContinue()`(寫),grep 確認 `kHasAgreedToPrivacyKey` 等三個 key 只在這個檔案內出現。設定頁若要做「隱私設定」入口,目前完全沒有可直接呼叫的既有 API,需新增。

### 版本資訊來源
- `pubspec.yaml`(全檔已讀)**dependencies 清單裡沒有 `package_info_plus` 或任何 `package_info`/`device_info` 套件**(逐行核對 :30-46 dependencies 區塊)。`grep -n "package_info" pubspec.lock` 也是空輸出。**版本資訊目前無現成來源,波 6 若要顯示 App 版本需自行加依賴。**
- `pubspec.yaml:20`:`version: 2.0.0+6`——build 時期常數存在(可透過 `--dart-define` 或未來加 package_info_plus 取得),但目前 code 內沒有任何地方讀取它。

---

## 4. 單位偏好的消費面預估(僅枚舉,不判方案)

全 `lib/` grep `"kg"` 命中 22 個檔案。扣掉 onboarding 相關(單位選擇本身的 UI,非「顯示」)後的重量顯示點：

**共用格式化函式(4 份幾乎重複,各自硬編 `' kg'` 字尾)**:
- `lib/features/dashboard/dashboard_format.dart:13,19` — `formatVolumeKg` / `formatWeightKg`
- `lib/features/history/history_format.dart:22,27` — 同名兩函式,獨立複本
- `lib/features/stats/workout_stats/workout_stats_format.dart:14` — `formatVolumeKg` 複本
- `lib/features/stats/body_weight/body_weight_format.dart:7` — `formatBodyWeightKg`

**直接字串插值 `' kg'`/`'kg'` 的顯示點**:
- `lib/features/history/edit/workout_edit_page.dart:166,436`
- `lib/features/workout/workout_in_progress_view.dart:146,340`
- `lib/features/workout/workout_summary_sheet.dart:74,118`
- `lib/features/stats/powerlifting/widgets/total_lift_card.dart:54`(獨立 `Text('kg')`)
- `lib/features/stats/powerlifting/widgets/system_estimate_section.dart:50,135,149`
- `lib/features/stats/powerlifting/widgets/manual_records_section.dart:49,191,221`
- `lib/features/stats/powerlifting/widgets/add_power_lift_record_sheet.dart:144`(+ :113 輸入框 label)
- `lib/features/stats/pr/widgets/pr_summary_card.dart:31,35`
- `lib/features/stats/body_weight/widgets/body_weight_chart.dart:113`(圖表目標線 tooltip)

**輸入框 label(InputDecoration,非顯示但同樣硬編 kg)**:
- `lib/features/dashboard/widgets/add_body_weight_sheet.dart:87`
- `lib/features/workout/add_set_sheet.dart:195`
- `lib/features/stats/body_weight/widgets/body_weight_form_sheet.dart:170`
- `lib/features/stats/powerlifting/widgets/add_power_lift_record_sheet.dart:113`
- `lib/features/goals/goal_settings_page.dart:188`(目標體重欄位 label,值域註解 :30-31 也寫死 kg)

**結論**:若做 kg/lb 切換,至少要動 4 份重複的 format 函式 + 上面列出的約 13 處直接插值顯示點 + 5 處輸入框 label,共約 22 個命中檔案裡的所有位置(僅枚舉,未判斷是否該先合併 4 份 format 函式再改)。

---

## 5. User model / Users 表

- Drift schema:`lib/data/db/tables.dart:7-11`:
  ```
  class Users extends Table {
    TextColumn get id => text()();
    TextColumn get name => text().nullable()();
    TextColumn get email => text().nullable()();
    DateTimeColumn get createdAt => dateTime()();
    DateTimeColumn get updatedAt => dateTime()();
  }
  ```
  **只有 id/name/email/createdAt/updatedAt,沒有身高/體重/性別/年齡欄位。**
- Dart model:`lib/data/models/user_profile.dart` 全檔(57 行)——`UserProfile{id,name,email,createdAt,updatedAt}`,`fromRow`/`toCompanion`/`copyWith` 皆只碰這 5 欄。檔案開頭註解(:6-8)自陳「目前 iOS 版沒有對應的 Repository,此 model 保留給之後接上認證流程時使用」。
- 身高/性別/年齡/目前體重/目標體重這些「個人資料」**不在 Drift,只以 prefs 形式存在**(`kUserGenderKey`/`kUserAgeKey`/`kUserHeightKey`/`kUserCurrentWeightKey`/`kUserTargetWeightKey`,定義於 `lib/features/onboarding/onboarding_controller.dart:28-33`)——且如 2./3. 節所述,這些 key 目前是 **write-only**,onboarding 寫入後從未被讀回(grep 全 lib/ 確認,見上方逐一 key 搜尋表)。
- 設定頁「個人資料」區可接資產:
  - `UserProfile.name`/`.email`(Drift,經 `userRepositoryProvider`)——但目前實際的 session 顯示名/信箱是走 prefs 的 `kAppleUserIdKey`/`kAppleUserNameKey`/`kAppleUserEmailKey`(session_controller.dart :28-30,148-150),不是 `UserProfile`,兩者是否同步未驗證(**待查項**:`onboarding_controller.dart:222` `userRepo.ensure(id, name: session.appleUserName, email: session.appleUserEmail)` 建 row 時有帶入,理論上首次建立會同步,但之後若 session 端改名/改信箱,Drift `Users` row 不會自動跟著更新——沒看到任何地方呼叫 `UserProfile.copyWith`+寫回)。
  - 身高/性別/年齡/目前體重/目標體重:目前只在 prefs 裡,且 write-only 從未讀回——若設定頁要顯示/編輯,需要決定要不要新增讀取邏輯,或是否該搬進 Drift(現無 Users 表對應欄位,需 migration)。目標體重另有 Drift `UserGoal.targetWeight` 這條平行路徑(見 3. GoalSettingsPage),與 prefs 的 `kUserTargetWeightKey` 是兩份不同步的資料,**這點是既有結構性重複,不確定波 6 該以哪個為準——建議上牌桌前先跟大腦/Mike 核對**。

---

## 不確定/待驗證清單(主動標出)

1. `UserProfile`(Drift Users 表 name/email)與 session prefs(`kAppleUserNameKey`/`kAppleUserEmailKey`)是否保持同步——只驗證了首次建立時同步,之後未驗證是否有任何地方回寫。
2. 目標體重存在兩處(`Drift UserGoal.targetWeight` 由 GoalSettingsPage 讀寫 vs prefs `kUserTargetWeightKey` 由 onboarding 寫入且從未讀回)——這是既有重複還是刻意設計未查證,只確認事實面。
3. 週訓練次數目標同樣存在兩處(`Drift UserGoal.weeklyWorkoutGoal` vs prefs `kWeeklyWorkoutGoalKey`),同上未判斷是否刻意。
4. router.dart 的 `_refreshForBranch`(:241-262)沒有掛「切到設定分頁」的 invalidate 邏輯——是否需要補,取決於波 6 設定頁要不要顯示會被其他分頁改動影響的資料(例如個人資料),未判斷。
