// 舊 CoreData(WorkoutRecord.sqlite)→ Drift 匯入的 web no-op stub。
//
// web 平台天然不可能存在舊 iOS App 的 CoreData SQLite 檔(不同 App 沙盒、
// 不同作業系統),也不能 import dart:io / package:sqlite3(FFI 綁定在
// dart2js/dartdevc 編譯不過,見 app/lib/data/db/README.md web 支援章節)。
// 對外維持與 coredata_importer_io.dart 相同的 `CoreDataImporter.importIfNeeded`
// 簽章,呼叫端(main.dart)不需要知道目前是哪個平台實作(見
// coredata_importer.dart 的 conditional export)。
import '../db/app_database.dart';
import 'coredata_importer_result.dart';

export 'coredata_importer_result.dart';

class CoreDataImporter {
  const CoreDataImporter();

  Future<ImportResult> importIfNeeded(AppDatabase db) async {
    return const ImportResult.skippedNoOldDb();
  }

  /// web 平台天然不可能有連續失敗達上限的狀態(importIfNeeded 一律直接
  /// skippedNoOldDb),ImportRetryTile 也不會在 web 上渲染出重試按鈕——這裡
  /// 只是維持跟 io 版相同的介面(見檔案開頭註解),實際上不會被呼叫到。
  Future<ImportResult> retryAfterPermanentFailure(AppDatabase db) async {
    return const ImportResult.skippedNoOldDb();
  }
}
