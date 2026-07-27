// 平台共用的匯入結果型別,native(io)/web 兩邊實作都靠它溝通。
// 抽成獨立檔案是因為 [CoreDataImporter] 本體(coredata_importer_io.dart /
// coredata_importer_web.dart)依平台走 conditional export(見
// coredata_importer.dart),但 [ImportResult] / 完成旗標的 key 兩邊要共用
// 同一份定義,不能各自宣告一份。

/// SharedPreferences 旗標:CoreData 匯入是否已完成(成功或確認無需匯入)。
const kCoreDataImportCompletedKey = 'coredata_import_completed';

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
