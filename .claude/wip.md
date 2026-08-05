# WIP — 三平台改寫(2026-07-24 起)

> **新 session 接手:讀完本檔即可動工。Mike 喊「繼續」= 直接開波 5(流程見下方「下一步」),不需再問。**

## 現況(2026-08-05,波 0~4 全部完成並 merged + 已推 origin)

- **波 0** 升 Flutter 3.44.8 + web 平台;**波 1** 登入 + Onboarding;**import-minors** 匯入核帳收尾;**波 2** 帳號隔離(owner 認領/換帳號清資料)+ Dashboard 五區塊 + 複審收尾;**波 3** 選動作器 + 模板(schema v2 migration + 五系統模板種子)+ 記訓練核心流(草稿寫穿/重啟恢復/記組/休息計時/PR 結算/summary);**波 4** Stats tab 全對等(訓練統計容量趨勢/體重/經典三項三子頁 + PR 排行頁)。
- **基線(大腦親跑,2026-08-05)**:`flutter analyze` 0 issues、`flutter test` **447/447**、`flutter build web` ✓。schemaVersion 2。
- 重大決策全在 `.claude/decisions/`(最近三份:2026-08-04 帳號隔離、2026-08-04 波3 草稿寫穿與系統模板含全部補裁、2026-07-24 三平台方向)。
- 工作流慣例(歷波驗證有效):工人 brief 用 `/brief` 模板(常備紀律+變異逐規則列+張力回報);多工人同 repo 各掛 worktree;跨工人接縫用「議定契約 + WAVE{n}-MERGE placeholder,merge 時大腦換接」;每輪 major 修復必附雙向變異輸出且大腦至少親測一個;merge 後大腦跑全量三指令。

## 下一步(Mike 喊「繼續」執行 1;其餘等 Mike 開口)

1. **開波 5:歷史 + 目標設定頁 + 成就**(體重已在波 4 做完)。流程照慣例:
   - 探路(兩 haiku Explore 平行):iOS 基準 `ios/.../Views/History/`、`Views/Goals/`(或 GoalSettingsView)、成就相關 Views/ViewModels + FEATURE_MAP Tab4/目標/成就段;Flutter 側盤 history_page placeholder、可用查詢(fetchAll 已排草稿)、UserGoal/PersonalRecord 資產、Dashboard 目標區塊沒接的導航(波 2 遺留:GoalSettingsView 入口)。
   - 有真分岔先 AskUserQuestion 裁(可能的:成就系統 iOS 有多少實作 vs FEATURE_MAP 願望清單的落差怎麼切;歷史頁編輯/刪除已完成訓練的範圍)。
   - 拆工平行派(範圍互斥 + worktree),驗收 → review chain → merge 接線 → 收波,全程照本檔慣例。
2. Mike 驗看波 2~4(見「Mike 待辦」)。
3. 裁遺留判斷題(見「遺留」,不擋波 5)。

## Mike 待辦

- 模擬器/瀏覽器驗看波 2~4:Dashboard、換帳號清資料、選動作器、模板 CRUD/套用、記訓練全流程(開始→記組→休息計時→完成 summary→首頁反映)+ 重啟恢復草稿、Stats 三子頁 + PR 排行。**iOS 刻意差異清單**(驗看時別當 bug):Stats 預設停「訓練統計」非體重、肌群篩選單選、三項手動紀錄全列、date picker 預設輸入模式(可切回日曆)、Dashboard ISO 週一起算、進行中訓練會寫穿草稿且重啟詢問恢復。
- Apple Developer portal 開 Sign in with Apple capability;iOS 真機實測登入。
- 波 5 開工前若想先裁遺留,清單在下方。

## 遺留(判斷題,不擋;累積自波 2~4 review)

- **架構類**:`_resolveUserId` 五份複本(dashboard/picker/templates/powerlifting/pr)該抽 `features/auth` 共用;format 函式多份(dashboard/stats)該進 core;肌群篩選多選疊線(iOS 對等缺口);riverpod defaultRetry 38 秒重試鈕;intl 統一(date picker 測試依賴未掛 localizations,掛 zh_TW 時要同步改)。
- **小項**:filter 切換丟飛行中時間範圍切換(毫秒窗口)、波 4 兩處變異存活(軸標籤對齊/時間口徑,程式對無測試釘)、C 線 1RM 趨勢 x 軸標籤重複風險(同 B 線已修型)、`_liftLabels` 兩份、PR 分組 mutable 值物件、accent 色寫死(repo 慣例不一)、首訪雙查存疑(r2 實測未重現)、Drift 秒級時間精度、帳號隔離三判斷題(retireImports 搬家等)、import_retry alreadyLanded 訊息分支無測試、GoalProgress 型別化、「首頁該刷新」知識搬 Dashboard 側。
- **專波待排**:全 repo dart format(49/69 檔)、sqlite3_flutter_libs EOL 遷移、v1/v2 schema 快照改 drift_dev dump + SchemaVerifier(v3 前)、web 平台 migration smoke。

## 同步波(波 7)前置決策(開工前必裁,db review 盤點)

1. push query 必帶 `endedAt IS NOT NULL`(草稿不得上雲);2. 多裝置草稿衝突要 partial unique index 或伺服器仲裁(**勿在無 dedup 下加 unique index,匯入會炸**);3. pull 不得覆蓋/刪本機草稿;4. 子列無 isSynced/deletedAt→只能整包 workout 取代,子列級增量要加欄位;5. 草稿 updatedAt 不隨子列變動。既有備忘:apple_user_id 不可當帳號 key、伺服器驗 identityToken+nonce、Android 同步前不上架 Play、隱私文案改版、getCurrentPR 無 userId 過濾 + PersonalRecords 無索引(同步波前處理)。

## 波次規劃

5. 歷史 + 目標設定 + 成就 ← **下一波**
6. 設定(消費 legacy prefs)
7. 同步波:Go 後端 + 同步 + 真 Auth + 隱私改版(強制 security+db review)
8. 發布波(三平台)

## 工作規則(Mike 定,詳見歷波 git log 與 memory)

- UI-first 垂直切片;每波:驗收(大腦親跑)+ review chain + Mike 驗看 → merge;dev 推 remote 前必問 Mike。
- 領域語言 `CONTEXT.md`、術語 `docs/GLOSSARY.md`;社群 skill 裝前安全審閱。
