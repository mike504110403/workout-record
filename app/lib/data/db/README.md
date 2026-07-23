# data/db

Drift(SQLite)資料庫定義放這裡：table schema、DAO、migration。

硬性驗收條件(見 `.claude/decisions/2026-07-22-flutter-kickoff.md`):首次啟動需偵測舊
CoreData SQLite 檔並無縫匯入 Drift,升級不得遺失任何訓練歷史。實作 migration 時務必
以此為前提設計。

## Review 追蹤事項(2026-07-23 data-layer review)

- `WorkoutExercises.exerciseId` / `TemplateExercises.exerciseId` 未設 onDelete(= NO ACTION),
  且 foreign_keys pragma 已開。接「刪除自訂動作」UI 前必須處理:擋在 UI 層,
  或棄用 `ExerciseRepository.permanentDelete` 只留 soft delete(iOS 版語意是 nullify 不噴錯)。
- `rpe`/`restSeconds`:Drift 版真 NULL,Swift 版把 0 當「未填」。匯入舊資料時 0 值應轉為 NULL。
