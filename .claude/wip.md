# WIP — 三平台改寫(2026-07-24)

## 現況(2026-08-04 波 2 收斂)

- **波 0(升 Flutter + web)**、**波 1(登入 + Onboarding)**、**import-minors 波** 均已 merge develop(細節見 git log 與 `.claude/decisions/`)。
- **波 2 ①帳號隔離:完成,merged**(d81d5f8):owner 認領 + 換帳號警告清資料,依 `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`(含「實作補充」節:重種動作庫、血緣消耗時機=換人清除時、清除退休匯入旗標、已知保留範圍)。review:code r1 FAIL→r2 PASS、security r1 FAIL→r2 PASS。
- **波 2 ②Dashboard:完成,merged**(dff922f):五區塊對等 iOS(今日概覽/快速操作/目標進度/本週統計/最近訓練),`features/dashboard/` + router 分頁切回 invalidate。review 三輪(r3 PASS,M3 真測試經大腦親自變異驗證)。與 iOS 刻意差異:ISO 週一起算、無目標顯示空狀態、最近訓練日期格式 `M/d HH:mm`、不複製 iOS 鼓勵訊息 0-1% 邊界 bug。
- **收波後 develop 全驗證(大腦親跑,2026-08-04)**:analyze 0 issues、test 200/200、web build 成功。
- **波 2 ③import minors:完成,merged**(1a8afd8 修復 + merge + 3fa0e9b 補測試):六項複審遺留 minor(真 COUNT 核帳、alreadyCompleted 斷言、exercises 核帳等式、alreadyLanded 舊庫 COUNT、blocked UNIQUE 評估不適用、_ImportTally 重構)+ 修復 3 major(排版 scope creep 還原、測試假變異宣稱誠實化、`_oldDbTableCounts` 缺表 try/catch 降級)。工人被收斂中斷後由大腦收尾:補插核帳等式兩測試 + 排版還原時遺失的 alreadyCompleted tile 測試。**補審已完成(2026-08-04):code + db 聚焦複審雙 PASS**(7 個變異全紅、回貼零錯位、merge 交疊無錯位),兩條一行級 minor(手動重試命中時六表相等不成立的文件註記、缺表測試改 key 集合比對)大腦已修。
- **波 2 收波清理完成**:全部 worktree 移除、worktree-agent-* 分支刪除;`feature/wave2-*` 三分支已 merge 保留在地端(推 origin 後可刪)。

## 波 2 遺留(判斷題,不擋,收下波或 Mike 裁)

- riverpod `defaultRetry` 讓 Dashboard 錯誤畫面 ~38 秒後才出現重試鈕(生產重試路徑無測試);候選:自訂 retry 縮短退避 / loading 分支提早顯示重試。
- Drift `dateTime()` 秒級精度:同秒多筆時「取最新」排序不定(目前僅測試踩到,已在測試端規避)。
- intl 已宣告未使用,dashboard 手刻日期格式化——要不要統一,下波前決定。
- 帳號隔離 code r2 判斷題:退休旗標邏輯搬 migration 側 `retireImports()`、onboarding 清除三步抽私函式、11 表守門改逐表塞資料驗清空。
- StatCard 抽共用(等波 4 Stats 第二個使用者出現)、GoalProgress 型別化、「首頁該刷新」知識搬 Dashboard 側(波 3 加詳情頁時回看)。
- 全 repo dart format 專波(波 0 遺留,49/69 檔會動)。
- `import_retry_tile._messageFor` 的 alreadyLanded 分支是唯一無測試的 skipReason 分支(死碼建構子已刪,補測要手組 ImportResult)。
- ~~CoreData model 版本演進疑慮~~:Mike 確認(2026-08-04)無版本演進、單一凍結 schema,正常匯入路徑缺表情境不存在,關閉。

## Mike 待辦

- Apple Developer portal 給 `com.mikelin.workitout` 開 Sign in with Apple capability;iOS 真機實測登入。
- 模擬器/真機驗看波 2:Dashboard 五區塊 + 換帳號警告清資料劇本(測試登入是裝置固定 UUID,驗對話框要 iOS 真機或手改 owner prefs 模擬)。
- develop 領先 origin 15 commits(2026-08-04 收斂時),要推說一聲(推前必問)。

## 決策狀態

全部定案 ✅(同步波前置的戰爭迷霧仍掛:同步 API 細設、部署、Auth token/session;同步波備忘:本機 apple_user_id 不可當帳號 key、Android 同步前不上架 Play、隱私同意文案改版)。詳見 `.claude/decisions/2026-07-24-三平台雲端同步方向.md`。

## 工作規則(Mike 2026-07-24 定)

- UI-first 垂直切片;grill 用 `grilling` skill;領域語言進 `CONTEXT.md`、術語進 `docs/GLOSSARY.md`;社群 skill 裝前安全審閱。
- 每波:驗收(大腦親跑)+ review chain + Mike 驗看 → merge。
- brief 模板已於 2026-08-04 補常備紀律(async 失敗路徑、快取生命週期、清除後不變式)——波 2 退件教訓,寫 brief 照抄。

## 波次規劃

3. 記訓練核心流(開訓練→選動作→記組→完成、模板)← **下一波(③merge 收尾後)**
4. 數據 Stats(fl_chart)
5. 歷史 + 體重 + 目標 + 成就
6. 設定(消費 legacy prefs)
7. 掛同步波:Go 後端 + 同步 + 真 Auth + 隱私改版(強制 security + db review)+ sqlite3_flutter_libs EOL 遷移波、dart format 專波擇機插入
8. 發布波(三平台)

## 波 3 進行中(2026-08-04 開)

- 決策已裁(見 `.claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md`):進行中訓練 = Drift 草稿寫穿(endedAt NULL);種五個系統模板(照 iOS DEBUG mock 定案);兩段式拆工。
- **第一段:完成(2026-08-05)**:①選動作器(review 三輪,merge b3ec808)+ ③模板(migration v1→v2 nullable + 五系統模板種子 + CRUD + applyTemplate;code/db 雙審各兩輪,merge a758ac3)+ 接線(a2508dc,fake→真 picker,crud 測試駕駛真 picker)。develop 親驗:analyze 0、test 261/261、web build ✓。②brief 要點:模板列表入口掛 workout tab(補裁④)、applyTemplate 消費 `AppliedTemplate`(null→3 組×10 次)。
- **第二段:實作中斷,WIP 保存待續(2026-08-05 收斂)**。branch `feature/wave3-workout-core`,WIP commit **9c3a418(勿 merge,未驗證)**:17 檔 +3011 行——repository 增量方法、workout controller、start/in-progress/summary 三畫面、記組 sheet(add_set_sheet)、休息計時(rest_timer_bar/controller)、OneRM 計算器、四個測試檔含 e2e 骨架;dashboard 兩測試檔也有對齊改動(草稿隔離)。**接手步驟**:(1) 開新工人 checkout 該分支,先跑 analyze + `flutter test` 盤點現況;(2) 對照下方「第二段 brief 要點」逐項補完;(3) 完成後照流程:大腦親驗 + 五核心防護雙向變異 → code+db 雙審 → merge → 收波。
- **第二段 brief 要點(接手照此驗收)**:A 開始畫面(自由/`showTemplatePicker`→AppliedTemplate/模板管理入口 Navigator.push);B 草稿寫穿(開始即建 endedAt=NULL row,每操作即時落庫,repository 允許新增增量方法);C 重啟恢復對話框(繼續=完整還原含 startedAt,放棄=刪草稿 cascade);D 進行中畫面對等 iOS(記組 sheet 重量/次數/RPE/暖身/休息 90s 可調 0-300、上一組帶入、存組自動啟動休息倒數±15s、即時統計每秒跳、放棄必須有確認框[iOS TODO 我們要做]);E 完成結算(completeWorkout 統計語意須對齊 iOS **排除暖身組**、OneRM 照 iOS 移植、createIfNewPR、summary 報告);F 草稿不污染 Dashboard 查詢(fetchByDateRange/fetchRecent/countWorkouts/calculateTotalVolume 過濾 endedAt NULL,勿破壞波 2 dashboard 測試)。**狀態機矩陣逐格測**:開始連點、有草稿再開始、完成冪等不重複 PR、放棄後再放棄 no-op、結算中不可放棄、休息中存組重啟計時。**草稿不變式**:重啟還原逐欄斷言、完成/放棄後無殘留、草稿不入統計。**五核心防護(草稿唯一、完成冪等、暖身排除、草稿隔離、放棄刪草稿)必附雙向變異輸出**。禁:動 schema、動其他 feature(dashboard 只讀)、動 picker/templates 既有實作、動 router(F 必要時最小改動單獨回報)、push、merge。②訓練核心流——開始(自由/模板)、草稿寫穿、記組(重量/次數/RPE/暖身/休息計時)、上一組帶入、即時統計、放棄確認(iOS 是 TODO,我們要做)、完成結算(completeWorkout + OneRM PR 偵測 `createIfNewPR`)、summary 報告、啟動偵測未完成草稿詢問恢復/放棄;Dashboard M3 invalidate 已保證切回首頁刷新。
- iOS 基準要點(探路 2026-08-04):進行中純記憶體無恢復(我們改草稿)、AddSetSheet 預設休息 90s 可調 0-300、PR 用 OneRMCalculator(工人讀 iOS 原始碼對等)、匯入路徑統計是複製舊值而新寫入路徑 completeWorkout 現算(語意已對齊,別動)。

## 下一步

1. 收第一段兩工人 → 驗收 + review → merge + 接線 → 開第二段②。
2. develop 已推(9690e6a);波 2 遺留判斷題仍待裁(riverpod 38 秒重試等,見上方遺留節)。
