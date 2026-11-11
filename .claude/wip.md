# WIP — Flutter 版(2026-11-11 收斂)

> **新 session 接手:讀完本檔即可動工。** /mvp 已畢業(2026-11-11),之後工程走 quick/solo/feature/bug/mega,主 checkout 恆 develop、一切改動在 worktree(/feature-flow)。

## 現況

- origin/develop = `b1e422c`。TestFlight 最新 `2.0.0 (7)`,連 workout-prod(打包:`app/tool/build_ios_prod.sh --upload`)。
- workout-prod:migration 0100–0600 已跑;Apple 登入開、Email 關;Edge Function `apple-revoke` 已部署(dev+prod,secrets 用 AuthKey_37258C87DX)。
- 2026-11-11 落地:上線前加固 `4262b4a`(撤銷 Apple 授權、刪舊 CoreData 與 UserDefaults、首次登入比對舊 Apple ID、session 改 Keychain、上傳略過他帳號資料)、介面改版 `bce72fc`(4 分頁+全螢幕訓練、計畫組、各頁去標題、懶建置)。

## 等 Mike

- TestFlight 2.0.0(7) 手測:開始→記組→完成回首頁數字更新;模板計畫組打勾;收起→繼續→放棄;iOS 返回手勢;升級後不需重登;刪 App 重裝要重登;實際刪一個測試帳號(驗 Apple 撤銷)。
- 本機殘留分支 `wt/ui-polish/flow`(內容已全在 develop,hook 擋 -D),Mike 可自行 `git branch -D wt/ui-polish/flow`。

## App Store 正式上架前必做

- `cloud_upload.dart:333-341`:自建動作 id 被他帳號佔用時連帶剔除本人子列且寫完成旗標(詳見 ledger `~/.claude/ledgers/workout-record.md`)。
- 改寫 `docs/privacy.html`(Firebase→Supabase、刪帳號管道)。
- Android `allowBackup`。
- 其餘非阻斷項全在 ledger。
