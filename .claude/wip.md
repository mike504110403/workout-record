# WIP — 三平台改寫(2026-07-24 起)

> **新 session 接手:讀完本檔即可動工。Mike 喊「繼續」= 直接開波 6(流程見下方「下一步」),不需再問。**

## 現況(2026-09-01,波 0~5 全部完成並 merged;波 5 未推 origin)

- **波 0** 升 Flutter 3.44.8 + web 平台;**波 1** 登入 + Onboarding;**import-minors** 匯入核帳收尾;**波 2** 帳號隔離(owner 認領/換帳號清資料)+ Dashboard 五區塊 + 複審收尾;**波 3** 選動作器 + 模板(schema v2 migration + 五系統模板種子)+ 記訓練核心流(草稿寫穿/重啟恢復/記組/休息計時/PR 結算/summary);**波 4** Stats tab 全對等(訓練統計容量趨勢/體重/經典三項三子頁 + PR 排行頁);**波 5** 歷史頁(列表+日曆雙檢視/詳情頁/刪除)+ 編輯已完成訓練(Flutter 超車 iOS:寫穿模型+recomputeSummary+PR 只升不降挑最高 1RM)+ 目標設定頁(週次數+目標體重兩欄,0/留空=未設定,Dashboard 導航接線)。
- **基線(大腦親跑,2026-09-01)**:`flutter analyze` 0 issues、`flutter test` **497/497**、`flutter build web` ✓。schemaVersion 2。develop=9597301(**波 5 一顆,未推 origin——推前問 Mike,走 /ship**)。
- **波 5 裁示記錄**:成就**獨立成波**(iOS 端實為孤兒功能:MainTabView 無入口、三套實作全死碼/半成品/假資料,親驗 2026-09-01;22 項成就定義在 Achievement.swift 可當未來基準;FEATURE_MAP 無此規劃);iOS 編輯按鈕是死的、篩選面板 print-only(親驗)——Flutter 不對等這些殼。recomputeSummary bump updatedAt(同步波 updatedAt 增量拉推,不 bump 會漏推編輯)。
- 重大決策全在 `.claude/decisions/`。既有雷 ledger:`~/.claude/ledgers/workout-record.md`(2026-09-01 起,首雷:copyWith `??` 語意無法清 null)。
- 工作流慣例(歷波驗證有效):工人 brief 用 `/brief` 模板(常備紀律+變異逐規則列+張力回報);多工人同 repo 各掛 worktree;跨工人接縫用「議定契約 + WAVE{n}-MERGE placeholder,merge 時大腦換接」;每輪 major 修復必附雙向變異輸出且大腦至少親測一個;merge 後大腦跑全量三指令。

## 下一步(Mike 喊「繼續」執行 1;其餘等 Mike 開口)

1. **開波 6:設定 tab(消費 legacy prefs)**。流程照慣例:
   - 探路平行(scout-trace iOS 基準 `Views/Settings/` 全部 View+SettingsView 結構+FEATURE_MAP Tab5 段;scout-read Flutter 側 settings_page placeholder、legacy_prefs_importer 已搬了哪些 key、既有可接資產如 GoalSettingsPage 入口)。
   - 可能分岔先 AskUserQuestion 裁(單位偏好 kg/lb 的消費面、匯出資料、關於/隱私頁內容、登出/刪帳號範圍)。
   - 拆工平行派(範圍互斥 + worktree),驗收 → review chain → merge 接線 → 收波。
2. Mike 驗看波 2~5(見「Mike 待辦」)。
3. 裁遺留判斷題(見「遺留」,不擋波 6)。

## Mike 待辦

- 模擬器/瀏覽器驗看波 2~5。波 5 重點路徑:歷史列表/日曆切換、點日期看當天清單、詳情頁(summary/容量分布/明細含暖身標記)、滑動刪除+詳情頁刪除(皆有確認)、**編輯流**(詳情頁鉛筆→改組重量/增刪組/增刪動作/改備註→返回詳情頁與列表都反映新值、PR 只升不降)、Dashboard 目標卡點入設定頁(存週次數/目標體重→返回首頁進度更新;存 0/清空→顯示空狀態;目標體重接體重頁目標線)。**波 5 已知觀察項**(手測順不順眼,不是 bug):目標卡版式(標題卡外+chevron)、詳情頁刪除中 UI、編輯頁無日期顯示。
- 舊待辦:驗看波 2~4 清單與 iOS 刻意差異清單(見 git 歷史 a37fe58 版 wip.md,或直接問大腦);Apple Developer portal 開 Sign in with Apple capability;iOS 真機實測登入。
- develop 已含波 5 一顆 commit 未推 origin——要推說「推」(走 /ship)。

## 遺留(判斷題,不擋;累積自波 2~5 review)

- **架構類**:`_resolveUserId` 六份複本(+goals)該抽 `features/auth` 共用;format 函式多份(dashboard/stats/history)該進 core;肌群篩選多選疊線(iOS 對等缺口);riverpod defaultRetry 38 秒重試鈕;intl 統一(date picker 測試依賴未掛 localizations)。
- **波 5 新增**:刪除與列表 fetchAll 飛行中的時序窗口幽靈列(DB 正確,refresh 即消;最小修法=delete 成功後 invalidateSelf);日曆錯誤重試保月在 view 層無測試釘(靠 copyWithPrevious 機制+註解);edit 錯誤文案不分流(PR 結算/recomputeSummary 失敗也顯示「更新組數失敗」,但資料其實已寫入);`_confirmAndDelete` 與 `_addSet`/`_editSet` 各兩份重複(第三處出現再抽);goals `_prefillIfNeeded` build 期寫 controller.text(現況安全,脆弱慣例);歷史頁 FEATURE_MAP 宣稱的搜尋/篩選/排序/無限滾動(iOS 也沒做,做不做待裁);成就波規劃(獨立波,基準=Achievement.swift 22 項+AchievementCheckerService 可抄邏輯)。
- **小項(波 2~4)**:filter 切換丟飛行中時間範圍切換(毫秒窗口)、波 4 兩處變異存活(軸標籤對齊/時間口徑)、C 線 1RM 趨勢 x 軸標籤重複風險、`_liftLabels` 兩份、PR 分組 mutable 值物件、accent 色寫死、首訪雙查存疑、Drift 秒級時間精度、帳號隔離三判斷題、import_retry alreadyLanded 訊息分支無測試、GoalProgress 型別化。
- **專波待排**:全 repo dart format(49/69 檔)、sqlite3_flutter_libs EOL 遷移、v1/v2 schema 快照改 drift_dev dump + SchemaVerifier(v3 前)、web 平台 migration smoke。

## 同步波(波 7)前置決策(開工前必裁,db review 盤點)

1. push query 必帶 `endedAt IS NOT NULL`(草稿不得上雲);2. 多裝置草稿衝突要 partial unique index 或伺服器仲裁(**勿在無 dedup 下加 unique index,匯入會炸**);3. pull 不得覆蓋/刪本機草稿;4. 子列無 isSynced/deletedAt→只能整包 workout 取代,子列級增量要加欄位;5. 草稿 updatedAt 不隨子列變動(**已完成訓練的編輯會 bump updatedAt——波 5 定,整包重推靠它**)。既有備忘:apple_user_id 不可當帳號 key、伺服器驗 identityToken+nonce、Android 同步前不上架 Play、隱私文案改版、getCurrentPR 無 userId 過濾 + PersonalRecords 無索引(同步波前處理)。

## 波次規劃

6. 設定(消費 legacy prefs)← **下一波**
7. 同步波:Go 後端 + 同步 + 真 Auth + 隱私改版(強制 security+db review)
8. 發布波(三平台)
9. (未排)成就波:獨立設計(入口/持久化/計算),基準見「波 5 裁示記錄」

## 工作規則(Mike 定,詳見歷波 git log 與 memory)

- UI-first 垂直切片;每波:驗收(大腦親跑)+ review chain + Mike 驗看 → merge;dev 推 remote 前必問 Mike。
- 領域語言 `CONTEXT.md`、術語 `docs/GLOSSARY.md`;社群 skill 裝前安全審閱。
