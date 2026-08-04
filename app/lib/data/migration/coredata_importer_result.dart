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

/// SharedPreferences:連續失敗次數計數器(見 spec 4.6 節)。每次匯入失敗
/// (未捕捉例外)遞增,成功時歸零。
const kCoreDataImportAttemptsKey = 'coredata_import_attempts';

/// SharedPreferences 旗標:連續失敗達重試上限(3 次)後標記 true,
/// `importIfNeeded` 之後會直接 skip,不再自動重試,需使用者手動點擊
/// Settings 頁的重試按鈕(呼叫 [CoreDataImporter.retryAfterPermanentFailure])
/// 才會再跑一次。
const kCoreDataImportFailedPermanentlyKey = 'coredata_import_failed_permanently';

/// SharedPreferences:成功匯入後的各表**落地筆數**,以 JSON 字串存放,供之後
/// debug / 跟使用者核對「東西是不是都搬過來了」(spec 4.5 節)。
const kCoreDataImportTableCountsKey = 'coredata_import_table_counts';

/// SharedPreferences:成功匯入後的各表**結構層孤兒略過筆數**,以 JSON 字串
/// 存放,搭配 [kCoreDataImportTableCountsKey] 才能還原完整帳式(見
/// [ImportResult] 類別文件的落地量公式)。
const kCoreDataImportSkippedCountsKey = 'coredata_import_skipped_counts';

/// SharedPreferences:成功匯入後因「對映到既有種子,不重複 insert」而未落地
/// 的筆數(目前只有 exercises 表有此概念),以 JSON 字串存放。
const kCoreDataImportDedupedCountsKey = 'coredata_import_deduped_counts';

/// SharedPreferences:成功匯入後,因舊資料的 FK 對不上任何已知列而惰性補建
/// 的佔位列筆數(users / exercises 兩表),以 JSON 字串存放。這些是**額外
/// 新增**的列,不對應任何一筆舊庫來源資料。
const kCoreDataImportCreatedPlaceholdersKey = 'coredata_import_created_placeholders';

/// SharedPreferences:匯入收工那一刻(成功匯入 transaction 剛 commit,或
/// alreadyLanded 命中)對 Drift 各表下的 `SELECT COUNT(*)` 核帳快照,以 JSON
/// 字串存放——跟 [kCoreDataImportTableCountsKey] 不同,這是「此刻 Drift 裡
/// 實際有幾筆」的絕對數字(含既有種子動作等所有既存列),不是「這次呼叫落地
/// 了幾筆」的相對數字,兩者搭配才能在事後核對「東西是不是都在」,不需要另外
/// 記一份 seed 基準線。alreadyLanded 命中時沒有 tableCounts 可存,但這份快照
/// 一定會有,補上那個缺口。
const kCoreDataImportVerifiedCountsKey = 'coredata_import_verified_counts';

/// 帳號隔離換帳號清除用(見
/// `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`「實作補充」
/// 節與 session_controller.dart `confirmClearAndContinueLogin`):上一次
/// CoreData 匯入留下的統計類 key,不是使用者個資,但屬於「上一位帳號那次
/// 匯入」的殘留,換帳號確認清除時一併清掉,避免下一個帳號在設定頁看到
/// 前人的匯入統計。顯式列舉,不做前綴掃描。
const kCoreDataImportStatsKeys = <String>[
  kCoreDataImportTableCountsKey,
  kCoreDataImportSkippedCountsKey,
  kCoreDataImportDedupedCountsKey,
  kCoreDataImportCreatedPlaceholdersKey,
  kCoreDataImportVerifiedCountsKey,
];

/// 沒有實際跑匯入時,[ImportResult.skipped] = true 的具體原因,供 UI
/// (見 app/lib/features/settings/widgets/import_retry_tile.dart)顯示對應
/// 訊息,不要一律當成「未知錯誤」或籠統的「成功」。
enum ImportSkipReason {
  /// 舊 App 的 CoreData 檔不存在(全新安裝 / Android / 舊 App 從未初始化
  /// 過),沒有東西可以匯入。
  noOldDb,

  /// 連續失敗已達重試上限,需使用者手動重試,見
  /// [kCoreDataImportFailedPermanentlyKey]。
  permanentlyFailed,

  /// 「已 commit 未標旗」窗口:偵測到資料其實已經在 Drift 裡(先前的匯入
  /// transaction 其實成功了,只是寫完成旗標前 App 被中斷),已補寫完成
  /// 旗標,不重新跑一次匯入(避免撞主鍵)。見 [CoreDataImporter] 的
  /// `_detectAlreadyLanded`。
  alreadyLanded,

  /// 完成旗標([kCoreDataImportCompletedKey])已經設置——不論當初是因為
  /// 真的成功匯入、確認舊檔不存在、還是偵測到 [alreadyLanded] 而補寫,
  /// `importIfNeeded` 之後每次呼叫都會直接回這個,不冒用 [noOldDb](那個
  /// 專指「這次呼叫發現舊檔案不存在」,語意上不該用來代表「這次呼叫根本
  /// 沒去檢查舊檔案,因為早就標記完成了」)。
  alreadyCompleted,
}

/// 匯入結果:各表**落地筆數**([tableCounts])+ 是否成功 + 非致命警告,
/// 供之後 UI 顯示。
///
/// ## 落地量帳式(spec 4.5 節)
///
/// 對每一張來源表:`來源筆數(舊庫 SELECT COUNT(*))= 落地筆數([tableCounts])
/// + 結構層孤兒略過筆數([skippedCounts])+ 去重筆數([dedupedCounts])`。
///
/// - **落地筆數([tableCounts])**:這次呼叫實際 insert 進 Drift 的筆數。
///   users / exercises 兩表另外**加上**惰性補建的佔位列數
///   ([createdPlaceholders])——這些是額外新增、不對應任何舊庫來源列的
///   資料,因此不計入上面的帳式等號左邊(來源筆數),只計入右邊的落地量。
/// - **略過筆數([skippedCounts])**:結構層孤兒防護略過整列,只有
///   template_exercises / workout_exercises / workout_sets 三張表會有
///   非零值。
/// - **去重筆數([dedupedCounts])**:系統動作(isSystem = true)對映到
///   `seedIfEmpty()` 已建立的內建種子,不重複 insert,只記住 id 對映
///   (資料本身沒有遺失,只是合併到既有列)。目前只有 exercises 表有這個
///   概念。
/// - **補建佔位筆數([createdPlaceholders])**:舊資料的 FK(userId /
///   exerciseId)對不上任何已匯入的列時,惰性補建的佔位列(見
///   coredata_importer_io.dart `_resolveUserId` /
///   `_resolveOrCreatePlaceholderExercise`)。只有 users / exercises 兩表
///   會有非零值,且不是「來源」的一部分——是為了不讓子表資料(訓練歷史 /
///   PR)因為孤兒 FK 而遺失才新增的列。
class ImportResult {
  const ImportResult({
    required this.success,
    required this.skipped,
    this.errorMessage,
    this.tableCounts = const {},
    this.skippedCounts = const {},
    this.dedupedCounts = const {},
    this.createdPlaceholders = const {},
    this.warnings = const [],
    this.permanentlyFailed = false,
    this.skipReason,
  });

  const ImportResult.skippedNoOldDb()
      : success = true,
        skipped = true,
        errorMessage = null,
        tableCounts = const {},
        skippedCounts = const {},
        dedupedCounts = const {},
        createdPlaceholders = const {},
        warnings = const [],
        permanentlyFailed = false,
        skipReason = ImportSkipReason.noOldDb;

  /// 連續失敗達重試上限、已標記 [kCoreDataImportFailedPermanentlyKey] 時,
  /// `importIfNeeded` 直接回傳這個結果,不再嘗試開檔匯入。
  const ImportResult.skippedPermanentlyFailed()
      : success = false,
        skipped = true,
        errorMessage = '先前已連續失敗達重試上限,已標記為 permanently failed,'
            '需在設定頁手動重試。',
        tableCounts = const {},
        skippedCounts = const {},
        dedupedCounts = const {},
        createdPlaceholders = const {},
        warnings = const [],
        permanentlyFailed = true,
        skipReason = ImportSkipReason.permanentlyFailed;

  /// 「已 commit 未標旗」窗口命中(見 [ImportSkipReason.alreadyLanded]):
  /// 資料其實已經在 Drift 裡,只是完成旗標沒寫,已補寫旗標,不重新匯入
  /// (重新匯入會撞主鍵)。
  const ImportResult.skippedAlreadyLanded()
      : success = true,
        skipped = true,
        errorMessage = null,
        tableCounts = const {},
        skippedCounts = const {},
        dedupedCounts = const {},
        createdPlaceholders = const {},
        warnings = const [],
        permanentlyFailed = false,
        skipReason = ImportSkipReason.alreadyLanded;

  /// 完成旗標([kCoreDataImportCompletedKey])已設置,`importIfNeeded` 一
  /// 開頭就短路回這個,不去檢查舊檔案是否存在(見 [ImportSkipReason.alreadyCompleted]
  /// 的語意說明)。
  const ImportResult.skippedAlreadyCompleted()
      : success = true,
        skipped = true,
        errorMessage = null,
        tableCounts = const {},
        skippedCounts = const {},
        dedupedCounts = const {},
        createdPlaceholders = const {},
        warnings = const [],
        permanentlyFailed = false,
        skipReason = ImportSkipReason.alreadyCompleted;

  final bool success;

  /// true 代表沒有實際跑匯入(舊檔不存在,或先前已標記完成,或目前平台
  /// 天然不可能有舊檔——例如 web,或連續失敗已達上限,或偵測到資料已落地
  /// 只是旗標沒寫)。具體原因見 [skipReason]。
  final bool skipped;

  final String? errorMessage;

  /// 各表**落地筆數**(實際 insert 筆數,見類別文件的帳式說明)。
  final Map<String, int> tableCounts;

  /// 各表因結構層孤兒防護而略過的筆數(只有 template_exercises /
  /// workout_exercises / workout_sets 會有非零值)。
  final Map<String, int> skippedCounts;

  /// 各表因對映到既有資料(目前只有 exercises 的系統動作對映到既有種子)
  /// 而不重複 insert 的筆數。
  final Map<String, int> dedupedCounts;

  /// 各表因舊資料 FK 對不上任何已知列而惰性補建的佔位列筆數(只有 users /
  /// exercises 會有非零值)。這些筆數已經計入 [tableCounts],這裡只是拆出
  /// 「有多少是額外新增,不對應任何舊庫來源列」。
  final Map<String, int> createdPlaceholders;

  final List<String> warnings;

  /// true 代表本次結果就是因為 [kCoreDataImportFailedPermanentlyKey] 已設置
  /// (或本次呼叫剛好跨過重試上限)而直接 skip 或失敗。呼叫端不需要另外讀
  /// prefs 判斷是否已達上限。
  final bool permanentlyFailed;

  /// [skipped] 為 true 時的具體原因;[skipped] 為 false 時一律是 null。
  final ImportSkipReason? skipReason;

  @override
  String toString() =>
      'ImportResult(success: $success, skipped: $skipped, '
      'errorMessage: $errorMessage, tableCounts: $tableCounts, '
      'skippedCounts: $skippedCounts, dedupedCounts: $dedupedCounts, '
      'createdPlaceholders: $createdPlaceholders, warnings: $warnings, '
      'permanentlyFailed: $permanentlyFailed, skipReason: $skipReason)';
}
