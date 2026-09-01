# Brief：波 6 設定頁骨架＋個人資料頁＋關於頁＋入口整合

## 目標

把設定 tab 從 placeholder（現況只有登出按鈕＋ImportRetryTile）做成 section 化的設定主頁，加個人資料頁（消費 legacy prefs 預填）與關於頁（版本＋隱私內文），整合既有入口。iOS 基準 `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Settings/SettingsView.swift`（可讀不改）；**FEATURE_MAP.md Tab5 段是願景不是基準，勿對照它做**（探路已證實匯出/刪帳號/Google 登入等 iOS 全無實作）。

## 範圍

改動面：前端（Flutter）。可動：

- `app/lib/features/settings/`（settings_page.dart 重寫＋新增 profile/、about/ 子目錄；**不動 preferences/ 子目錄**——那是另一工人的，你只 import 它的 `PreferencesPage` 掛入口）
- `app/pubspec.yaml`（**僅限**加 `package_info_plus` 一個依賴，Mike 已裁；跑 `flutter pub get` 更新 lock）
- `app/test/features/settings/`（新增；既有 settings_logout_test.dart 若因骨架改版需調整選擇器可改，登出行為斷言不得弱化）

## 工作環境

- 工作目錄＝`/Users/mike/Documents/self/workout-record-wt-score`（app 在其下 `app/`，依賴已裝）
- 分支＝`wt/wave6/core`；commit 全留此分支；不 merge、不 push、不切分支、不動 worktree 外目錄。

## Seam（測試邊界）

- 設定主頁結構（對照 iOS SettingsView.swift:10-113，取「真功能」子集）：
  1. 個人資料（push 你新建的 `ProfilePage`）
  2. 目標設定（push 既有 `GoalSettingsPage`——`lib/features/goals/goal_settings_page.dart`，zero-arg const，照 dashboard_page.dart:64 的 push 慣例）
  3. 我的模板（push 既有 `TemplatesListPage`——照 start_workout_view.dart:54 慣例）
  4. 偏好設定（push `PreferencesPage`——契約 stub 已在 `lib/features/settings/preferences/preferences_page.dart`，另一工人換真身，你只掛入口）
  5. 關於（push 你新建的 `AboutPage`）
  6. 登出（**沿用既有** `_confirmSignOut` 流程與 signOutButton key，settings_page.dart:10-30 現有邏輯搬進新骨架，行為不變）
  7. `ImportRetryTile` 保留（現況只在匯入永久失敗時渲染，位置放列表尾）
- **個人資料頁**：三欄——姓名（文字）、性別（選項，值域對照 iOS ProfileView 的 Picker）、身高（cm，數字）。存 SharedPreferences，key 用既有 `kUserNameKey`/`kUserGenderKey`/`kUserHeightKey`（定義在 `lib/features/onboarding/onboarding_controller.dart:28-33`——先開檔核對確切名稱與型別）。**首次進頁預填順序**：既有 prefs 值 → 沒有則 `legacy_user_name`/`legacy_user_gender`/`legacy_user_height`（legacy_prefs_importer 搬進來的，現全 write-only——這就是「消費 legacy prefs」）→ 都沒有則空。儲存按鈕＋成功回饋＋失敗路徑。**不做**：目標體重/週目標欄位（單一真源是 Drift UserGoal，入口在目標設定頁——Mike 已裁，消滅 iOS 雙源缺陷）、email/年齡（iOS 無 UI 寫入路徑，探路已證）。
- **關於頁**：版本號（`package_info_plus` 的 `PackageInfo.fromPlatform()`，顯示 version+buildNumber）＋隱私政策靜態內文。**隱私文案紀律（repo CLAUDE.md 地雷區）**：必須與「資料存裝置本機」現狀一致——參照 iOS `Views/About/AboutView.swift` 內文精神但**刪掉**其中「可透過設定頁匯出/刪除資料」等與實作不符的句子（探路已證 iOS 文案與實作不一致，不要照抄病灶）。
- 測試組裝照 `test/features/settings/settings_logout_test.dart`＋`test/features/dashboard/dashboard_page_test.dart` harness 慣例。至少一條從 `SettingsPage` 頂層 pump 真組裝。

## 驗收標準（可執行）

在 `/Users/mike/Documents/self/workout-record-wt-score/app` 下：

- `flutter analyze` → 0 issues；`flutter test` → 全綠（基線 497＋新增；既有紅＝未達成）。
- 新增測試至少覆蓋（附變異說明與實際輸出）：
  1. 主頁七項入口各自導頁正確（偏好設定推入 PreferencesPage stub 即可；變異：拔掉任一 push 必紅）。
  2. 個人資料 legacy 預填：fixture 種 `legacy_user_name` 等三個 legacy key（無既有 kUser* 值）→ 進頁三欄帶入（變異：拔預填 fallback 必紅）；_*既有 kUser* 值優先於 legacy_*（兩組都種，斷言顯示 kUser* 值）。
  3. 個人資料儲存 → prefs 三 key 寫入正確型別（變異：拔儲存呼叫必紅）；失敗路徑解除 loading＋浮錯不 pop。
  4. 登出流程既有斷言全數維持綠（settings_logout_test.dart）。
  5. 關於頁版本顯示（PackageInfo 在測試環境用 `PackageInfo.setMockInitialValues` mock）。
- 期望值自己實跑確認；規格與實測不符停下 SendMessage 回報。

## 紀律

- /tdd：red-green、只測 seam。
- 【常備】範圍外既有問題一律不處理，記「順路發現」；唯一例外＝直接擋驗收，停下 SendMessage 等指示。
- 【UI】非同步失敗路徑一律要處理（儲存失敗解除 loading＋浮錯）；至少一條失敗路徑測試。
- 【Riverpod】新增 controller 交代快取生命週期；已知雷：riverpod defaultRetry 自動重試（failure 測試用 `retry: (c,e)=>null` 關）；Drift 秒級時間精度。
- 前提與程式碼不符也算互斥：停下 SendMessage 回報。
- UI 文案繁中硬編（現慣例）。

## 禁止事項

- 不做：通知設定、震動、教學頁、匯出/刪帳號、自定義動作入口、目標體重/週目標欄位、單位切換相關任何東西（另兩工人的）。
- 不動：`lib/features/settings/preferences/` 內容（契約檔＋stub，另一工人的地盤；只 import）、router.dart、lib/data/、其他 feature、pubspec 除 package_info_plus 外任何依賴。
- 已知雷內聯：`_resolveUserId` 複本慣例照抄不抽共用（若用到）；copyWith `??` 語意無法清 null（ledger 首雷——nullable 欄位清空用完整建構子）；legacy key 清單以 `legacy_prefs_importer.dart` 實際 key 名為準（動筆前開檔核對，勿憑本 brief 轉述）。
- 不 push、不 merge、不切分支。

## 回報格式

done 時必附，缺一視同未完成：commit hash＋diff --stat／測試與 analyze 實際輸出／驗收逐條對照／張力與偏離清單（無則寫無）／順路發現（無則寫無）。**用 SendMessage 主動送出**，idle 通知不算；報告長就落檔 `/private/tmp/claude-502/-Users-mike/9a6ac3ed-ec9d-4e70-85cf-e9edfa59b2a1/scratchpad/wave6-core-report.md` 再回一行摘要。
