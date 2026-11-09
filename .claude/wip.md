# WIP — 三平台改寫(2026-07-24 起)

> **新 session 接手:讀完本檔即可動工。Mike 喊「繼續」= 直接開波 6(流程見下方「下一步」),不需再問。**

## 現況(2026-11-10,stage: mvp)

- **2026-11-10 Mike 裁示轉 /mvp**(覆寫入選條件:iOS 版已上架,Flutter 版未發布即視為 MVP;Flutter 首次發布＝畢業,總審必含 CoreData 匯入與 schema migration)。MVP 規則:直接在 develop 小顆 commit,不開 worktree、不跑 review chain。
- 波 0~6 全部落在 develop(最後 4c40e36,**未推 origin**)。基線:analyze 0、test 579/579、build web ✓。
- 波 6 內容:設定主頁四組、個人資料頁、關於頁、偏好頁(主題/休息秒數/1RM 公式/kg-lb)、全 app kg/lb 顯示層、接線(themeMode、預設休息秒數、Brzycki/Lander 補實作)。

## 下一步:波 7 改 Supabase(2026-11-10 Mike 裁示,取代自建 Go 後端)

- 架構:**直接連 Supabase(同記帳 app)**,不再以 Drift 為主;沒網路不能記訓練。登入 Apple＋Google(`signInWithIdToken`)。
- Supabase:新 org(PRO)專案 `workout-dev`,URL/ref/publishable key/DB 密碼在 repo 根 `.env`(已 gitignore,不進 git)。prod 等發布波再開。
- 做法:8 個 repository 抽介面＋Supabase 實作(公開 API 不變);Drift 實作留作測試假件,`USE_MOCK` 切換;依 `tables.dart` 寫 schema＋RLS＋GRANT migration(新表不自動 expose、已開 automatic RLS);舊 CoreData 照舊先進本機 Drift,登入後一次性上傳。
- 參考實作:`~/Documents/self/accounting`(`lib/data/supabase_client.dart`、`lib/data/auth.dart`、`supabase/migrations/`、`docs/adr/0005`)。
- **待 Mike**:Supabase Auth 開 Apple、Google provider;Google Cloud 建 iOS/Android/Web 三組 OAuth client 給 client ID。
- **進度(2026-11-10)**:資料層 a8f4a58、migration 已推 workout-dev(4 支,遠端清單一致、anon 被拒)、Apple 登入 bccf019(預設連雲端;USE_MOCK=true 走 Drift)。600/600 綠。Google 登入 Mike 裁示先跳過(Web/Android 雲端模式暫無登入)。
- **待做片**:(1) Mike 真機 Apple 登入實測;(2) 舊 CoreData 資料登入後一次性上傳(cloud_upload.dart TODO,含系統動作 id 依名稱對應、升級用戶略過 onboarding 失效);(3) 隱私文案改雲端版(login/Onboarding/About/PrivacyConsent);(4) onAuthStateChange 監聽 token 失效;(5) fetchAll 超 1000 筆分頁;(6) Google 登入。
- 不再適用:原「同步波前置決策」(updatedAt 增量拉推/LWW/墓碑)因改直連作廢,見 git 歷史。

## Mike 待辦

- 模擬器/瀏覽器驗看波 2~6(波 6 重點:設定頁四組、個人資料清空不回填、偏好四項切換生效、lb 模式全 app 顯示與輸入)。
- Apple Developer portal 開 Sign in with Apple capability;iOS 真機實測登入。

## 遺留(判斷題,不擋;累積自波 2~5 review)

- **架構類**:`_resolveUserId` 六份複本(+goals)該抽 `features/auth` 共用;format 函式多份(dashboard/stats/history)該進 core;肌群篩選多選疊線(iOS 對等缺口);riverpod defaultRetry 38 秒重試鈕;intl 統一(date picker 測試依賴未掛 localizations)。
- **波 5 新增**:刪除與列表 fetchAll 飛行中的時序窗口幽靈列(DB 正確,refresh 即消;最小修法=delete 成功後 invalidateSelf);日曆錯誤重試保月在 view 層無測試釘(靠 copyWithPrevious 機制+註解);edit 錯誤文案不分流(PR 結算/recomputeSummary 失敗也顯示「更新組數失敗」,但資料其實已寫入);`_confirmAndDelete` 與 `_addSet`/`_editSet` 各兩份重複(第三處出現再抽);goals `_prefillIfNeeded` build 期寫 controller.text(現況安全,脆弱慣例);歷史頁 FEATURE_MAP 宣稱的搜尋/篩選/排序/無限滾動(iOS 也沒做,做不做待裁);成就波規劃(獨立波,基準=Achievement.swift 22 項+AchievementCheckerService 可抄邏輯)。
- **小項(波 2~4)**:filter 切換丟飛行中時間範圍切換(毫秒窗口)、波 4 兩處變異存活(軸標籤對齊/時間口徑)、C 線 1RM 趨勢 x 軸標籤重複風險、`_liftLabels` 兩份、PR 分組 mutable 值物件、accent 色寫死、首訪雙查存疑、Drift 秒級時間精度、帳號隔離三判斷題、import_retry alreadyLanded 訊息分支無測試、GoalProgress 型別化。
- **專波待排**:全 repo dart format(49/69 檔)、sqlite3_flutter_libs EOL 遷移、v1/v2 schema 快照改 drift_dev dump + SchemaVerifier(v3 前)、web 平台 migration smoke。

