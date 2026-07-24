# WIP — 三平台改寫(2026-07-24)

## 現況

- 分支 `feature/flutter-coredata-import`:CoreData→Drift 匯入完成、大腦驗收過,但 **review chain 打回(共同 blocker:結構層 FK workoutId/workoutExerciseId/templateId/exerciseId 無孤兒防護,一筆懸空→整批 rollback→永久匯不進)**。已派 `coredata-fixfk-worker`(sonnet)修復:父列不存在 skip+warn、exerciseId 對不上補建佔位動作、AppDelegate channel 移到 super 後、補孤兒測試 ≥6。修完**重跑 review chain** 才 commit + merge。
- Review 剩餘 minor(下一波再修,勿忘):匯入失敗持久化 log(spec 4.6)、連續失敗 3 次標記 permanently + UI 手動重試(4.6)、匯入統計持久化(4.5)、legacy_prefs_importer 零測試。
- develop 已含:v1.2 Swift 修正、docs/Claude 系統、Flutter scaffold、完整資料層(49 測試)。develop 領先 origin,未推(推前要問 Mike)。

## 決策狀態(全部定案 ✅,2026-07-24)

- ✅ 帳號:Apple + Google 雙登入
- ✅ 隱私改版:掛同步波再改(驗收硬檢核)
- ✅ Skill:flutter-tester + owasp-mobile-security-checker 已裝(已安全審閱)
- ✅ 同步架構:**完全自建後端(Go + SQLite + Litestream)+ 自寫簡易同步(updatedAt 增量 + LWW + 墓碑)**;PowerSync 經深挖後由 Mike 否決(雙 schema/約束流失/meta 牆)
- ✅ 升 Flutter:3.38.5 → 最新 stable(Dart ≥3.11),解 meta 天花板,升完重訂 pin
- ⏸ 戰爭迷霧(掛同步波前再解):同步 API 細部設計、部署細節(伺服器/Docker/TLS/web 靜態檔)、Auth token 驗證與 session 實作

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

1. 收 `coredata-fixfk-worker` → 驗收 → 重跑 review chain → commit → merge --no-ff 回 develop
2. 執行波 0(升 Flutter),回報驗證結果
3. 波 1 起逐波派工
