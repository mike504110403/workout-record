# WorkoutRecord — 健身紀錄 App

SwiftUI 健身紀錄 app,已上架 App Store。

**專案方向(2026-07-22 定):以 Flutter 完全改寫並新增 Android 版;現有 iOS 版進入維護模式——只修 bug、不加新功能、不做重構美化。** 重大決策見 `.claude/decisions/`。

## Flutter 版(app/,開發中)

- 選型:Riverpod + Drift(SQLite)+ fl_chart + go_router;**第一版不接 Firebase**(登入用 sign_in_with_apple 本機狀態、版本檢查用 iTunes Lookup API)
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
- 隱私文案(Onboarding / About / PrivacyConsent)必須與「資料存裝置本機」的現狀一致
- App Store 的隱私政策網頁由 `docs/privacy.html` + GitHub Pages 供應,勿刪勿移

## 文檔地圖

- `docs/FEATURE_MAP.md`、`DATABASE_SCHEMA.md`、`TECH_STACK.md`:長期參考(Flutter 遷移的功能對照基準)
- `docs/archive/`:上架期一次性文檔(checklist、修 bug 紀錄),僅供考古
- `.claude/decisions/`:重大決策紀錄(背景、選項、選擇、理由)
