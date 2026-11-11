> 2026-11-11 /mvp 畢業:Flutter 版連 workout-prod 發 TestFlight(真實資料),畢業總審完成(B1/M1/M2 已修),之後工程走 quick/solo/feature/bug/mega。

# WorkoutRecord — 健身紀錄 App

SwiftUI 健身紀錄 app,已上架 App Store。

**專案方向(2026-07-22 定 Flutter 改寫;2026-07-24 擴為 iOS/Android/Web 三平台 + 跨裝置同步):現有 iOS 版進入維護模式——只修 bug、不加新功能、不做重構美化。** 重大決策見 `.claude/decisions/`;領域語言見 `CONTEXT.md`,技術術語見 `docs/GLOSSARY.md`。

## Flutter 版(app/,TestFlight 內測中)

- 選型:Riverpod + Drift(SQLite)+ fl_chart + go_router;三平台(iOS/Android/Web)一起首發
- **後端:Supabase 直連(2026-11-10 改,同記帳 app;取代 07-24 的自建 Go 後端與 updatedAt/LWW/墓碑同步協定)**。資料讀寫直接走 Supabase(RLS 守權限),沒網路不能記訓練(進行中訓練草稿例外:存本機、完成時一次上傳)。舊 iOS CoreData 首啟先匯入本機 Drift,登入後一次性上傳(`app/lib/data/migration/cloud_upload.dart`)。帳號:Apple 登入(Google 暫緩,Web/Android 雲端模式暫無登入入口)。決策見 `.claude/decisions/2026-11-11-supabase直連與正式環境.md`
- **環境**:`workout-dev`(ap-south-1,連線資訊 repo 根 `.env`)給開發與 debug build;`workout-prod`(ap-northeast-1,`.env.prod`)給 TestFlight/App Store。兩檔皆 gitignore、權限 600。release build 不帶連線設定就拒絕啟動,打包一律 `app/tool/build_ios_prod.sh`(`--upload` 自動 build 號 +1 並上傳 TestFlight,金鑰在 `~/mike/asc/asc.env`)。migration 跑 dev 與 prod 都要先問 Mike;prod 走 `aws-1-ap-northeast-1.pooler.supabase.com`(直連會被拒)
- 本機開發:`flutter run -d chrome --dart-define=USE_MOCK=true` 不連任何雲端
- 升 Flutter 至最新 stable(Dart ≥3.11)已拍板未執行;升完重訂依賴 pin(現況因 meta 1.17.0 牆釘 drift 2.31 等)
- Bundle ID / applicationId:`com.mikelin.workitout`(接手現有 App Store app,自 1.1(5) 之後)
- 硬性驗收:首次啟動須把舊 CoreData SQLite 資料無縫匯入 Drift,升級不得遺失訓練歷史
- 功能對等基準:`docs/FEATURE_MAP.md` + `ios/` 現行程式碼;`ios/` 保留至 Flutter 版上架穩定後才刪
- 資料模型基準:`docs/COREDATA_MIGRATION_SPEC.md`(以 `Sources/WorkoutRecord.xcdatamodeld` 為準;**`docs/DATABASE_SCHEMA.md` 是舊後端規劃版,與實際不符勿當基準**;repo 根目錄那份 xcdatamodeld 是孤兒舊檔)
- 驗證:`flutter analyze` 零 error + `flutter test` + `flutter build ios --simulator` 成功

## 現況架構(iOS 版)

- SwiftUI + MVVM:`ios/WorkoutRecord/WorkoutRecord/Sources/{Views,ViewModels,Repositories,Services,Models,Utils}`
- 入口 `WorkoutRecordApp.swift` → Apple ID 登入檢查 → Onboarding → `MainTabView` 五個 tab(Dashboard / Workout / Stats / History / Settings)
- 資料:**本地 CoreData 是唯一資料源**(`Services/CoreDataStack.swift`,模型 `WorkoutRecord.xcdatamodeld`),存取一律走 `Repositories/`,無雲端同步
- Firebase 僅用於:匿名 Analytics、`app_config/version` 版本強制更新檢查(`VersionCheckService`)
- Apple ID 登入是本機狀態(UserDefaults),**未接 Firebase Auth**;正規認證留給 Flutter 版實作,不要在 Swift 版補

## Build 與驗證

```bash
cd ios/WorkoutRecord && xcodebuild -project WorkoutRecord.xcodeproj -scheme WorkoutRecord \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

無測試 target;任何改動至少確認 BUILD SUCCEEDED。Xcode 專案用 filesystem-synchronized groups,新增/刪除檔案不需改 pbxproj。

## 地雷與禁區

- **禁止未經 Firebase Auth 驗證的 Firestore 個資寫入**(users collection)——v1.2 曾引入、已因安全問題移除,見 decisions
- `UserPreferencesSyncService`、`CloudKitSyncService` 是半成品死碼,勿當現行功能參考
- iOS 版隱私文案(Onboarding / About / PrivacyConsent)必須與「資料存裝置本機」的現狀一致;Flutter 版資料在 Supabase,`docs/privacy.html` 要在 Flutter 版送審時改寫(現行 iOS 版仍在用,之前勿動)
- App Store 的隱私政策網頁由 `docs/privacy.html` + GitHub Pages 供應,勿刪勿移
- **改雲端系統動作名稱/分類的 migration**:必須等只有 v1 上傳旗標的使用者清零(或確認 TestFlight 全員已升到含 v2 旗標的版本)才能跑。否則 `cloud_upload.dart` 的 v1 補送會把本機系統動作當成被佔用,補回使用者在雲端刪掉的組/動作項目/PR、模板重複,並建出舊名稱複本(2026-11-12 db-review)

## 文檔地圖

- `docs/FEATURE_MAP.md`、`DATABASE_SCHEMA.md`、`TECH_STACK.md`:長期參考(Flutter 遷移的功能對照基準)
- `docs/archive/`:上架期一次性文檔(checklist、修 bug 紀錄),僅供考古
- `.claude/decisions/`:重大決策紀錄(背景、選項、選擇、理由)
