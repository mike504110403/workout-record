# WIP — 三平台改寫(2026-07-24)

## 現況(2026-08-04 波 2 收斂)

- **波 0(升 Flutter + web)**、**波 1(登入 + Onboarding)**、**import-minors 波** 均已 merge develop(細節見 git log 與 `.claude/decisions/`)。
- **波 2 ①帳號隔離:完成,merged**(d81d5f8):owner 認領 + 換帳號警告清資料,依 `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`(含「實作補充」節:重種動作庫、血緣消耗時機=換人清除時、清除退休匯入旗標、已知保留範圍)。review:code r1 FAIL→r2 PASS、security r1 FAIL→r2 PASS。
- **波 2 ②Dashboard:完成,merged**(dff922f):五區塊對等 iOS(今日概覽/快速操作/目標進度/本週統計/最近訓練),`features/dashboard/` + router 分頁切回 invalidate。review 三輪(r3 PASS,M3 真測試經大腦親自變異驗證)。與 iOS 刻意差異:ISO 週一起算、無目標顯示空狀態、最近訓練日期格式 `M/d HH:mm`、不複製 iOS 鼓勵訊息 0-1% 邊界 bug。
- **merge 後 develop 全驗證(大腦親跑)**:analyze 0 issues、test 195/195、web build 成功。
- **波 2 ③import minors:實作完成但卡在 review 修復,未 merge**。branch `feature/wave2-import-minors`(commit 9677951,基於 9fac376),worktree `.claude/worktrees/agent-aa0b7abf3e20217d5`。六項功能 reviewer 確認都達標;打回 3 major 修復已派工(session 收斂時進行中,**接手先看該 worktree 的 git log/status 有沒有修復 commit**):
  1. 還原四檔整檔 dart format(scope creep,只留 ~507 行語意改動)
  2. `coredata_importer_test.dart:918` 測試名假變異宣稱誠實化 + `:915` 改 set 比對 actualTableName
  3. `_oldDbTableCounts` 逐表 try/catch 降級(缺表不得弄死 alreadyLanded 補旗標;已裁決採 db-reviewer 方案)+ 補「舊庫缺 ZWORKOUTSETENTITY 仍成功」測試
  4. 順修:刪 `ImportResult.skippedAlreadyLanded()` 死碼建構子;quoting 對齊;`_oldDbTableCounts` 註解(凍結 schema/交集比對/哪些 key 應相等)
  - 修完流程:大腦親驗(analyze+test+抽查排版還原幅度)→ code+db 聚焦複審 → merge --no-ff → merge 後全驗證。**注意 merge 衝突**:develop 的帳號隔離波也改了 `coredata_importer_result.dart` / `legacy_prefs_importer.dart`(新增 export 常數),要手解。

## 波 2 遺留(判斷題,不擋,收下波或 Mike 裁)

- riverpod `defaultRetry` 讓 Dashboard 錯誤畫面 ~38 秒後才出現重試鈕(生產重試路徑無測試);候選:自訂 retry 縮短退避 / loading 分支提早顯示重試。
- Drift `dateTime()` 秒級精度:同秒多筆時「取最新」排序不定(目前僅測試踩到,已在測試端規避)。
- intl 已宣告未使用,dashboard 手刻日期格式化——要不要統一,下波前決定。
- 帳號隔離 code r2 判斷題:退休旗標邏輯搬 migration 側 `retireImports()`、onboarding 清除三步抽私函式、11 表守門改逐表塞資料驗清空。
- StatCard 抽共用(等波 4 Stats 第二個使用者出現)、GoalProgress 型別化、「首頁該刷新」知識搬 Dashboard 側(波 3 加詳情頁時回看)。
- 全 repo dart format 專波(波 0 遺留,49/69 檔會動)。

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

## 下一步

1. **收尾③**:依上方「波 2 ③」段落流程走完 merge。
2. 開波 3 前:Mike 驗看波 2、裁遺留判斷題、決定 develop 要不要推。
