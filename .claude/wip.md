# WIP — 三平台改寫(2026-07-24 起)

> **新 session 接手:讀完本檔即可動工。Mike 喊「繼續」= 接「波 8」待做片,不需再問。**

## 現況(2026-11-10,stage: mvp)

- **2026-11-10 Mike 裁示轉 /mvp**(覆寫入選條件:iOS 版已上架,Flutter 版未發布即視為 MVP;Flutter 首次發布＝畢業,總審必含 CoreData 匯入與 schema migration)。MVP 規則:直接在 develop 小顆 commit,不開 worktree、不跑 review chain。
- 波 0~7 已推 origin/develop(2026-11-10,8060bc9)。
- 波 6 內容:設定主頁四組、個人資料頁、關於頁、偏好頁(主題/休息秒數/1RM 公式/kg-lb)、全 app kg/lb 顯示層、接線(themeMode、預設休息秒數、Brzycki/Lander 補實作)。

## 下一步:波 7 改 Supabase(2026-11-10 Mike 裁示,取代自建 Go 後端)

- 架構:**直接連 Supabase(同記帳 app)**,不再以 Drift 為主;沒網路不能記訓練。登入 Apple＋Google(`signInWithIdToken`)。
- Supabase:新 org(PRO)專案 `workout-dev`,URL/ref/publishable key/DB 密碼在 repo 根 `.env`(已 gitignore,不進 git)。prod 等發布波再開。
- 做法:8 個 repository 抽介面＋Supabase 實作(公開 API 不變);Drift 實作留作測試假件,`USE_MOCK` 切換;依 `tables.dart` 寫 schema＋RLS＋GRANT migration(新表不自動 expose、已開 automatic RLS);舊 CoreData 照舊先進本機 Drift,登入後一次性上傳。
- 參考實作:`~/Documents/self/accounting`(`lib/data/supabase_client.dart`、`lib/data/auth.dart`、`supabase/migrations/`、`docs/adr/0005`)。
- Supabase Apple provider 已開;Google 待 Mike 建三組 OAuth client(先跳過)。
- **進度(2026-11-10)**:資料層 a8f4a58、migration 已推 workout-dev(4 支,遠端清單一致、anon 被拒)、Apple 登入 bccf019(預設連雲端;USE_MOCK=true 走 Drift)。600/600 綠。Google 登入 Mike 裁示先跳過(Web/Android 雲端模式暫無登入)。
- **2026-11-10 收尾**:舊資料上傳 d03fda9、隱私文案＋分頁 668e7a0、session 被動結束監聽(本 commit)。638 綠。
- **待做片**:(1) Mike 真機 Apple 登入實測(含舊資料上傳狀態看設定頁);(2) Google 登入(Mike 裁示先跳過);(3) 上架前改 docs/privacy.html(1.2/1.3/2/3/4.1/5 節,Firebase→Supabase、刪 analytics/crash、刪除帳號管道)與同意頁 analytics key 改名;(4) 遠端 max_rows 確認維持 1000。

## 波 8:上架缺口(2026-11-10 起)

- 刪除帳號 6dced61:RPC `delete_my_account`(security definer,刪 auth.users,資料全 cascade;本機 rollback 實測 A 刪光、B 與 66 系統動作完好、anon/無 uid 被拒)+ 設定頁兩段確認 + 成功後清本機 Drift 並退休舊 iOS 匯入。migration 0500 已推 workout-dev(2026-11-10,遠端清單一致、anon 呼叫 42501)。
- **待做**:Apple 授權撤銷(App Store 要求刪帳號時 revoke Apple token;需 Mike 提供 Sign in with Apple 的 .p8 key、Key ID、Team ID,走 Edge Function 呼叫 appleid.apple.com/auth/revoke);隱私頁/關於頁補「設定 > 刪除帳號」管道說明(併 privacy.html 改寫)。
- 進行中:訓練中離線草稿(雲端模式草稿存本機、完成時 create_workout 一次上傳、失敗保留可重試)。
- 已完成:動作/模板清單離線快取(1218ab7、04451b8)、_resolveUserId 抽共用 df47a41、graft 接線 f200911。資料匯出 Mike 裁示不做。
- 2026-11-10 做完 iOS 對等 1/2/5:自定義動作管理 afc7dee(軟刪除,FK 擋實體刪)、PR 詳情頁 6e40ea9、關於頁聯絡/服務條款/刪帳說明＋休息結束震動 05f12e7。721 綠。
- TODO:PR 列表卡與 `getPRSummary` 用寫入當下存的 1RM,詳情頁用偏好公式重算——非 Epley 且 reps>1 時兩邊數字/「當前 PR」可能不同;要一致需改列表卡與 repository 挑選邏輯。目標肌群多選(模型無欄位)未做。
- iOS 對等缺口(2026-11-10 盤點,孤兒死碼不移植:成就、日曆規劃、Progress、圓餅圖等):(1) 自定義動作管理(編輯/刪除,中);(2) PR 詳情頁(趨勢圖+歷史,中);(3) 強制更新(中,需定版本設定放 Supabase 哪);(4) 使用教學頁(小~中);(5) 服務條款+關於頁 mailto(小);休息結束震動(小);通知設定 iOS 是空殼(只有測試通知),要不要做真提醒待裁。

- 不再適用:原「同步波前置決策」(updatedAt 增量拉推/LWW/墓碑)因改直連作廢,見 git 歷史。

## 待 Mike 裁示(紅)

- **[已修碼,待 Mike 出版]** 上架中 iOS 版會刪 30 天前的訓練(2026-11-10 Mike 同意建議,已拿掉呼叫,xcodebuild 成功;版本號仍 1.1(5),送審前需升版,且 Flutter 版號要大於它):`ios/.../Services/DataRetentionService.swift:11`(保留 30 天)、`:55-74`(刪 startedAt < cutoff 的 WorkoutEntity,級聯刪動作與組),由 `WorkoutRecordApp.swift:80` init → `:183` 每週執行一次。2025-10-22 2b4afff 引入。影響:真實用戶的 iOS 歷史只剩近 30 天(PR 保留),Flutter 首次匯入也只拿得到 30 天。建議:iOS 出一版只拿掉 `:183` 這行(維護模式允許修 bug),越早越好;已刪的資料無法救回。
- 同檔 `WorkoutRecordApp.swift:86-126`:CoreData 模型版本字串不符就整個刪庫重建(目前 "2.3")。未來若改模型版本字串會清空用戶資料;維護模式不改模型即無影響,記錄備查。

## Mike 待辦

- 模擬器/瀏覽器驗看波 2~6(波 6 重點:設定頁四組、個人資料清空不回填、偏好四項切換生效、lb 模式全 app 顯示與輸入)。
- Apple Developer portal 開 Sign in with Apple capability;iOS 真機實測登入。

## 遺留(判斷題,不擋;累積自波 2~5 review)

- **架構類**:`_resolveUserId` 六份複本(+goals)該抽 `features/auth` 共用;format 函式多份(dashboard/stats/history)該進 core;肌群篩選多選疊線(iOS 對等缺口);riverpod defaultRetry 38 秒重試鈕;intl 統一(date picker 測試依賴未掛 localizations)。
- **波 5 新增**:刪除與列表 fetchAll 飛行中的時序窗口幽靈列(DB 正確,refresh 即消;最小修法=delete 成功後 invalidateSelf);日曆錯誤重試保月在 view 層無測試釘(靠 copyWithPrevious 機制+註解);edit 錯誤文案不分流(PR 結算/recomputeSummary 失敗也顯示「更新組數失敗」,但資料其實已寫入);`_confirmAndDelete` 與 `_addSet`/`_editSet` 各兩份重複(第三處出現再抽);goals `_prefillIfNeeded` build 期寫 controller.text(現況安全,脆弱慣例);歷史頁 FEATURE_MAP 宣稱的搜尋/篩選/排序/無限滾動(iOS 也沒做,做不做待裁);成就波規劃(獨立波,基準=Achievement.swift 22 項+AchievementCheckerService 可抄邏輯)。
- **小項(波 2~4)**:filter 切換丟飛行中時間範圍切換(毫秒窗口)、波 4 兩處變異存活(軸標籤對齊/時間口徑)、C 線 1RM 趨勢 x 軸標籤重複風險、`_liftLabels` 兩份、PR 分組 mutable 值物件、accent 色寫死、首訪雙查存疑、Drift 秒級時間精度、帳號隔離三判斷題、import_retry alreadyLanded 訊息分支無測試、GoalProgress 型別化。
- **專波待排**:全 repo dart format(49/69 檔)、sqlite3_flutter_libs EOL 遷移、v1/v2 schema 快照改 drift_dev dump + SchemaVerifier(v3 前)、web 平台 migration smoke。

