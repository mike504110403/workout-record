# 2026-07-22 — 開發工具由 Cursor 轉 Claude Code,文檔體系重整

## 背景

專案先前以 Cursor 開發,累積 30+ 個 AI 產出的一次性 .md(上架 checklist、截圖指南、修 bug 紀錄)散落根目錄與 docs/,無 .cursorrules、無專案級規則檔。轉用 Claude Code 後需要:專案共識檔(CLAUDE.md)、決策紀錄、適用的 skills。

## 選擇

- 建 `CLAUDE.md`(精簡:方向、架構、build 指令、地雷)+ `.claude/decisions/`。
- 一次性文檔全部移入 `docs/archive/`(不刪,保留考古價值);長期文檔留 `docs/`。
- Skills:只裝與 Flutter 方向相容者(App Store 審核檢查、fastlane 雙平台發佈、ASO/截圖產出);Swift 深耕類 skills 不裝。安裝前逐一驗證 repo 真實性與內容安全。
- Hooks(SwiftLint/SwiftFormat 類)不做——iOS 版已是維護模式;Flutter 專案啟動時再配 dart format/analyze hooks。
