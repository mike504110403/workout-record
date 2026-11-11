# WIP — Flutter 版上架準備

更新：2026-11-12

## 任務背景與目標

健身紀錄 App 從 SwiftUI 改寫成 Flutter(`app/`),接管已上架 iOS app(`com.mikelin.workitout`),資料直連 Supabase。2026-11-11 /mvp 畢業,目前 TestFlight 內測中,目標是送 App Store 正式上架。之後工程走 quick/solo/feature/bug/mega,主 checkout 恆 develop、改動在 worktree。

## 已完成(全在 origin/develop)

- `4262b4a` 上線前加固:刪帳號撤銷 Apple 授權(Edge Function `apple-revoke` 已部署 dev+prod)、刪舊 CoreData 與 UserDefaults、首次登入比對舊 Apple ID、session 改 Keychain。
- `bce72fc` 介面改版:4 分頁+全螢幕訓練、計畫組打勾才記錄、各頁去標題、懶建置。
- `4eb7c8f` 上架前必做:上傳時自建動作被他帳號佔用改指或建複本(完成旗標 v2、舊使用者靜默只補缺)、隱私權政策改寫(Mike 已確認)、Android 關備份與換機轉移。
- workout-prod:migration 0100–0600 已跑;Apple 登入開、Email 關。

## 收斂時進行中

- **TestFlight `2.0.0 (8)`** 已上傳(含 `4eb7c8f`,連 workout-prod),build 號已 commit。
- **舊 iOS 1.1.1(8)** 已上傳、Apple 處理完、出口合規已設;等 Mike 在 App Store Connect 建 1.1.1 版、選 build 8、填更新說明、選審過自動發布、送審。(原生 Xcode 專案檔不在 git,版號 1.1.1/8 只改在主 checkout 的 `ios/WorkoutRecord/WorkoutRecord.xcodeproj`)

## 待 Mike

- TestFlight 手測(2.0.0(8)):Mike 說直接在 TestFlight 測,不跑清單;回饋後開 /bug 或 /quick。
- 本機殘留分支 `wt/ui-polish/flow`(內容已全在 develop,hook 擋 -D):`git branch -D wt/ui-polish/flow`。
- 可選:在 prod SQL Editor 跑跨帳號動作引用檢查(SQL 在本 session 2026-11-12 回覆裡;只有 Mike 在測,預期 0)。

## Flutter 版送審時必做

- 公開新版 `docs/privacy.html`(此 repo 未開 GitHub Pages,確認 App Store 隱私網址實際託管處)。
- App Store Connect 隱私營養標籤:收集使用者 ID、姓名、Email、健身資料;不追蹤;無分析。
- `CLAUDE.md` 地雷區「privacy.html 之前勿動」一句改寫。

## 非阻斷(全在 `~/.claude/ledgers/workout-record.md`)

- v1 補送 recompute 失敗後重試不再重算;主上傳的雲端草稿成孤兒;首頁模板 chip 抓整筆訓練;apple-revoke 無限流;Drift schema 快照;Android apk 未 build(本機無 SDK,驗證債);過時註解數處。
- 長期:Google 登入、升 Flutter stable、sqlite3_flutter_libs EOL、全 repo dart format、強制更新設定位置。

## 下一步

等 Mike 的 TestFlight 回饋;沒回饋前可挑 ledger 非阻斷項開 /quick。
