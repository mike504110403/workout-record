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

## Web 平台支援(2026-07-24,波 0 web 編譯修復)

`app_database.dart` 用 `drift_flutter` 的 `driftDatabase()` 做連線層 conditional
export(native → `NativeDatabase`,web → `WasmDatabase`),不再手動 import
`dart:io` / `drift/native.dart`。這解掉 web 編譯時 `package:sqlite3` FFI 綁定
(`dart:ffi`)被拉進 dart2js 導致的 `Only JS interop members may be 'external'`
編譯錯誤。

`drift_flutter` 曾因 Flutter 3.38.5 的 `meta 1.17.0` 版本天花板裝不上(見
`.claude/decisions/2026-07-24-三平台雲端同步方向.md`),3.44.8(meta 1.18.0)已解除,
現在可正常使用,不需要走 drift 官方手動 conditional import 那套(`connection/native.dart`
+ `connection/web.dart` + stub)。

### web 資產來源

- `web/sqlite3.wasm`:官方發佈,對應目前釘住的 `sqlite3_flutter_libs: 0.5.42`
  版本 —— <https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3_flutter_libs-0.5.42>
  (release asset `sqlite3.wasm`)。**升級 `sqlite3_flutter_libs` 版本時記得同步換這份 wasm。**
- `web/drift_worker.js`:從 `tool/drift_worker.dart`(內容即
  `package:drift/web/drift_worker.dart` 官方入口:`WasmDatabase.workerMainForOpen()`)
  用 Dart SDK 編譯出來,指令:
  ```bash
  dart compile js -o web/drift_worker.js tool/drift_worker.dart -O4
  ```
  **升級 `drift` 版本時記得重新編譯這份 worker js。**兩份資產都不進 `.gitignore`
  (build 產物但無法在 CI 免安裝 Dart SDK 之外重新生成 wasm 二進位,故 checked in)。
  編譯時順帶產生的 `drift_worker.js.deps` / `drift_worker.js.map` 是副產物,
  runtime 不需要,已列入 `.gitignore` 不進版控。
