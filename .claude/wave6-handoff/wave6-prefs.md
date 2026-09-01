# Brief：波 6 偏好設定頁＋四項偏好 provider（含 legacy 預填）

## 目標

把 `lib/features/settings/preferences/` 的契約 stub 換成真身：偏好設定頁（主題／預設休息秒數／1RM 公式／重量單位四項）＋各偏好的 provider 與 SharedPreferences 持久化＋legacy prefs 預填。**消費端接線不歸你**（themeMode、kDefaultRestSeconds、公式呼叫端由大腦 merge 後接；重量單位顯示層由另一工人做）——你交付的是「偏好狀態的單一真源」。

## 範圍

改動面：前端（Flutter）。可動：

- `app/lib/features/settings/preferences/`（stub 換真身：preferences_page.dart、weight_unit.dart 的 provider 實作、新增其餘偏好 provider 檔）
- `app/test/features/settings/preferences/`（新增）

## 工作環境

- 工作目錄＝`/Users/mike/Documents/self/workout-record-wt-prefs`（app 在其下 `app/`，依賴已裝）
- 分支＝`wt/wave6/prefs`；commit 全留此分支；不 merge、不 push、不切分支、不動 worktree 外目錄。

## Seam（測試邊界）

- **契約約束（不可改）**：`weight_unit.dart` 的 enum 名／函式簽名／換算係數／`weightUnitProvider` 名稱與 `Provider<WeightUnit>` 型別（另一工人 22 個檔案正在消費它）；`PreferencesPage` 類名與 zero-arg const（另一工人掛入口）。你改的是 provider **實作**（接 prefs）與頁面**內容**。
- **四項偏好，每項三件事**：prefs 持久化 key、legacy 預填、頁面 UI。
  1. **重量單位**：`WeightUnit`（契約檔）。新 prefs key（自定名，如 `weight_unit`）；預填：既有值 → 無則 `legacy_weight_unit`（"kg"/"lb" 字串，`WeightUnit.fromStorageString` 已處理未知值）→ 無則 kg。UI：SegmentedButton 或 Radio。
  2. **主題**：`ThemeMode`（system/light/dark）。預填：`legacy_theme`＋`legacy_is_dark_mode`（兩個 legacy key 都存在，先開 `legacy_prefs_importer.dart` 核對值域——iOS theme 值是什麼字串（"light"/"dark"/"system"？）動筆前以 importer 與 iOS `GlobalSettingsManager.swift` 為準，映射不到的值落 system）。你需要提供 `themeModeProvider`（同步 `Provider<ThemeMode>` 或等價物，命名清楚——大腦 merge 後接進 app.dart 的 MaterialApp.themeMode）。
  3. **預設休息秒數**：int。預填：`legacy_default_rest_time`；無則沿用現行常數值（開 `lib/features/workout/workout_ui_shared.dart` 核對 `kDefaultRestSeconds` 現值）。UI：值域合理的選擇器（如 30-300 秒 step）。提供 `defaultRestSecondsProvider`。
  4. **1RM 公式**：enum（epley/brzycki/lander——先開 `lib/features/workout/one_rm_calculator.dart` 核對已實作的公式名與參數型別，你的 enum 要能無損映射）。預填：`legacy_one_rm_formula`（iOS 值域以 importer/iOS 源碼為準）。提供 `oneRmFormulaProvider`。
- **provider 形狀**：四個都要「同步讀（app 啟動即有值）＋設定頁寫入即生效＋換帳號情境不留跨帳號快取」——參照 `sharedPreferencesProvider` 既有注入慣例（overrides 測試法照 dashboard_page_test.dart harness）。實作形式（StateProvider／NotifierProvider）你定，回報時交代選型理由。
- 測試組裝照 harness 慣例；至少一條從 `PreferencesPage` 頂層 pump 真組裝。

## 驗收標準（可執行）

在 `/Users/mike/Documents/self/workout-record-wt-prefs/app` 下：

- `flutter analyze` → 0 issues；`flutter test` → 全綠（基線 497＋新增）。
- 新增測試至少覆蓋（**四項偏好逐項各自要有測試，不許一個 fixture 混測四項**——多規則互遮；附變異說明與輸出）：
  1. 每項：無任何值 → 預設正確（kg／system／現行常數秒數／epley）。
  2. 每項：只有 legacy key → 預填生效（變異：拔該項 legacy fallback 必紅——**逐項一個變異**）。
  3. 每項：既有新 key 優先於 legacy（兩組都種）。
  4. 每項：頁面改值 → prefs 寫入＋provider 值即時反映（變異：拔寫入必紅）。
  5. legacy 值域畸形（如 `legacy_theme` 存了未知字串、`legacy_default_rest_time` 為 0 或負數）→ 落安全預設不炸（**此輸入不受信**，逐項列畸形 fixture）。
  6. 契約回歸：`weightUnitProvider` 無任何 prefs 值時回 kg（另一工人的 no-op 基準）。
- 期望值自己實跑確認；規格與實測不符停下 SendMessage 回報。

## 紀律

- /tdd；【常備】範圍外既有問題不處理記順路發現（唯一例外擋驗收停下回報）；【UI】寫入失敗解除 loading＋浮錯＋失敗測試；【Riverpod】快取生命週期注釋交代（含換帳號）；defaultRetry 測試雷照舊；前提不符停下回報；繁中文案。
- legacy key 的確切名稱／型別／值域一律開 `legacy_prefs_importer.dart` 與 iOS `Services/GlobalSettingsManager.swift` 核對，本 brief 轉述僅供索引。

## 禁止事項

- 不做：任何消費端接線（app.dart／workout_ui_shared／one_rm 呼叫端／任何顯示點——大腦與另一工人的）、通知、震動、單位顯示換算本體。
- 不動：`settings_page.dart`（另一工人重寫中）、`lib/features/` 其他目錄、router.dart、lib/data/、pubspec。
- 不改契約：enum 名／換算函式簽名／係數／provider 名與型別／PreferencesPage 類名建構子。
- 已知雷內聯：copyWith `??` 無法清 null（ledger）；importer 的 GlobalSettings blob 優先、deprecated 頂層 key 僅補缺（已是 importer 內建行為，你只讀 `legacy_*` 目標 key，不碰 raw 來源）。
- 不 push、不 merge、不切分支。

## 回報格式

同波慣例：commit hash＋diff --stat／實際輸出／逐條對照／張力偏離（無則寫無）／順路發現（無則寫無）／**加一欄：三個新 provider 的名稱與型別清單（供大腦接線）**。SendMessage 主動送出，長報告落檔 `/private/tmp/claude-502/-Users-mike/9a6ac3ed-ec9d-4e70-85cf-e9edfa59b2a1/scratchpad/wave6-prefs-report.md` 回一行摘要。
