// 平台共用的匯入結果型別,native(io)/web 兩邊實作都靠它溝通。
// 抽成獨立檔案是因為 [CoreDataImporter] 本體(coredata_importer_io.dart /
// coredata_importer_web.dart)依平台走 conditional export(見
// coredata_importer.dart),但 [ImportResult] / 完成旗標的 key 兩邊要共用
// 同一份定義,不能各自宣告一份。

/// SharedPreferences 旗標:CoreData 匯入是否已完成(成功或確認無需匯入)。
const kCoreDataImportCompletedKey = 'coredata_import_completed';

/// SharedPreferences:連續失敗次數計數器(見 spec 4.6 節)。每次匯入失敗
/// (未捕捉例外)遞增,成功時歸零。
const kCoreDataImportAttemptsKey = 'coredata_import_attempts';

/// SharedPreferences 旗標:連續失敗達重試上限(3 次)後標記 true,
/// `importIfNeeded` 之後會直接 skip,不再自動重試,需使用者手動點擊
/// Settings 頁的重試按鈕(清掉本旗標與 [kCoreDataImportAttemptsKey])才會
/// 再跑一次。
const kCoreDataImportFailedPermanentlyKey = 'coredata_import_failed_permanently';

/// SharedPreferences:成功匯入後的各表落地筆數,以 JSON 字串存放,供之後
/// debug / 跟使用者核對「東西是不是都搬過來了」(spec 4.5 節)。
const kCoreDataImportTableCountsKey = 'coredata_import_table_counts';

/// 匯入結果:各表**落地筆數**([tableCounts],實際成功寫入 Drift 的筆數;
/// 孤兒防護略過的列不計入,另見 [skippedCounts])+ 是否成功 + 非致命警告,
/// 供之後 UI 顯示。
///
/// [tableCounts] 的語意是「這次呼叫實際 insert 進 Drift 的筆數」,不是
/// 「讀到的舊資料筆數」——兩者只在該表完全沒有孤兒略過時才相等。系統動作
/// 對映到既有 seed(見 coredata_importer_io.dart `_importExercises`)不算
/// 孤兒略過(資料本身沒有遺失,只是合併到既有列),因此 exercises 沒有對應
/// 的 [skippedCounts] 概念;真正會略過整列的只有 template_exercises /
/// workout_exercises / workout_sets 三張表的結構層孤兒防護。
class ImportResult {
  const ImportResult({
    required this.success,
    required this.skipped,
    this.errorMessage,
    this.tableCounts = const {},
    this.skippedCounts = const {},
    this.warnings = const [],
    this.permanentlyFailed = false,
  });

  const ImportResult.skippedNoOldDb()
      : success = true,
        skipped = true,
        errorMessage = null,
        tableCounts = const {},
        skippedCounts = const {},
        warnings = const [],
        permanentlyFailed = false;

  /// 連續失敗達重試上限、已標記 [kCoreDataImportFailedPermanentlyKey] 時,
  /// `importIfNeeded` 直接回傳這個結果,不再嘗試開檔匯入。
  const ImportResult.skippedPermanentlyFailed()
      : success = false,
        skipped = true,
        errorMessage = '先前已連續失敗達重試上限,已標記為 permanently failed,'
            '需在設定頁手動重試。',
        tableCounts = const {},
        skippedCounts = const {},
        warnings = const [],
        permanentlyFailed = true;

  final bool success;

  /// true 代表沒有實際跑匯入(舊檔不存在,或先前已標記完成,或目前平台
  /// 天然不可能有舊檔——例如 web,或連續失敗已達上限)。
  final bool skipped;

  final String? errorMessage;

  /// 各表**落地筆數**(實際 insert 筆數,見類別註解)。
  final Map<String, int> tableCounts;

  /// 各表因結構層孤兒防護而略過的筆數(只有 template_exercises /
  /// workout_exercises / workout_sets 會有非零值)。
  final Map<String, int> skippedCounts;

  final List<String> warnings;

  /// true 代表本次結果就是因為 [kCoreDataImportFailedPermanentlyKey] 已設置
  /// 而直接 skip(見 [ImportResult.skippedPermanentlyFailed])。
  final bool permanentlyFailed;

  @override
  String toString() =>
      'ImportResult(success: $success, skipped: $skipped, '
      'errorMessage: $errorMessage, tableCounts: $tableCounts, '
      'skippedCounts: $skippedCounts, warnings: $warnings, '
      'permanentlyFailed: $permanentlyFailed)';
}
