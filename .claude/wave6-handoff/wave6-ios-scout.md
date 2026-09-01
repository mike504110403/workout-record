# 波 6 iOS Settings 探路報告(判讀型)

範圍：`ios/WorkoutRecord/WorkoutRecord/Sources/`（Views/Settings、Services、相關 ViewModel）＋ `docs/FEATURE_MAP.md`
方法：只讀不改；判讀（機制敘述）與事實（檔案:行號＋逐字引用）分開標示。標「⚠️不確定」處請大腦自行開檔覆核。

---

## 1. SettingsView 結構

### 1.1 Views/Settings/ 下全部檔案
```
Views/Settings/SettingsView.swift            — 主頁 + ProfileView + SettingsExerciseManagementView + ExerciseCategoryView + AppSettingsView + FormulaExplanationView（多個 struct 塞在同一檔）
Views/Settings/GoalSettingsView.swift        — 目標設定頁
Views/Settings/NotificationSettingsView.swift — 通知設定頁
Views/Settings/AnalyticsSettingsView.swift   — 分析設定頁【死碼，見 2.6】
Views/Settings/CloudKitSettingsView.swift    — CloudKit 設定頁【死碼，見 2.7】
```

### 1.2 SettingsView 主頁清單（`SettingsView.swift:10-113`）
| Section | 列 | 點了做什麼 | 導去哪 |
|---|---|---|---|
| (無標題) | 個人資料 | NavigationLink | `ProfileView`（同檔內 struct，L127-221） |
| (無標題) | 目標設定 | NavigationLink | `GoalSettingsView` |
| 動作庫管理 | 動作庫 | NavigationLink | `SettingsExerciseManagementView`（同檔 L223-234）⚠️假資料，見 2.2 |
| 動作庫管理 | 自定義動作 | NavigationLink | `CustomExerciseListView`（`Views/Exercise/CustomExerciseListView.swift`）真功能 |
| 訓練模板 | 我的模板 | NavigationLink | `WorkoutTemplateView`（`Views/Template/WorkoutTemplateView.swift`）真功能（CoreData 支撐，未深挖） |
| 應用設定 | 偏好設定 | NavigationLink | `AppSettingsView`（同檔 L278-343） |
| 應用設定 | 通知 | NavigationLink | `NotificationSettingsView` |
| (無標題) | 版本（純顯示，非按鈕） | — | `VersionCheckService.shared` 讀 app/build 版本 |
| (無標題) | 使用教學 | NavigationLink | `TutorialView`（真·靜態教學內容） |
| (無標題) | 關於 | NavigationLink | `AboutView` |
| (無標題) | 登出 | Button→Alert確認 | `appleIDAuth.signOut()` |

**引用**（`SettingsView.swift:106-112`）：
```swift
                // 登出選項
                Section {
                    Button("登出") {
                        showSignOutAlert = true
                    }
                    .foregroundColor(.red)
                }
```

⚠️注意：Settings 主頁「無其他子頁」——沒有刪除帳號、沒有匯出/匯入、沒有單位設定 UI（見 2.3、5）。

---

## 2. 每個子頁實作深度判讀

### 2.1 ProfileView（`SettingsView.swift:127-221`）—【真功能，但欄位與 GoalSettingsView 有重複資料源，見 3.1 重大發現】
- 資料源：`UserProfile.shared`（`@AppStorage`，見 4）
- 欄位：姓名、性別、身高、目標體重、每週訓練目標
- 「儲存」按鈕呼叫 `profile.save()`（`SettingsView.swift:206`），但 `save()` 本體（`Services/AppSettings.swift:58-61`）幾乎是 no-op：
  ```swift
  func save() {
      // AppStorage 會自動保存，這裡可以添加額外邏輯
      objectWillChange.send()
  }
  ```
  （因為欄位本身是 `@AppStorage`，寫入時已即時落地，按鈕只是補一個成功提示 alert，非必要但不算殼）

### 2.2 SettingsExerciseManagementView / ExerciseCategoryView（`SettingsView.swift:223-276`）—【殼／Mock，判讀】
- `categories` 硬編碼字串陣列（`SettingsView.swift:224`）
- `ExerciseCategoryView.exercises` 硬編碼假動作清單，註解直寫 `// Mock exercises`（`SettingsView.swift:239-246`）
- 收藏星星按鈕：`// TODO: Toggle favorite`（`SettingsView.swift:256-258`，無實際邏輯）
- 右上「+」按鈕：`// TODO: Add custom exercise`（`SettingsView.swift:268-270`，無實際邏輯）
- **對照**：真正可用的自定義動作 CRUD 在同一 Section 的另一列「自定義動作」→`CustomExerciseListView`（真·repository 驅動，`viewModel.loadExercises()`/`deleteExercises`），與這顆殼並列，容易混淆。

### 2.3 AppSettingsView（`SettingsView.swift:278-343`）—【真功能，但缺單位設定】
- 資料源：`GlobalSettingsManager.shared`（非 deprecated 的 `AppSettings`，見 4）
- 有：主題（淺/深/系統）、預設休息時間、震動回饋、1RM 公式、重置所有設定
- **沒有**：weightUnit（kg/lb）選擇 UI——`GlobalSettingsManager` 有 `weightUnit` 屬性且被廣泛消費（見 2.4），但整個 AppSettingsView body（`SettingsView.swift:283-331`）三個 Section（外觀/訓練設定/進階設定）中不存在任何綁定 `weightUnit` 的 Picker/Toggle。**目前 iOS 版沒有任何 UI 能讓使用者切換公斤/磅**，永遠固定 `.kg`（除非曾被 `UserPreferencesSyncService`/CloudKit 同步覆寫，該服務本身是已知死碼，見 CLAUDE.md）。
- 「重置所有設定」呼叫 `globalSettings.resetToDefaults()`（`GlobalSettingsManager.swift:86-95`），真的會清空並落地存檔。

### 2.4 weightUnit 消費鏈驗證（單位偏好——存哪、誰真的讀）
- **存放**：`GlobalSettingsManager.weightUnit`（`Services/GlobalSettingsManager.swift:11`），非獨立 UserDefaults key，而是序列化進單一 JSON blob，key 名 `"GlobalSettings"`（`GlobalSettingsManager.swift:21,32,56-58`）：
  ```swift
  private let settingsKey = "GlobalSettings"
  ...
  if let data = try? JSONEncoder().encode(settings) {
      userDefaults.set(data, forKey: settingsKey)
  }
  ```
  `SettingsData` struct（`GlobalSettingsManager.swift:99-107`）把 weightUnit/theme/oneRMFormula/defaultRestTime/showVolumeInStats/enableHapticFeedback/autoSaveWorkout 全部塞進同一包 JSON。
- **真的被讀取消費者**（grep 全 Sources 確認，非猜測）：`WeightFormatter.swift:18,25,32,100`、`WorkoutViewModel.swift:188`、`EditSetSheet.swift:18,47,120`、`AddSetSheet.swift:32,74,171`、`EditExerciseSheet.swift:20,61`、`PowerliftingView.swift`（多處）、`AddPowerLiftRecordSheet.swift`、`WorkoutDetailView.swift:321`、`OnboardingView.swift:563,668`——**確有大量真實顯示/換算消費**。
- **矛盾**：有消費者、有 model 屬性，但**沒有任何 UI 讓使用者改它**（2.3 已確認）。等同「設定存在但無法從 UI 觸達」的半殼狀態，非典型死碼但功能缺口。
- **另有一組舊制、已 deprecated、且完全無人使用的 `AppSettings.weightUnit`**（`Services/AppSettings.swift:5-16`，`@AppStorage("weightUnit")` 獨立 key，非 JSON blob）：全 Sources grep `AppSettings.shared` 零命中——**整個 deprecated class 已是死碼**，其 `weightUnit`/`theme`/`oneRMFormula`/`defaultRestTime`/`enableAutoRestTimer`/`enableHapticFeedback` 六個獨立 UserDefaults key（`weightUnit`/`theme`/`oneRMFormula`/`defaultRestTime`/`enableAutoRestTimer`/`enableHapticFeedback`）**理論上可能殘留在真機/模擬器 UserDefaults 中但無程式碼讀寫**，Flutter 側做 legacy prefs 消費時**不要**誤讀這批頂層 key（正確來源是 `GlobalSettings` JSON blob裡的欄位）。

### 2.5 NotificationSettingsView（`Views/Settings/NotificationSettingsView.swift`）—【殼，寫入邏輯是死碼】
- 四個 Toggle（訓練提醒/休息計時器提醒/成就通知/週報通知）+ 提醒時間 DatePicker，全部是 `@State`（`L5-9`），非持久化屬性本身。
- `onAppear` 呼叫 `loadNotificationSettings()`（`L91-93`），從 UserDefaults 讀四個 bool key + `reminderTime`（`L142-150`）。
- **`saveNotificationSettings()`（`L153-159`）宣告後，全 Sources grep 零其他呼叫點**——沒有任何 Toggle 的 `onChange`、沒有任何按鈕呼叫它。唯一有 `onChange` 的是 `workoutReminders`，但它只觸發 `requestNotificationPermission()`（`L17-21`），不落地存值。
  ```swift
  private func saveNotificationSettings() {
      UserDefaults.standard.set(workoutReminders, forKey: "workoutReminders")
      ...
  }
  ```
  → **結論：這頁的四個 Toggle 與提醒時間永遠不會真正持久化**；`loadNotificationSettings()` 每次 `onAppear` 讀到的 UserDefaults key 若從未被寫過，`.bool(forKey:)` 回傳預設 `false`，等於使用者每次重進這頁都會看到已勾選的 Toggle 被重置回未勾選（`@State` 初值是 `true`，但 `onAppear` 覆寫成讀取值）。
- `isNotificationPermissionGranted()`（`L107-110`）**永遠 return true**（註解自承 `// 簡化檢查，實際應用中需要異步檢查權限狀態`），導致 `L58` 的權限警告區塊永遠不顯示——真殼。
- 「測試通知」「清除所有通知」兩個按鈕是真的呼叫 `UNUserNotificationCenter`（`L112-133`），這兩個算真功能，但整頁的「設定持久化」是假的。
- **通知提醒設定與真通知系統無關聯**：沒有排程邏輯根據 `reminderTime`/`workoutReminders` 實際註冊 local notification（只有一次性「測試通知」）。

### 2.6 AnalyticsSettingsView（`Views/Settings/AnalyticsSettingsView.swift`）—【完全孤兒，未掛載進 Settings 導覽】
- grep `AnalyticsSettingsView(` 全 Sources，唯一命中是自己的 `#Preview`（`L137`）。**SettingsView.swift 沒有任何 NavigationLink 指向它**——這顆檔案存在但使用者永遠到不了。
- 內容本身接 `LocalAnalyticsService.shared`（上傳/清除分析數據），邏輯看起來完整，但因未掛載等同死碼。

### 2.7 CloudKitSettingsView（`Views/Settings/CloudKitSettingsView.swift`）—【完全孤兒，未掛載】
- 同上，grep 只命中自己的 `#Preview`（`L165`）。接 `AuthService.shared`/`CloudKitAuthService.shared`/`CloudKitSyncService.shared`，這批服務本身已被 CLAUDE.md 明文列為「半成品死碼」（`UserPreferencesSyncService`、`CloudKitSyncService`）。

### 2.8 GoalSettingsView（`Views/Settings/GoalSettingsView.swift`）—【真功能，CoreData 驅動】
- `GoalViewModel`（`ViewModels/GoalViewModel.swift`）用 `UserGoalRepository` 存取 CoreData `UserGoal` entity，`loadGoals()`/`saveGoals()` 都有真實 try/catch + repository 呼叫（`GoalViewModel.swift:31-91`）。
- 儲存成功會 post `NotificationCenter` 事件 `.goalsUpdated`（`GoalViewModel.swift:84,96`），供其他頁面監聽刷新（真實跨頁同步機制，非殼）。
- ⚠️但與 ProfileView 的「每週訓練目標」「目標體重」欄位是**兩套完全獨立的儲存**，見 3.1。

### 2.9 AboutView（`Views/About/AboutView.swift`）—【真·靜態內容，非死碼但非動態】
- 版本號從 `Bundle.main.infoDictionary` 真的讀（`L7-13`），非硬編碼。
- 隱私政策/服務條款是 App 內建純文字 `AboutPrivacyPolicyView`/`TermsOfServiceView`（`L172-270`），與 `docs/privacy.html`（App Store 隱私政策網頁）內容各自獨立維護，未見引用同一份文字來源（⚠️此處只核對了程式碼內文字存在，未逐字比對 privacy.html 是否一致，需要的話另開任務）。
- 內文提及使用者可「透過應用程式內的設定頁面」行使刪除/匯出等權利（另一份 `Views/Privacy/PrivacyPolicyView.swift:443` 也提到「資料可攜權…以結構化格式匯出您的資料」）——但 Settings 實際上**沒有任何匯出/刪除功能**（見第 3、5 節），文案與實作不一致。

### 2.10 TutorialView（`Views/Tutorial/TutorialView.swift`）—【真·靜態教學內容】
- 386 行，純 SwiftUI 排版的圖文教學步驟，無資料存取邏輯，內容與功能對應大致合理（快速開始/新增動作等），未見殼標記。

---

## 3. 登入/帳號區

### 3.1 【重大發現】weeklyWorkoutGoal 與 targetWeight 有兩套互不同步的儲存
- **ProfileView**（Settings→個人資料）：`Stepper` 綁 `profile.weeklyGoal`（`SettingsView.swift:201`），來源 `UserProfile.weeklyGoal`＝`@AppStorage("weeklyWorkoutGoal")`（`AppSettings.swift:54`）；`targetWeight` 同理綁 `@AppStorage("userTargetWeight")`（`AppSettings.swift:53`）。
- **GoalSettingsView**（Settings→目標設定）：`Stepper` 綁 `viewModel.weeklyWorkoutGoal`（`GoalSettingsView.swift:17`），來源 CoreData `UserGoal.weeklyWorkoutGoal`（`GoalViewModel.swift:35`）；`targetWeight` 同理綁 CoreData `UserGoal.targetWeight`（`GoalViewModel.swift:36`）。
- 兩頁**各自獨立讀寫，互不同步**——使用者在「個人資料」改每週目標，「目標設定」頁不會反映，反之亦然。⚠️這是既有雷（非本次任務造成），按協議不擴大範圍，但因直接影響 Flutter 側「目標設定」該讀哪個 legacy 值，**必須在 brief 中明示：Flutter 目標設定波該對應的是 `UserGoal`/CoreData（GoalSettingsView 路線，功能較完整：含容量目標、休息日提醒），還是 `UserProfile`（ProfileView 路線，較陽春）**——這題本質是「哪個是真基準」的裁決，不是我能單方判定的既有雷分類，建議轉入 wip 待裁示。

### 3.2 登出（`AppleIDAuthService.signOut()`，`Services/AppleIDAuthService.swift:101-113`）
```swift
func signOut() {
    // 清除儲存的用戶資訊
    UserDefaults.standard.removeObject(forKey: "AppleIDUserID")
    UserDefaults.standard.removeObject(forKey: "AppleIDUserName")
    UserDefaults.standard.removeObject(forKey: "AppleIDUserEmail")
    
    // 重置狀態
    isSignedIn = false
    userID = nil
    userName = nil
    userEmail = nil
    showLoginRequired = true
}
```
- **只清 3 個 Apple ID 相關 key**（`AppleIDUserID`/`AppleIDUserName`/`AppleIDUserEmail`）。
- **不清**：`UserProfile`（姓名/身高/體重等 8 個 key）、`GlobalSettingsManager`（GlobalSettings JSON blob）、CoreData 全部訓練資料、`GoalSettingsView` 的 UserGoal、Onboarding 完成狀態（`hasCompletedOnboarding`）。
- 效果＝退回登入畫面（`showLoginRequired = true`），但本機資料全數保留，下次登入（同一台裝置）資料原封不動可見。

### 3.3 刪除帳號
- 全 Sources grep `deleteAccount`/`刪除帳號`：**零命中**。**iOS 版沒有刪除帳號功能**，即使 `docs/FEATURE_MAP.md`（見第 5 節）與 `Views/Privacy/PrivacyPolicyView.swift:405-406`（"我們會保留您的資料直到您刪除帳戶或要求刪除"）都提及此功能存在。

### 3.4 與波 2 Flutter 帳號隔離（owner 認領/換帳號清資料）的對應關係
⚠️此點需要波 2 Flutter 側實作細節才能精確比對，我只讀了 iOS 側，未讀 `app/` 波 2 程式碼——**這條我判讀力不足，建議大腦自行核對波 2 brief/程式碼**。已知的 iOS 側事實只有：iOS 版 `signOut()` 不清資料、無多帳號切換機制（`AppleIDAuthService` 全域單例、無 per-user 資料隔離邏輯，CoreData 也沒看到 userId 過濾——⚠️這點也需要 scout-trace 級的資料模型交叉驗證，本次未深入 CoreData schema）。

---

## 4. UserDefaults Keys 清單（Settings 相關，逐一列出）

| Key | 型別 | 寫入點 | 讀取點 | 狀態 |
|---|---|---|---|---|
| `userName` | String | `UserProfile.name`（`AppSettings.swift:47`）ProfileView TextField | 同上（AppStorage 雙向） | 真·使用中 |
| `userEmail` | String | `AppSettings.swift:48` | ⚠️grep 顯示只在 struct 宣告，ProfileView 顯示的是 `appleIDAuth.userEmail`（Apple ID 服務），非此欄位——**此 key 疑似未在任何 UI 實際寫入**，需覆核 |
| `userGender` | String | `UserProfile.gender`（`AppSettings.swift:49`），ProfileView Picker | 同上 | 真·使用中 |
| `userAge` | Int | `AppSettings.swift:50` | ⚠️grep 顯示 ProfileView 沒有「生日/年齡」欄位 UI（FEATURE_MAP 宣稱有生日，見第5節）——**此 key 疑似無 UI 寫入路徑**，需覆核 |
| `userHeight` | Double | `UserProfile.height`（`AppSettings.swift:51`），ProfileView TextField | 同上 | 真·使用中 |
| `userCurrentWeight` | Double | `AppSettings.swift:52` | ⚠️grep 顯示 ProfileView 沒有「目前體重」欄位 UI——**此 key 疑似無 UI 寫入路徑**，需覆核（可能被 Onboarding 或其他頁寫入，本次未查全） |
| `userTargetWeight` | Double | `UserProfile.targetWeight`（`AppSettings.swift:53`），ProfileView TextField | 同上；**與 CoreData UserGoal.targetWeight 並存，見 3.1** | 真·使用中，但雙源頭 |
| `weeklyWorkoutGoal` | Int | `UserProfile.weeklyGoal`（`AppSettings.swift:54`），ProfileView Stepper | 同上；**與 CoreData UserGoal.weeklyWorkoutGoal 並存，見 3.1** | 真·使用中，但雙源頭 |
| `GlobalSettings` | Data(JSON blob) | `GlobalSettingsManager.saveSettings()`（`GlobalSettingsManager.swift:56-58`） | `loadSettings()`（`L32-41`）；欄位含 weightUnit/theme/oneRMFormula/defaultRestTime/showVolumeInStats/enableHapticFeedback/autoSaveWorkout | 真·使用中，**單位偏好真正的家**（見 2.4） |
| `hasCompletedOnboarding` | Bool | `OnboardingState`（`Models/OnboardingState.swift:7`），`@AppStorage` | 同上 | 真·使用中，非 Settings 頁面直接控制但關聯登出後行為 |
| `workoutReminders` | Bool | `NotificationSettingsView.saveNotificationSettings()`（**從未被呼叫，死碼**） | `loadNotificationSettings()`（`L143`） | 讀取路徑存活，寫入路徑死碼——實質永遠讀到預設值 |
| `restTimerAlerts` | Bool | 同上（死碼寫入） | 同上（`L144`） | 同上 |
| `achievementNotifications` | Bool | 同上（死碼寫入） | 同上（`L145`） | 同上 |
| `weeklyReports` | Bool | 同上（死碼寫入） | 同上（`L146`） | 同上 |
| `reminderTime` | Date | 同上（死碼寫入） | 同上（`L148-150`） | 同上 |
| `AppleIDUserID`/`AppleIDUserName`/`AppleIDUserEmail` | String | `AppleIDAuthService`（登入時寫、`signOut()` 清） | 同服務 | 真·使用中（帳號區，非嚴格「設定」但登出行為相關） |
| `weightUnit`（頂層獨立 key，非 GlobalSettings blob 內）/`theme`/`oneRMFormula`/`defaultRestTime`/`enableAutoRestTimer`/`enableHapticFeedback` | 各型別 | `AppSettings`（deprecated class）`@AppStorage`（`AppSettings.swift:11-16`） | 同 class 內，但 **`AppSettings.shared` 全 Sources 零呼叫** | **死碼**——可能是舊版殘留在使用者裝置 UserDefaults 裡的孤兒值，Flutter 側消費 legacy prefs 時務必排除，改讀 `GlobalSettings` blob |

⚠️`userEmail`/`userAge`/`userCurrentWeight` 三個 key 我只確認了「宣告存在＋所屬 class 有被實例化（`UserProfile.shared`）」，但**未逐一確認是否真的有任何 UI 對它們寫值**（ProfileView 的 Form 只看到姓名/性別/身高/目標體重/每週目標五個欄位，見 `SettingsView.swift:176-202`，找不到 email/age/currentWeight 的輸入控件）——這三個 key 有 declare 沒 UI 寫入路徑，建議大腦另外 grep 一次 `\.email\s*=`、`\.age\s*=`、`\.currentWeight\s*=` 全域確認是否被 Onboarding 或其他非 Settings 頁面寫入，我這次搜尋範圍集中在 Settings，未做全庫地毯式核對。

---

## 5. FEATURE_MAP.md「Tab 5: 設定與個人」段對照（`docs/FEATURE_MAP.md:297-435`）

FEATURE_MAP 本身聲明是「長期參考／功能對等基準」，但本段落宣稱內容與實際程式碼落差巨大，逐項對照：

| FEATURE_MAP 宣稱 | 實際狀況 |
|---|---|
| 個人資料含「照片頭像」「生日」 | ProfileView 沒有頭像上傳、沒有生日欄位（`SettingsView.swift:176-202`只有姓名/性別/身高/目標體重/每週目標） |
| 登入資訊含「Google 帳號綁定狀態」「帳號綁定/解綁」 | 只有 Apple ID 單一登入（`AppleIDAuthService`），無 Google、無綁定/解綁 UI |
| 動作庫「標記常用」「隱藏動作」「排序（拖曳）」 | `SettingsExerciseManagementView`/`ExerciseCategoryView` 純 Mock，收藏鍵是 TODO（見 2.2），無隱藏、無拖曳排序 |
| 訓練模板「系統預設模板 PPL/上下肢分化/全身訓練」 | ⚠️未深入 `WorkoutTemplateView`/`WorkoutTemplateViewModel` 逐項核對是否有這三個系統預設模板的資料，本次只確認該頁面是真·CoreData 驅動非 Mock（見 1.2），系統模板內容真偽待另外覆核 |
| 應用設定「單位設定：重量單位 kg/lb + 身高單位 cm/in」 | **重量單位無 UI**（見 2.3/2.4）；**身高單位完全不存在**，全 Sources 找不到 cm/in 切換邏輯（身高欄位固定顯示 "cm"，`SettingsView.swift:188`寫死文字） |
| 提醒通知「提醒頻率」 | `NotificationSettingsView` 只有時間 DatePicker，無「頻率」選項；且整頁持久化是死碼（見 2.5） |
| 進階設定「百分比快選設定」「資料顯示精度」 | 全 Sources grep 未見對應 UI/邏輯，AppSettingsView 進階設定 Section 只有 1RM 公式 Picker（`SettingsView.swift:307-323`） |
| 數據管理「匯出數據 CSV/JSON」「匯入數據」「iCloud 自動備份/手動備份/還原」 | **全部不存在**，Settings 主頁沒有任何對應列（見 1.2 完整清單） |
| 帳號管理「刪除帳號（二次確認）」 | **不存在**（見 3.3） |
| 登出「保留本地資料（可選）」 | 實際登出沒有選項，固定行為是保留本地資料（不清）＋清 3 個 Apple ID key（見 3.2），與宣稱的「可選」不符（現況是無條件保留，非使用者可選） |
| 關於與幫助「常見問題 FAQ」「意見回饋」 | AboutView 只有「聯絡我們」mailto 連結（`AboutView.swift:94-96`），無 FAQ 頁面、無獨立意見回饋表單 |

**結論**：FEATURE_MAP.md 的 Tab 5 段落更像是「規劃願景」而非「實際功能對等基準」，落差比例極高（單位設定、資料匯出/匯入/備份、刪除帳號、Google 登入、動作庫進階操作全數缺席）。波 6 若把 FEATURE_MAP 當 Flutter 設定頁的功能清單直接對照，會做出 iOS 版根本不存在的功能——**建議波 6 brief 明確聲明「以本探路報告的實際程式碼行為為準，FEATURE_MAP Tab5 段僅供背景參考」**。

---

## 待覆核清單（我最不確定的環節，優先序由高到低）

1. **`userEmail`/`userAge`/`userCurrentWeight` 三個 UserDefaults key 是否真的無 UI 寫入路徑**——本次搜尋集中在 Settings 目錄，未做全庫地毯搜尋，可能被 Onboarding 或其他非 Settings 頁寫入。
2. **weeklyWorkoutGoal / targetWeight 雙儲存源頭（UserProfile vs CoreData UserGoal）哪個是波 6 該對接的「真基準」**——這是裁決題，不是我能單方判定，已建議轉 wip 待裁示。
3. **`WorkoutTemplateView` 系統預設模板（PPL/上下肢分化/全身）內容是否真的存在**——只確認頁面非 Mock，未逐項核對模板資料本身。
4. **波 2 Flutter 帳號隔離機制與 iOS `signOut()` 行為的對應關係**——未讀 `app/` 波 2 程式碼，純 iOS 側判讀。
5. **`docs/privacy.html` 與 App 內建 `AboutPrivacyPolicyView`/`PrivacyPolicyView` 文字是否一致**——只確認兩份都存在且各自獨立維護，未逐字比對。
