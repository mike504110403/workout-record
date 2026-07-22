# WorkoutRecord — 健身紀錄 App

SwiftUI 健身紀錄 app,已上架 App Store。

**專案方向(2026-07-22 定):以 Flutter 改寫並新增 Android 版;現有 iOS 版進入維護模式——只修 bug、不加新功能、不做重構美化。** 重大決策見 `.claude/decisions/`。

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
- 隱私文案(Onboarding / About / PrivacyConsent)必須與「資料存裝置本機」的現狀一致
- App Store 的隱私政策網頁由 `docs/privacy.html` + GitHub Pages 供應,勿刪勿移

## 文檔地圖

- `docs/FEATURE_MAP.md`、`DATABASE_SCHEMA.md`、`TECH_STACK.md`:長期參考(Flutter 遷移的功能對照基準)
- `docs/archive/`:上架期一次性文檔(checklist、修 bug 紀錄),僅供考古
- `.claude/decisions/`:重大決策紀錄(背景、選項、選擇、理由)
