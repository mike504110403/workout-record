# Brief：波 6 重量單位顯示層改造（kg/lb 換算，22 檔）

## 目標

把全 app 的重量顯示／輸入點改造成消費 `weightUnitProvider`：kg 模式行為與現狀完全一致（no-op 回歸基準），lb 模式顯示換算值、輸入反向換算入庫。**儲存一律 kg**——DB／model／統計計算全部不動，lb 只存在於顯示與輸入層。

## 範圍

改動面：前端（Flutter）。可動：

- `app/lib/core/format/`（新目錄：收斂共用重量格式化）
- 下列顯示／輸入點所在檔案（**僅動與重量顯示/輸入相關的行**，同檔其他邏輯不碰）：
  - format 函式 4 份：`features/dashboard/dashboard_format.dart`、`features/history/history_format.dart`、`features/stats/workout_stats/workout_stats_format.dart`、`features/stats/body_weight/body_weight_format.dart`
  - 直接插值顯示點：`features/history/edit/workout_edit_page.dart`(166,436)、`features/workout/workout_in_progress_view.dart`(146,340)、`features/workout/workout_summary_sheet.dart`(74,118)、`features/stats/powerlifting/widgets/`（total_lift_card:54、system_estimate_section:50,135,149、manual_records_section:49,191,221、add_power_lift_record_sheet:144)、`features/stats/pr/widgets/pr_summary_card.dart`(31,35)、`features/stats/body_weight/widgets/body_weight_chart.dart`(113)
  - 輸入框 label＋輸入換算：`features/dashboard/widgets/add_body_weight_sheet.dart`(87)、`features/workout/add_set_sheet.dart`(195)、`features/stats/body_weight/widgets/body_weight_form_sheet.dart`(170)、`features/stats/powerlifting/widgets/add_power_lift_record_sheet.dart`(113)、`features/goals/goal_settings_page.dart`(188 與值域提示)
  - （行號採自 2026-09-01 探路，僅供索引——以你 grep 現況為準，**枚舉判準是「最終消費點」**：任何把重量數值渲染給使用者或收使用者重量輸入的地方，字面沒有 'kg' 的也要查——例如圖表軸刻度、tooltip）
- 對應各 feature 既有測試檔（只為適配改斷言＋新增單位測試；既有斷言語義不得弱化）

## 工作環境

- 工作目錄＝`/Users/mike/Documents/self/workout-record-wt-units`（app 在其下 `app/`，依賴已裝）
- 分支＝`wt/wave6/units`；commit 全留此分支；不 merge、不 push、不切分支、不動 worktree 外目錄。

## Seam（測試邊界）

- **唯一的單位事實來源**：`lib/features/settings/preferences/weight_unit.dart`（契約檔，另一工人接真身，目前 stub 恆回 kg）。你只 `ref.watch(weightUnitProvider)`＋用 `kgToDisplay`/`displayToKg`/`unitSuffix`——**消費端不得自帶換算係數或 'kg'/'lb' 字面判斷**（變異抽查會抓）。不得改契約檔。
- **收斂策略**：在 `core/format/` 建共用函式（吃值＋`WeightUnit`，如 `formatWeight(double kg, WeightUnit unit)`／`formatVolume(...)`），4 份重複 format 函式改為薄轉發或直接替換引用（各 feature 一份的舊慣例注釋要同步更新）；13 處直接插值改走共用函式；小數位規範對照既有輸出（trimZeros／toStringAsFixed 現行為，kg 模式輸出字串必須與改造前逐字元相同——這是 no-op 基準）。
- **輸入換算**：輸入框顯示當前單位 label；使用者輸入視為當前單位值，`displayToKg` 轉 kg 入庫；編輯既有值時 `kgToDisplay` 帶入。值域驗證（如 goal_settings_page 20-300kg、body weight 值域）在 lb 模式下界限換算後比對，錯誤提示顯示當前單位的界限值。
- **圖表**（body_weight_chart 目標線 tooltip、軸刻度若有）：顯示值換算，資料點本身不動。
- 測試：photo harness 慣例；provider override 直接 `weightUnitProvider.overrideWithValue(WeightUnit.lb)` 測 lb 模式（stub 期不依賴另一工人進度）。

## 驗收標準（可執行）

在 `/Users/mike/Documents/self/workout-record-wt-units/app` 下：

- `flutter analyze` → 0 issues；`flutter test` → 全綠（基線 497＋新增）。**既有測試全綠本身就是 kg no-op 回歸證明**——不得為過關而改寫既有測試的 kg 期望字串（改了＝破壞 no-op 基準，驗收不過；只有選擇器級適配可改）。
- 新增測試至少覆蓋（附變異說明與輸出）：
  1. **每個消費群組**（列表卡片／詳情頁／編輯頁／記訓練／summary／powerlifting／PR 卡／體重圖／各輸入框）各至少一條 lb 模式測試：override lb → 顯示值＝kg×2.20462…（斷言用 `kgToDisplay` 算期望值，別手抄係數）＋字尾 'lb'（變異：該群組漏接 provider 恆 kg 必紅）。
  2. 輸入換算雙向：lb 模式輸入 220.5 → DB 存 ≈100kg（誤差界說清楚）；編輯帶入反向。
  3. 值域：lb 模式下 goal 目標體重輸入 45（≈20.4kg）過、44 以下擋（換算後界限）。
  4. 精度：kg 模式輸出字串與現狀逐字相同（挑三個代表點 fixture 斷言完整字串）。
- 期望值自己實跑確認；規格與實測不符停下 SendMessage 回報。

## 紀律

- /tdd；【常備】範圍外既有問題不處理記順路發現（唯一例外擋驗收停下回報）；【Riverpod】顯示點 watch weightUnitProvider（切單位即時重繪——契約 provider 可監聽）；defaultRetry 測試雷照舊；前提不符停下回報；繁中文案。
- 改動範圍廣、機械性高——**每改完一個 feature 群組跑一次該群組測試再前進**，不要 22 檔改完才首跑。
- 探路行號僅索引：動筆前每個檔案自己重 grep 確認現況行號與內容。

## 禁止事項

- 不做：單位偏好的 UI／持久化（另一工人）、DB schema／model 單位變更、統計計算層改動（volume/1RM 計算輸入輸出恆 kg）、身高單位（cm 固定）。
- 不動：`lib/features/settings/`（兩位工人的地盤，含契約檔）、router.dart、lib/data/、pubspec。
- 消費端不得自帶換算係數／單位字面判斷（唯一來源＝契約檔）。
- 已知雷內聯：copyWith `??` 無法清 null（ledger）；Drift 秒級時間精度；4 份 format 函式「各 feature 一份」是既有明示慣例（dashboard_format.dart:12 注釋）——你被授權打破此慣例收斂進 core，收斂時把各檔慣例注釋同步改掉，別留過時宣稱。
- 不 push、不 merge、不切分支。

## 回報格式

同波慣例：commit hash＋diff --stat／實際輸出／逐條對照／張力偏離（無則寫無）／順路發現（無則寫無）／**加一欄：最終消費點清單 vs 探路清單的差集**（多找到的、確認不存在的，逐條）。SendMessage 主動送出，長報告落檔 `/private/tmp/claude-502/-Users-mike/9a6ac3ed-ec9d-4e70-85cf-e9edfa59b2a1/scratchpad/wave6-units-report.md` 回一行摘要。
