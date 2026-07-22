# 2026-07-22 — 以 Flutter 改寫,iOS 版進入維護模式

## 背景

App 已上架 App Store(SwiftUI + CoreData + Firebase)。Mike 有出 Android 版的實際需求與計畫,但只有 side project 的零碎時間,無法長期維護兩套原生程式碼。原本計畫對 Swift 做積極簡化(拆大檔、抽元件)。

## 選項

- A:維持 SwiftUI,另寫原生 Android(Kotlin)——一人零碎時間養兩套原生,不現實。
- B:Flutter 全面改寫,一套 Dart 雙平台——app 是表單+列表+圖表的 CRUD 型應用,無重度 Apple 專屬依賴,適合跨平台。
- C:KMP 共享邏輯——app 主體是 UI,共享價值有限。

## 選擇:B(Flutter 改寫)

執行方式:**先收尾 iOS v1.2 並保持可上架,Flutter 版當全新專案開發,功能對等後才切換**;期間 iOS 版只修 bug。原「Swift 積極簡化」取消——不再投資即將被取代的程式碼。

## 反悔訊號

- Flutter 版動工三個月後功能對等度不到一半 → 停損,回頭維護 SwiftUI 版
- Android 上架後證實無需求 → 停止跨平台投資
- 想以 HealthKit / Apple Watch 深度整合為核心賣點 → 原生價值回升,重新評估

## 待決(Flutter 專案啟動前必須先討論)

1. 既有用戶 CoreData 資料遷移方案(同 bundle ID 接手)
2. 專案位置(同 repo `flutter/` vs 新 repo)
3. 技術選型:狀態管理、本地儲存、FlutterFire
4. 切換與上架策略
