// 平台共用的匯入結果型別,native(io)/web 兩邊實作都靠它溝通。
// 抽成獨立檔案是因為 [CoreDataImporter] 本體(coredata_importer_io.dart /
// coredata_importer_web.dart)依平台走 conditional export(見
// coredata_importer.dart),但 [ImportResult] / 完成旗標的 key 兩邊要共用
// 同一份定義,不能各自宣告一份。

/// SharedPreferences 旗標:CoreData 匯入是否已完成(成功或確認無需匯入)。
/// 注意:找不到舊檔(全新安裝 / Android)時這個旗標也會設成 true(見
/// coredata_importer_io.dart `importIfNeeded`),所以它不能拿來判斷「這台
/// 裝置有沒有真的匯入過舊資料」——那個判斷要用 [kCoreDataImportedUserIdKey]
/// 存不存在,不能用這個旗標(血緣誤判修正,見 review 2026-07-30)。
const kCoreDataImportCompletedKey = 'coredata_import_completed';

/// SharedPreferences:CoreData 真正匯入成功時,這次匯入實際落地的主要
/// 使用者 id(單一使用者 App,取匯入器內部 user id 對映/佔位補建邏輯的
/// 結果,見 coredata_importer_io.dart `_importFromFile`)。只在真正執行過
/// 匯入(不是「舊檔不存在」的 skip 分支)且成功時才會寫入,是判斷「這台
/// 裝置有沒有 CoreData 匯入血緣」的明確訊號——取代原本誤用
/// [kCoreDataImportCompletedKey] 的判斷。
const kCoreDataImportedUserIdKey = 'coredata_imported_user_id';

/// 匯入結果:各表匯入筆數(以「讀到的舊資料筆數」計,對應「不遺失任何訓練
/// 歷史」這條硬性要求的量化驗證) + 是否成功 + 非致命警告,供之後 UI 顯示。
class ImportResult {
  const ImportResult({
    required this.success,
    required this.skipped,
    this.errorMessage,
    this.tableCounts = const {},
    this.warnings = const [],
  });

  const ImportResult.skippedNoOldDb()
      : success = true,
        skipped = true,
        errorMessage = null,
        tableCounts = const {},
        warnings = const [];

  final bool success;

  /// true 代表沒有實際跑匯入(舊檔不存在,或先前已標記完成,或目前平台
  /// 天然不可能有舊檔——例如 web)。
  final bool skipped;

  final String? errorMessage;
  final Map<String, int> tableCounts;
  final List<String> warnings;

  @override
  String toString() =>
      'ImportResult(success: $success, skipped: $skipped, '
      'errorMessage: $errorMessage, tableCounts: $tableCounts, '
      'warnings: $warnings)';
}
