// 編譯出 web/drift_worker.js 用的入口(來源:package:drift/web/drift_worker.dart,
// drift 官方 web 支援指引 https://drift.simonbinder.eu/web/ 的標準做法)。
// 編譯指令見 lib/data/db/README.md 的「web 資產來源」一節。
import 'package:drift/wasm.dart';

void main() {
  WasmDatabase.workerMainForOpen();
}
