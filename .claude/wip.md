# WIP — 三平台改寫(2026-07-24)

## 現況(2026-08-05 波 3 收波)

- **波 0(升 Flutter + web)、波 1(登入 + Onboarding)、import-minors 波、波 2(帳號隔離 + Dashboard + import 複審收尾)**:全部 merged,細節見 git log 與 `.claude/decisions/`。
- **波 3(記訓練核心流 + 模板):完成,全部 merged**:
  - ①選動作器(分類/搜尋/最愛/自訂動作,契約 `showExercisePicker(context, {multiSelect})`;review 三輪)。
  - ③模板(schema v1→v2 Templates.userId nullable + 五系統模板種子 + CRUD + `applyTemplate`;code/db 雙審各兩輪;接線 fake→真 picker)。
  - ②訓練核心流(最終 merge):開始畫面(自由/模板/模板管理入口)、**草稿寫穿**(endedAt NULL=進行中,每操作即時落庫,repository 增量方法群)、重啟恢復對話框、進行中畫面(記組 sheet 重量/次數/RPE/暖身/休息 90s 可調、上一組帶入、存組自動休息倒數±15、即時統計、放棄確認框)、完成結算(暖身排除統計對齊 iOS、Epley OneRM、createIfNewPR、summary)、草稿隔離(五讀查詢過濾)、匯入 NULL ZENDEDAT 保險。review:code/db 各三輪(r1 6 major→r2 code 抓編輯路徑死開關→r3 大腦聚焦確認),五核心防護 + 追加 major 全數雙向變異驗證(工人 + 大腦各自親測)。
- **收波後 develop 全驗證(大腦親跑,2026-08-05)**:analyze 0 issues、**test 328/328**、web build 成功。
- 決策檔:`2026-08-04-波3訓練流草稿寫穿與系統模板.md`(含四項補裁 + migration 裁決)。

## 同步波(波 7)前置決策(db review 盤點,開工前必裁)

1. 草稿不得被推上雲:push query 必須帶 `endedAt IS NOT NULL`(isSynced 預設 false 含草稿)。
2. 多裝置草稿衝突:同 userId 兩筆 endedAt NULL 只有 partial unique index 或伺服器仲裁能解(單機已由 controller 查 DB 守住;**勿在無 dedup 步驟下順手加 unique index——匯入可能多筆 NULL 會炸**)。
3. pull 路徑不得覆蓋/刪除本機草稿。
4. workout_exercises/workout_sets 無 isSynced/deletedAt——同步只能「整包 workout 取代」;要子列級增量需加欄位(schema 變更)。
5. 草稿的 workouts.updatedAt 不隨子列變動——若同步靠 updatedAt 衝突偵測要先解。
(既有備忘:本機 apple_user_id 不可當帳號 key、伺服器驗 identityToken+nonce、Android 同步前不上架 Play、隱私同意文案改版。)

## 遺留(判斷題,不擋,收波/下波裁)

- **波 3 新增**:`getCurrentPR` 無 userId 過濾 + PersonalRecords 無索引(帳號隔離換帳清庫後單機不可達,同步波前處理)、RestTimer adjust 歸零後拉正的防禦缺口、deleteSet renumber 逐列 UPDATE N 次往返、`_draftCheckStarted` 煙霧測試升級(若未來加第二個檢查入口)、startFromTemplate 撞既有草稿時靜默丟棄所選模板(現不可達,變可達時補提示)。
- **波 2 遺留**:riverpod defaultRetry 38 秒重試鈕、Drift 秒級時間精度、intl 統一、帳號隔離三判斷題(retireImports 搬家/清除三步抽函式/11 表守門逐表塞資料)、StatCard 抽共用(波 4 第二使用者出現時)、GoalProgress 型別化、import_retry alreadyLanded 訊息分支無測試。
- 全 repo dart format 專波(波 0 遺留)。
- v1/v2 schema 快照改 drift_dev schema dump + SchemaVerifier(v3 前補)、web 平台 migration smoke。

## Mike 待辦

- **模擬器/瀏覽器驗看波 2+3**:Dashboard 五區塊、換帳號清資料劇本、選動作器、模板(五系統模板/CRUD/套用)、完整記訓練流(開始→記組→休息計時→完成 summary→首頁反映)、重啟恢復草稿劇本。
- Apple Developer portal 開 Sign in with Apple capability;iOS 真機實測登入。
- develop 有新 merge 未推(推前必問;origin 曾由 Mike 自行推至收斂點)。
- 波 2/3 遺留判斷題要不要掛波 4。

## 工作規則(Mike 2026-07-24 定;brief 模板 2026-08-04 起含常備紀律)

- UI-first 垂直切片;每波:驗收(大腦親跑)+ review chain + Mike 驗看 → merge;修復輪每個帶測試的 major 必附雙向變異輸出。
- 領域語言進 `CONTEXT.md`、術語進 `docs/GLOSSARY.md`;社群 skill 裝前安全審閱。

## 波次規劃

4. 數據 Stats(fl_chart)← **下一波**
5. 歷史 + 體重 + 目標 + 成就(History 頁會消費波 3 的已完成訓練;目標設定頁補 Dashboard 的導航缺口)
6. 設定(消費 legacy prefs)
7. 掛同步波:Go 後端 + 同步 + 真 Auth + 隱私改版(強制 security + db review;上方前置決策先裁)+ sqlite3_flutter_libs EOL 遷移、dart format 專波擇機插入
8. 發布波(三平台)

## 下一步

1. Mike 驗看波 2+3 → 裁遺留與推送 → 開波 4(Stats)。
