# 2026-07-22 — Flutter 改寫啟動:範圍與技術選型

## 背景

延續 [2026-07-22-flutter-rewrite.md]:Mike 拍板直接以 Flutter 完全改寫,功能照現有 iOS 版對等,之後上架取代並新增 Android 版。

## 決定(Mike 逐項拍板)

1. **Firebase 先不接**:Flutter 版第一版不含 Firebase(無 Analytics、無 Firestore)。
   - Apple 登入:保留 Sign in with Apple(`sign_in_with_apple` 套件),與現況相同為本機狀態,不接任何後端。
   - 版本強制更新:改用 iTunes Lookup API(`itunes.apple.com/lookup?bundleId=...`)查最新版本,不再依賴 Firestore `app_config`。
2. **舊資料無縫帶過**:同 bundle ID 更新上架,首次啟動偵測舊 CoreData SQLite 檔,原地讀取匯入 Drift 資料庫。這是硬性驗收條件——升級不得遺失任何訓練歷史。
3. **同 repo `app/` 目錄**:與 `.claude/`、`docs/` 共用;`ios/` 舊專案保留至 Flutter 版上架穩定後才刪(期間仍是線上維護對象與功能對照基準)。
4. **技術選型**:Riverpod(+riverpod_annotation)/ Drift(SQLite)/ fl_chart / go_router。UI 語言沿用 zh-TW 為主。

## 身分與版號

- Bundle ID(iOS)與 applicationId(Android):`com.mikelin.workitout`
- 接手版號自 1.1(5) 之後,Flutter 首發預計 2.0.0
- iOS 最低版本:17.6(與現行一致);Android minSdk 26+

## 對等基準

功能清單以 `docs/FEATURE_MAP.md` + `ios/` 現行程式碼為準;資料模型以 `docs/DATABASE_SCHEMA.md` + `WorkoutRecord.xcdatamodeld` 為準。

## 反悔訊號

沿用 2026-07-22-flutter-rewrite.md 的停損條件。
