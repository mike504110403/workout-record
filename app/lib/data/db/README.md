# data/db

Drift(SQLite)資料庫定義放這裡：table schema、DAO、migration。

硬性驗收條件(見 `.claude/decisions/2026-07-22-flutter-kickoff.md`):首次啟動需偵測舊
CoreData SQLite 檔並無縫匯入 Drift,升級不得遺失任何訓練歷史。實作 migration 時務必
以此為前提設計。
