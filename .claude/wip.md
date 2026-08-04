# WIP — 三平台改寫(2026-07-24)

## 現況

- **CoreData→Drift 匯入已完成並 merge 回 develop**(fixfk 修復 + review chain 通過,commit d481904 / merge 30b993e)。
- **波 0(升 Flutter + web 平台)完成並 merge 回 develop(2026-07-27,merge c6dedc4)**:Flutter 3.38.5→3.44.8(Dart 3.12.2)、web 平台啟用(drift WasmDatabase + checked-in sqlite3.wasm / drift_worker.js,見 app/lib/data/db/README.md)、DB 連線層改 drift_flutter(native 路徑不變)、CoreData 匯入器 io/web conditional export 分流、iOS 部分 pods 遷 SwiftPM。review chain 通過(1 major 2 minor 已修);merge 後 analyze 零 issue + test 68/68 重跑確認。
- **依賴 pin 重訂:Mike 選 A(2026-07-27)**——pin 維持現狀(驗證過的版本);sqlite3_flutter_libs 已 EOL,遷移(sqlite3 3.5 native assets + 移除 EOL 套件 + 換 wasm + 重編 worker)**另開獨立波次,勿忘排程**。
- Review 剩餘 minor(Mike 已准併入下一波,勿忘):匯入失敗持久化 log(spec 4.6)、連續失敗 3 次標記 permanently + UI 手動重試(4.6)、匯入統計持久化(4.5)、legacy_prefs_importer 零測試、template_exercises 的 exerciseId 孤兒 skip 無專屬測試、tableCounts=讀取量非落地量(有孤兒時偏高,要當零遺失證據需另計)。
- develop 已含:v1.2 Swift 修正、docs/Claude 系統、Flutter scaffold、完整資料層、CoreData 匯入(68 測試)。develop 領先 origin,未推(推前要問 Mike)。

## 決策狀態(全部定案 ✅,2026-07-24)

- ✅ 帳號:Apple + Google 雙登入
- ✅ 隱私改版:掛同步波再改(驗收硬檢核)
- ✅ Skill:flutter-tester + owasp-mobile-security-checker 已裝(已安全審閱)
- ✅ 同步架構:**完全自建後端(Go + SQLite + Litestream)+ 自寫簡易同步(updatedAt 增量 + LWW + 墓碑)**;PowerSync 經深挖後由 Mike 否決(雙 schema/約束流失/meta 牆)
- ✅ 升 Flutter:3.38.5 → 最新 stable(Dart ≥3.11),解 meta 天花板,升完重訂 pin
- ⏸ 戰爭迷霧(掛同步波前再解):同步 API 細部設計、部署細節(伺服器/Docker/TLS/web 靜態檔)、Auth token 驗證與 session 實作
- ✅ **DB 帳號隔離:換帳號清本機資料(Mike 2026-08-04 拍板)**,見 `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`;owner 認領機制 + 血緣 key 一次性消耗,實作掛波 2;②同步波備忘:本機 apple_user_id 不可當帳號 key,伺服器須驗 identityToken+nonce;Android 在同步波前不得上架 Play(release build 只有測試登入);③隱私同意文案「分析/錯誤報告」描述了不存在的收集且強制必勾,維持照抄 iOS 或先拿掉,同步波隱私改版一併解

詳見 `.claude/decisions/2026-07-24-三平台雲端同步方向.md`。

## 工作規則(Mike 2026-07-24 定,memory 有檔)

- UI-first:照使用者操作順序垂直切片,每波可在模擬器/瀏覽器驗看;後端不排前面
- grill 用 `grilling` skill:一次一題、附推薦答案、確認共識才動工
- 專有名詞:領域語言進 `CONTEXT.md`,技術術語進 `docs/GLOSSARY.md`,隨決策即時補
- 社群 skill 優先,裝前安全審閱

## 波次規劃(Mike 2026-07-24 確認)

0. 升 Flutter + 依賴 pin 重訂 + 全驗證 ← **下一波,等 fixfk 工人收工後執行**(避免升版打斷其驗證)
1. 登入 + Onboarding(UI + 本機 session)
2. 首頁 Dashboard
3. 記訓練核心流(開訓練→選動作→記組→完成、模板)
4. 數據 Stats(fl_chart)
5. 歷史 + 體重 + 目標 + 成就
6. 設定(消費 legacy prefs)
7. 掛同步波:Go 後端 + 同步 + 真 Auth + 隱私改版(強制 security + db review)
8. 發布波(三平台)

每波:驗收(大腦親跑)+ review chain + Mike 模擬器/瀏覽器驗看 → merge。

## 下一步

1. **波 1 已 merge 回 develop(2026-07-30,merge 825a412)**:登入 + Onboarding 5 頁 + 隱私同意 + 本機 session + iOS entitlement。三輪 review(2 blocker、5 major 修畢)通過;merge 後 analyze 零 issue + test 123/123。Apple 真登入僅 iOS release;iOS debug/模擬器/Android/Web 走測試登入(裝置層 UUID 身分);升級血緣改判 `coredata_imported_user_id`。**Mike 待辦:Apple Developer portal 給 `com.mikelin.workitout` 開 Sign in with Apple capability;iOS 真機實測登入(模擬器測不到)**
2. **import-minors 已 merge 回 develop(2026-08-04,merge a9954bf)**:六項 spec 4.5/4.6 收尾,經三輪修正(one-shot 重試、統計四份帳+核帳快照、alreadyLanded 多表多樣本偵測),終輪 code+db 複審 0 blocker/0 major。merge 衝突(importer io/result、settings_page、測試)大腦親解,merge 後 analyze 零 issue + test 155/155 + web build 成功
3. **複審遺留 minor(已准掛下波,勿忘)**:_verifiedTableCounts 改真 COUNT 表達式+allTables 遍歷、alreadyCompleted 觸發路徑補斷言、exercises 核帳等式(快照=種子+自訂落地)專屬測試、alreadyLanded 分支順記舊庫 COUNT、blocked UNIQUE 保險絲(可選)、統計參數群聚收 tally 物件、全 repo dart format(波 0 formatter fallout,另開波)
4. develop 領先 origin 7 個 commit(波 1 五個 + import-minors 兩個 merge),找時機問 Mike 要不要推
5. **下一波(波 2 Dashboard)開工前置**:等 Mike 決策「DB 層帳號隔離」(見上方待決策①),資料頁工人不得假設隔離已處理
