// 舊 CoreData(WorkoutRecord.sqlite)→ Drift 無縫匯入。native(io)平台實作
// (Android/iOS/桌面)——web 平台走 coredata_importer_web.dart 的 no-op stub,
// 兩邊由 coredata_importer.dart 做 conditional export(dart.library.js_interop
// 命中時切到 web stub,否則預設用本檔),
// 對外都是同一個 `CoreDataImporter` / `ImportResult`(見 coredata_importer_result.dart)。
//
// 規格見 docs/COREDATA_MIGRATION_SPEC.md,實測結果見該文件附錄 B
// (app/test/fixtures/schema_dump.sql 為最終依據)。
//
// 設計摘要:
// - 用 SharedPreferences 旗標防重跑。
// - 不用 Platform.isIOS 特判:Android/全新安裝天然沒有 WorkoutRecord.sqlite,
//   同一套「檔案是否存在」判斷會自動短路跳過(見 spec 第 1.2 / 4.7 節的
//   理由——這也讓整支匯入邏輯可以直接在任何 host 上用 flutter test 驗證,
//   不必假裝自己在 iOS 上執行)。
// - 找不到舊檔(全新安裝 / Android / 舊 App 從未初始化過)→ 直接標記完成,
//   不算錯誤。
// - 找到舊檔:複製到暫存目錄後用 sqlite3 唯讀開啟(不動原始檔案),
//   11 張表依父子順序轉換後寫入 Drift,全程包一個 transaction —— 任何一步
//   失敗就整個 rollback、不寫入完成旗標,下次啟動會自動重試(天然幂等)。
// - 系統動作(isSystem = true)用「名稱 + categoryId」對映到 seedIfEmpty()
//   已建立的內建動作,重複的不再插入,只記住 id 對映;自訂動作照原樣搬。
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show GeneratedColumn, Table, TableInfo, Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

import '../db/app_database.dart';
import 'coredata_importer_result.dart';
import 'import_log.dart';

export 'coredata_importer_result.dart';

const _oldDbFileName = 'WorkoutRecord.sqlite';
const _coreDataEpochOffsetSeconds = 978307200;

/// spec 4.6 節「建議設一個重試上限(例如連續失敗 3 次)」——連續失敗達此
/// 次數後標記 [kCoreDataImportFailedPermanentlyKey],改為需要使用者手動
/// 重試(見 app/lib/features/settings/widgets/import_retry_tile.dart)。
const _maxConsecutiveFailures = 3;

/// 佔位動作用的 categoryId——Exercises.categoryId 沒有 FK 約束(tables.dart),
/// 全 0 UUID 代表「未分類佔位」,不會撞到任何真實分類。
const _placeholderCategoryId = '00000000-0000-0000-0000-000000000000';

class CoreDataImporter {
  /// [supportDirectoryProvider] / [temporaryDirectoryProvider] 預設就是
  /// path_provider 的真正實作;測試時可以換成回傳臨時目錄的函式,不需要動
  /// [importIfNeeded] 本身的簽章,也不需要 mock 任何 platform channel。
  const CoreDataImporter({
    Future<Directory> Function() supportDirectoryProvider =
        getApplicationSupportDirectory,
    Future<Directory> Function() temporaryDirectoryProvider =
        getTemporaryDirectory,
  }) : _supportDirectoryProvider = supportDirectoryProvider,
       _temporaryDirectoryProvider = temporaryDirectoryProvider;

  final Future<Directory> Function() _supportDirectoryProvider;
  final Future<Directory> Function() _temporaryDirectoryProvider;

  Future<ImportResult> importIfNeeded(AppDatabase db) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kCoreDataImportCompletedKey) ?? false) {
      return const ImportResult.skippedAlreadyCompleted();
    }
    if (prefs.getBool(kCoreDataImportFailedPermanentlyKey) ?? false) {
      return const ImportResult.skippedPermanentlyFailed();
    }

    final log = ImportLog(supportDirectoryProvider: _supportDirectoryProvider);
    final currentStep = _CurrentStepHolder();
    File? copiedDbFile;
    try {
      currentStep.value = '取得 support 目錄';
      final supportDir = await _supportDirectoryProvider();
      final oldDbFile = File(p.join(supportDir.path, _oldDbFileName));

      currentStep.value = '檢查舊檔是否存在';
      if (!oldDbFile.existsSync()) {
        await prefs.setBool(kCoreDataImportCompletedKey, true);
        return const ImportResult.skippedNoOldDb();
      }

      currentStep.value = '複製舊檔到暫存目錄';
      copiedDbFile = await _copyToTemp(supportDir);
      final result = await _importFromFile(
        db,
        copiedDbFile,
        prefs,
        currentStep,
      );
      if (result.success) {
        await prefs.setBool(kCoreDataImportCompletedKey, true);
        await prefs.setInt(kCoreDataImportAttemptsKey, 0);
        // 核帳快照:不管是正常匯入成功、還是 alreadyLanded 命中,收工那一刻
        // Drift 各表實際有幾筆都要留痕——alreadyLanded 命中時沒有
        // tableCounts 可存,這份快照補上那個缺口;exercises 這種混了既有
        // 種子的表,也不需要另外記一份 seed 基準線才能核帳(見
        // kCoreDataImportVerifiedCountsKey 的類別文件)。
        final verifiedCounts = await _verifiedTableCounts(db);
        await prefs.setString(
          kCoreDataImportVerifiedCountsKey,
          jsonEncode(verifiedCounts),
        );
        if (result.skipped) {
          // 「已 commit 未標旗」窗口命中(見 _detectAlreadyLanded):資料
          // 已經在,這裡只是補寫旗標,沒有新的落地統計數字可存。順手把
          // 舊庫(CoreData)各表 COUNT(*) 也記進 log——跟上面 Drift 側的
          // verifiedCounts 對照,才看得出「舊庫原本有多少 vs Drift 現在有
          // 多少」,而不是只知道「有命中 alreadyLanded」這個布林結果,供
          // 日後診斷這類窗口時比對(見 [ImportResult.oldDbTableCounts])。
          await log.append(
            '偵測到資料已落地但完成旗標未設置(spec 4.6 節),已補寫完成旗標,'
            '不重新跑一次匯入。核帳快照(各表現有筆數):$verifiedCounts,'
            '舊庫(CoreData)各表 COUNT(*):${result.oldDbTableCounts}',
          );
        } else {
          await prefs.setString(
            kCoreDataImportTableCountsKey,
            jsonEncode(result.tableCounts),
          );
          await prefs.setString(
            kCoreDataImportSkippedCountsKey,
            jsonEncode(result.skippedCounts),
          );
          await prefs.setString(
            kCoreDataImportDedupedCountsKey,
            jsonEncode(result.dedupedCounts),
          );
          await prefs.setString(
            kCoreDataImportCreatedPlaceholdersKey,
            jsonEncode(result.createdPlaceholders),
          );
          await log.append(
            '匯入成功:tableCounts=${result.tableCounts}, '
            'skippedCounts=${result.skippedCounts}, '
            'dedupedCounts=${result.dedupedCounts}, '
            'createdPlaceholders=${result.createdPlaceholders}, '
            'warnings=${result.warnings.length} 則, '
            '核帳快照(各表現有筆數):$verifiedCounts',
          );
        }
      }
      return result;
    } catch (e, st) {
      // 任何未預期例外(檔案損毀、schema 不符、support 目錄取不到...)→
      // 不寫入完成旗標,下次啟動會重新偵測到「舊檔存在 + 完成旗標未設置」,
      // 自動重試,直到連續失敗達 _maxConsecutiveFailures 次為止
      // (spec 4.6 節)。
      final attempts = (prefs.getInt(kCoreDataImportAttemptsKey) ?? 0) + 1;
      await prefs.setInt(kCoreDataImportAttemptsKey, attempts);
      await log.append(
        '匯入失敗(連續第 $attempts 次,進行到:${currentStep.value ?? '未知階段'}):'
        '${truncateForImportLog('$e\n$st')}',
      );

      // 本次呼叫剛好跨過上限時也算 permanentlyFailed——呼叫端(見
      // ImportRetryTile)不需要另外讀 prefs 才知道已經到頂。
      final justPermanentlyFailed = attempts >= _maxConsecutiveFailures;
      if (justPermanentlyFailed) {
        await prefs.setBool(kCoreDataImportFailedPermanentlyKey, true);
        await log.append(
          '連續失敗達 $_maxConsecutiveFailures 次上限,已標記 '
          '$kCoreDataImportFailedPermanentlyKey = true,改為需手動重試。',
        );
      }

      return ImportResult(
        success: false,
        skipped: false,
        errorMessage: '$e\n$st',
        permanentlyFailed: justPermanentlyFailed,
      );
    } finally {
      if (copiedDbFile != null) {
        await _safeDelete(copiedDbFile);
        await _safeDelete(File('${copiedDbFile.path}-wal'));
        await _safeDelete(File('${copiedDbFile.path}-shm'));
      }
    }
  }

  /// spec 4.6 節「連續失敗達重試上限後,提供一個手動重試按鈕」的實際重試
  /// 邏輯——原本散落在 ImportRetryTile 裡(widget 自己操作 prefs key),
  /// 收進這裡讓 widget 只需要呼叫一個方法,也讓這段狀態機邏輯可以直接被
  /// 單元測試覆蓋。
  ///
  /// 這是 one-shot 重試,不是把使用者導回自動重試佇列:清掉
  /// [kCoreDataImportFailedPermanentlyKey] 與 [kCoreDataImportAttemptsKey]
  /// 後跑一次 [importIfNeeded]。若這一次仍然失敗——**或 [importIfNeeded]
  /// 本身丟出未預期例外**(理論上它自己會 catch 住大部分狀況,但防禦性地
  /// 假設呼叫端不該永遠信任這一點)——**立刻**把旗標與計數復原成「已達
  /// 上限」的狀態(而不是讓它停在「已清掉」,也不是讓它從 1 次重新累積到
  /// [_maxConsecutiveFailures] 次)——否則使用者得再連續失敗好幾次才會又
  /// 看到手動重試按鈕,等於這次點擊的重試意圖平白被吃掉,甚至讓 App 卡在
  /// 「兩個旗標都沒設、又不會自動重試」的無人之地。用 try/finally 而不是
  /// 只在失敗分支手動寫回,就是為了讓例外路徑也一定會復原。回傳的
  /// [ImportResult.permanentlyFailed] 因此在失敗時一定是 true,呼叫端不需要
  /// 另外讀 prefs 判斷。
  Future<ImportResult> retryAfterPermanentFailure(AppDatabase db) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kCoreDataImportFailedPermanentlyKey, false);
    await prefs.setInt(kCoreDataImportAttemptsKey, 0);

    var recovered = false;
    try {
      final result = await importIfNeeded(db);
      if (result.success || result.skipped) {
        recovered = true;
        return result;
      }
      return ImportResult(
        success: false,
        skipped: false,
        errorMessage: result.errorMessage,
        tableCounts: result.tableCounts,
        skippedCounts: result.skippedCounts,
        dedupedCounts: result.dedupedCounts,
        createdPlaceholders: result.createdPlaceholders,
        warnings: result.warnings,
        permanentlyFailed: true,
        oldDbTableCounts: result.oldDbTableCounts,
      );
    } finally {
      if (!recovered) {
        await prefs.setBool(kCoreDataImportFailedPermanentlyKey, true);
        await prefs.setInt(kCoreDataImportAttemptsKey, _maxConsecutiveFailures);
      }
    }
  }

  Future<File> _copyToTemp(Directory supportDir) async {
    final tempDir = await _temporaryDirectoryProvider();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final targetPath = p.join(tempDir.path, 'coredata_import_$stamp.sqlite');

    final mainFile = File(p.join(supportDir.path, _oldDbFileName));
    final walFile = File(p.join(supportDir.path, '$_oldDbFileName-wal'));
    final shmFile = File(p.join(supportDir.path, '$_oldDbFileName-shm'));

    final copied = await mainFile.copy(targetPath);
    if (walFile.existsSync()) {
      await walFile.copy('$targetPath-wal');
    }
    if (shmFile.existsSync()) {
      await shmFile.copy('$targetPath-shm');
    }
    return copied;
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {
      // 清理暫存副本失敗不影響匯入結果本身,忽略即可。
    }
  }

  /// 用真正的匯入邏輯跑一次,回傳結果。丟出的例外由呼叫端 catch 並轉成
  /// 失敗的 [ImportResult](不寫完成旗標,下次重試)。
  ///
  /// 成功時額外把這次匯入實際落地的主要使用者 id 寫進
  /// [kCoreDataImportedUserIdKey](血緣誤判修正,見 review 2026-07-30)——
  /// 取 [_importUsers] 回傳的 userIds(已含 [_resolveUserId] 惰性補建的佔位
  /// 使用者)的第一筆,單一使用者 App 下就是唯一或最先讀到的那筆。
  Future<ImportResult> _importFromFile(
    AppDatabase db,
    File dbFile,
    SharedPreferences prefs,
    _CurrentStepHolder currentStep,
  ) async {
    final oldDb = sqlite3lib.sqlite3.open(
      dbFile.path,
      mode: sqlite3lib.OpenMode.readOnly,
    );
    try {
      currentStep.value = '偵測「已 commit 未標旗」窗口';
      if (await _detectAlreadyLanded(db, oldDb)) {
        // 順手記錄舊庫(CoreData)各表 COUNT(*)——alreadyLanded 命中時沒有
        // 本次的 tableCounts 可存,這份舊庫側快照補上「命中當下舊庫原本
        // 有多少」的數字,供核帳與日後診斷這類窗口時比對(見
        // [ImportResult.oldDbTableCounts] 的類別文件)。
        return ImportResult(
          success: true,
          skipped: true,
          skipReason: ImportSkipReason.alreadyLanded,
          oldDbTableCounts: _oldDbTableCounts(oldDb),
        );
      }

      // 匯入過程中累積的各項統計數字,收攏成一個 tally 物件一次傳遞——
      // 取代原本 warnings / createdPlaceholders 這兩個可變狀態各自當參數
      // 傳給每個 _import* helper 的長參數列(行為不變,純粹減少參數數量)。
      final tally = _ImportTally();
      var userIds = <String>{};

      await db.transaction(() async {
        currentStep.value = 'users';
        final usersImport = await _importUsers(db, oldDb);
        // tally.counts['users'] 在 transaction 收尾統一定案(落地 + 佔位);
        // userIds 提升到 transaction 外,結束後寫血緣 key 用。
        userIds = usersImport.ids;

        currentStep.value = 'exercises';
        final exercisesImport = await _importExercises(
          db,
          oldDb,
          userIds,
          tally,
        );
        tally.dedupedCounts['exercises'] = exercisesImport.dedupedCount;
        final exerciseIdMap = exercisesImport.idMap;
        // 名稱 → 補建的佔位動作 id,讓不同的舊 exerciseId 若解析到同一個
        // 名稱時共用同一筆佔位動作,不會重複補建(見 _resolveOrCreatePlaceholderExercise)。
        final placeholderExerciseIdsByName = <String, String>{};

        currentStep.value = 'templates';
        final templatesImport = await _importTemplates(
          db,
          oldDb,
          userIds,
          tally,
        );
        tally.counts['templates'] = templatesImport.sourceCount;

        currentStep.value = 'template_exercises';
        final templateExercisesImport = await _importTemplateExercises(
          db,
          oldDb,
          exerciseIdMap,
          templatesImport.ids,
          tally,
        );
        tally.counts['template_exercises'] =
            templateExercisesImport.landedCount;
        tally.skippedCounts['template_exercises'] =
            templateExercisesImport.skippedCount;

        currentStep.value = 'workouts';
        final workoutsImport = await _importWorkouts(db, oldDb, userIds, tally);
        tally.counts['workouts'] = workoutsImport.sourceCount;

        currentStep.value = 'workout_exercises';
        final workoutExercisesImport = await _importWorkoutExercises(
          db,
          oldDb,
          exerciseIdMap,
          workoutsImport.ids,
          placeholderExerciseIdsByName,
          tally,
        );
        tally.counts['workout_exercises'] = workoutExercisesImport.landedCount;
        tally.skippedCounts['workout_exercises'] =
            workoutExercisesImport.skippedCount;

        currentStep.value = 'workout_sets';
        final workoutSetsImport = await _importWorkoutSets(
          db,
          oldDb,
          workoutExercisesImport.ids,
          tally,
        );
        tally.counts['workout_sets'] = workoutSetsImport.landedCount;
        tally.skippedCounts['workout_sets'] = workoutSetsImport.skippedCount;

        currentStep.value = 'body_weights';
        tally.counts['body_weights'] = await _importBodyWeights(
          db,
          oldDb,
          userIds,
          tally,
        );

        currentStep.value = 'personal_records';
        tally.counts['personal_records'] = await _importPersonalRecords(
          db,
          oldDb,
          exerciseIdMap,
          placeholderExerciseIdsByName,
          userIds,
          tally,
        );

        currentStep.value = 'user_goals';
        tally.counts['user_goals'] = await _importUserGoals(
          db,
          oldDb,
          userIds,
          tally,
        );

        currentStep.value = 'power_lift_records';
        tally.counts['power_lift_records'] = await _importPowerLiftRecords(
          db,
          oldDb,
          userIds,
          tally,
        );

        // users / exercises 的落地量必須等所有子表都跑完才能定案——佔位
        // 使用者 / 佔位動作是在子表匯入過程中才可能惰性補建的(見
        // ImportResult 類別文件的帳式說明)。
        tally.counts['users'] =
            usersImport.sourceCount + (tally.createdPlaceholders['users'] ?? 0);
        tally.counts['exercises'] =
            exercisesImport.landedCount +
            (tally.createdPlaceholders['exercises'] ?? 0);
      });

      if (userIds.isNotEmpty) {
        await prefs.setString(kCoreDataImportedUserIdKey, userIds.first);
      }

      return ImportResult(
        success: true,
        skipped: false,
        tableCounts: tally.counts,
        skippedCounts: tally.skippedCounts,
        dedupedCounts: tally.dedupedCounts,
        createdPlaceholders: tally.createdPlaceholders,
        warnings: tally.warnings,
      );
    } finally {
      oldDb.dispose();
    }
  }

  /// spec 4.6 節「已 commit 未標旗」窗口:匯入的 transaction 已成功寫入
  /// Drift,但寫入完成旗標前 App 被中斷(崩潰 / 被系統砍掉),導致下次啟動
  /// 誤判成尚未匯入,重跑會撞主鍵。用抽樣舊庫 id、查 Drift 是否已存在同一批
  /// id 的方式偵測——任一樣本命中就代表資料已經在,只是旗標沒寫。
  ///
  /// 抽樣範圍:所有「原樣保留舊庫 id」的表——workouts、users、自訂動作
  /// (isSystem = false)、templates、body_weights、personal_records、
  /// user_goals、power_lift_records。每張表最多抽 3 筆 id(LIMIT 3),逐表
  /// 檢查,只要有任何一筆命中 Drift 就視為已落地;不像舊版「第一張非空表
  /// 沒中就直接判定未匯入」——那樣只要抽樣到的那 1 筆剛好被使用者事後刪掉,
  /// 就會誤判成未匯入,重跑撞上其餘資料的主鍵。要**全部**表的**全部**樣本
  /// 都沒命中,才會判定為未匯入。
  ///
  /// **刻意不抽系統動作**:系統動作本來就會對映到既有種子(見
  /// [_importExercises]),Drift 有那筆資料是完全正常的現象,不代表曾經
  /// 匯入過,拿它當判準會產生大量偽陽性。也**刻意不用「Drift 有任何資料」
  /// 當判準**:使用者可能在匯入失敗後就已經開始用 App 記錄新訓練,那些新
  /// 資料跟舊庫毫無關係,誤判成「已匯入」會導致舊資料永久匯不進來。
  ///
  /// **殘餘窗口**:多表多樣本已經把誤判機率壓得很低,但不是零——理論上
  /// 若使用者精準刪光「每一張抽樣表裡剛好被抽中的那 1~3 筆」(其餘資料仍
  /// 保留),就還是會誤判成未匯入而重跑一次。這是抽樣型偵測的天生限制,
  /// 發生機率極低,不追求用全表掃描把它壓到 0(那會讓每次啟動都多付出
  /// 一次全表比對的成本)。
  Future<bool> _detectAlreadyLanded(
    AppDatabase db,
    sqlite3lib.Database oldDb,
  ) async {
    if (await _anySampleExists(
      db,
      db.workouts,
      (t) => t.id,
      _sampleOldIds(oldDb, 'ZWORKOUTENTITY'),
    )) {
      return true;
    }
    if (await _anySampleExists(
      db,
      db.users,
      (t) => t.id,
      _sampleOldIds(oldDb, 'ZUSERENTITY'),
    )) {
      return true;
    }
    if (await _anySampleExists(
      db,
      db.exercises,
      (t) => t.id,
      _sampleOldCustomExerciseIds(oldDb),
    )) {
      return true;
    }
    if (await _anySampleExists(
      db,
      db.templates,
      (t) => t.id,
      _sampleOldIds(oldDb, 'ZTEMPLATEENTITY'),
    )) {
      return true;
    }
    if (await _anySampleExists(
      db,
      db.bodyWeights,
      (t) => t.id,
      _sampleOldIds(oldDb, 'ZBODYWEIGHTENTITY'),
    )) {
      return true;
    }
    if (await _anySampleExists(
      db,
      db.personalRecords,
      (t) => t.id,
      _sampleOldIds(oldDb, 'ZPERSONALRECORDENTITY'),
    )) {
      return true;
    }
    if (await _anySampleExists(
      db,
      db.userGoals,
      (t) => t.id,
      _sampleOldIds(oldDb, 'ZUSERGOALENTITY'),
    )) {
      return true;
    }
    if (await _anySampleExists(
      db,
      db.powerLiftRecords,
      (t) => t.id,
      _sampleOldIds(oldDb, 'ZPOWERLIFTRECORDENTITY'),
    )) {
      return true;
    }

    // 所有抽樣表都是空的,或抽到的樣本 Drift 裡都沒有,沒有更多樣本可查,
    // 視為未偵測到,照常往下跑正常匯入流程。
    return false;
  }

  /// [_detectAlreadyLanded] 的共用檢查邏輯:[candidateIds] 任一筆存在於
  /// [table] 就回傳 true。抽出成獨立方法而不是在呼叫端各自組 query——8 張
  /// 表的檢查邏輯完全一樣,只有表跟 id 欄位不同。
  Future<bool> _anySampleExists<Tbl extends Table, Row>(
    AppDatabase db,
    TableInfo<Tbl, Row> table,
    GeneratedColumn<String> Function(Tbl) idColumn,
    List<String> candidateIds,
  ) async {
    if (candidateIds.isEmpty) return false;
    final rows = await (db.select(
      table,
    )..where((t) => idColumn(t).isIn(candidateIds))).get();
    return rows.isNotEmpty;
  }

  /// 抽樣舊庫某張表最多 3 筆 id(見 [_detectAlreadyLanded] 的抽樣策略說明)。
  List<String> _sampleOldIds(sqlite3lib.Database oldDb, String table) {
    final rows = oldDb.select('SELECT ZID FROM $table LIMIT 3');
    return [for (final row in rows) _uuidFromBlob(row['ZID'])];
  }

  /// 自訂動作(isSystem = false)專用抽樣——`ZISSYSTEM` 用 `COALESCE(...,0)`
  /// 修正 NULL 語意(CoreData 的 optional Bool 屬性沒賦值時欄位本身可能是
  /// NULL,不是 0,`ZISSYSTEM = 0` 會漏掉這種列)。
  List<String> _sampleOldCustomExerciseIds(sqlite3lib.Database oldDb) {
    final rows = oldDb.select(
      'SELECT ZID FROM ZEXERCISEENTITY WHERE COALESCE(ZISSYSTEM, 0) = 0 LIMIT 3',
    );
    return [for (final row in rows) _uuidFromBlob(row['ZID'])];
  }

  /// 匯入收工那一刻(成功匯入或 alreadyLanded 命中)對 Drift **每一張**表各下
  /// 一次真正的 `SELECT COUNT(*)` 的核帳快照(見 [kCoreDataImportVerifiedCountsKey]
  /// 的類別文件)。
  ///
  /// 用 [AppDatabase.allTables] 逐表遍歷,而不是手列 11 張表名——手列清單
  /// 在日後新增表時容易漏掉,變成核帳的盲區;`allTables` 由 `@DriftDatabase`
  /// 的 `tables:` 清單生成,新表天然涵蓋在內,不需要這裡同步維護第二份
  /// 清單。用 `customSelect` 下真正的 `COUNT(*)` 聚合查詢,而不是
  /// `db.select(table).get()` 再取 `.length`——後者要把整張表的每一列都
  /// 讀進記憶體才能算出筆數,對核帳快照這種「只要一個數字」的用途是不必要
  /// 的開銷。
  Future<Map<String, int>> _verifiedTableCounts(AppDatabase db) async {
    final counts = <String, int>{};
    for (final table in db.allTables) {
      final row = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM "${table.actualTableName}"',
            readsFrom: {table},
          )
          .getSingle();
      counts[table.actualTableName] = row.read<int>('c');
    }
    return counts;
  }

  /// [_detectAlreadyLanded] 命中時,順手記錄舊庫(CoreData SQLite)11 張表
  /// 各自的 `SELECT COUNT(*)`——跟 [_verifiedTableCounts] 的 Drift 側數字
  /// 對照,才看得出「舊庫原本有多少 vs Drift 現在有多少」,不是只知道
  /// 「有命中 alreadyLanded」這個布林結果,供日後診斷這類窗口時比對(見
  /// [ImportResult.oldDbTableCounts] 的類別文件)。表名與
  /// [kCoreDataImportVerifiedCountsKey] 快照的 key 一一對應,方便兩邊直接
  /// 逐 key 比對。
  Map<String, int> _oldDbTableCounts(sqlite3lib.Database oldDb) {
    int count(String table) =>
        oldDb.select('SELECT COUNT(*) AS c FROM $table').first['c'] as int;

    return {
      'users': count('ZUSERENTITY'),
      'exercises': count('ZEXERCISEENTITY'),
      'templates': count('ZTEMPLATEENTITY'),
      'template_exercises': count('ZTEMPLATEEXERCISEENTITY'),
      'workouts': count('ZWORKOUTENTITY'),
      'workout_exercises': count('ZWORKOUTEXERCISEENTITY'),
      'workout_sets': count('ZWORKOUTSETENTITY'),
      'body_weights': count('ZBODYWEIGHTENTITY'),
      'personal_records': count('ZPERSONALRECORDENTITY'),
      'user_goals': count('ZUSERGOALENTITY'),
      'power_lift_records': count('ZPOWERLIFTRECORDENTITY'),
    };
  }

  Future<({int sourceCount, Set<String> ids})> _importUsers(
    AppDatabase db,
    sqlite3lib.Database oldDb,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZUSERENTITY');
    final ids = <String>{};
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: id,
              name: Value(row['ZNAME'] as String?),
              email: Value(row['ZEMAIL'] as String?),
              createdAt: _dateFromCoreData(row['ZCREATEDAT']),
              updatedAt: _dateFromCoreData(row['ZUPDATEDAT']),
            ),
          );
      ids.add(id);
    }
    return (sourceCount: rows.length, ids: ids);
  }

  /// 這是單一使用者的本機 App(spec 第 0 節):理論上只有一筆 `UserEntity`。
  /// CoreData 用「裸 UUID 屬性」(`userId`)和正規 relationship 雙軌並存,
  /// 兩者沒有資料庫層級約束保證一致(spec 附錄 3),實測 fixture 也證實了
  /// 這個風險——某些子表的 `userId` 屬性跟目前僅有的 `UserEntity.id` 對不
  /// 起來。Drift 端的 userId 是有 FK 約束的必填欄位,若照抄舊值會讓整個
  /// transaction 因 FK 違規而 rollback,等於因為一筆資料的裸 UUID 髒資料
  /// 賠上全部訓練歷史。既然是單一使用者 App,對不上時安全地 fallback 回
  /// 唯一已匯入的使用者 id,不影響資料本身,只修正它掛在哪個使用者底下。
  ///
  /// `userIds` 為空(舊庫連一筆 `UserEntity` 都沒有,但子表仍有資料)時,
  /// 沒有任何使用者可以 fallback——惰性補建一筆佔位使用者(新 UUID、
  /// name/email 皆為 null)並加入 `userIds`,之後同一輪匯入的呼叫會自然
  /// fallback 到這筆佔位使用者,不會重複補建。`createdPlaceholders['users']`
  /// 因此最多只會被加 1(見 [ImportResult] 類別文件的帳式說明)。
  Future<String> _resolveUserId(
    AppDatabase db,
    String candidateUserId,
    Set<String> userIds,
    String context,
    _ImportTally tally,
  ) async {
    if (userIds.contains(candidateUserId)) {
      return candidateUserId;
    }
    if (userIds.isEmpty) {
      final placeholderId = _generateUuidV4();
      final now = DateTime.now();
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: placeholderId,
              createdAt: now,
              updatedAt: now,
            ),
          );
      userIds.add(placeholderId);
      tally.createdPlaceholders['users'] =
          (tally.createdPlaceholders['users'] ?? 0) + 1;
      tally.warnings.add(
        '$context 的 userId($candidateUserId)未對到任何使用者,'
        '舊庫也沒有任何 UserEntity,已補建佔位使用者($placeholderId)。',
      );
      return placeholderId;
    }
    final fallback = userIds.first;
    tally.warnings.add(
      '$context 的 userId($candidateUserId)未對到已匯入的使用者,'
      '已 fallback 為唯一使用者($fallback)——這是單一使用者 App,'
      '舊資料的裸 UUID 屬性與 relationship 不一定同步(spec 附錄 3),'
      '不影響資料本身。',
    );
    return fallback;
  }

  /// workout_exercises / personal_records 的 exerciseId 對不上任何舊庫
  /// exercise 時,以名稱為 key 惰性補建一個佔位動作(而非略過該列)——因為
  /// 這兩張表底下掛著真實訓練歷史(sets / PR),略過會損失比孤兒本身更多
  /// 的資料。同一個舊 exerciseId 之後再次查到會直接複用 [exerciseIdMap];
  /// 不同的舊 exerciseId 若解析到相同名稱,也共用同一筆佔位動作,不重複
  /// 補建——`createdPlaceholders['exercises']` 因此只在真正新建一筆佔位
  /// 動作時才加 1(見 [ImportResult] 類別文件的帳式說明)。
  Future<String> _resolveOrCreatePlaceholderExercise({
    required AppDatabase db,
    required String oldExerciseId,
    required String? name,
    required String? type,
    required Map<String, String> exerciseIdMap,
    required Map<String, String> placeholderIdsByName,
    required String context,
    required _ImportTally tally,
  }) async {
    final existing = exerciseIdMap[oldExerciseId];
    if (existing != null) {
      return existing;
    }

    final resolvedName = (name == null || name.isEmpty) ? '未知動作' : name;
    final existingPlaceholder = placeholderIdsByName[resolvedName];
    if (existingPlaceholder != null) {
      exerciseIdMap[oldExerciseId] = existingPlaceholder;
      return existingPlaceholder;
    }

    final placeholderId = _generateUuidV4();
    final now = DateTime.now();
    await db
        .into(db.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: placeholderId,
            name: resolvedName,
            categoryId: _placeholderCategoryId,
            type: type ?? 'strength',
            isSystem: const Value(false),
            isActive: const Value(true),
            userId: const Value(null),
            createdAt: now,
            updatedAt: now,
          ),
        );
    placeholderIdsByName[resolvedName] = placeholderId;
    exerciseIdMap[oldExerciseId] = placeholderId;
    tally.createdPlaceholders['exercises'] =
        (tally.createdPlaceholders['exercises'] ?? 0) + 1;
    tally.warnings.add(
      '$context 的 exerciseId($oldExerciseId)未對到任何動作,'
      '已補建佔位動作「$resolvedName」($placeholderId)。',
    );
    return placeholderId;
  }

  /// 系統動作(isSystem = true)以「名稱 + categoryId」對映到 seedIfEmpty()
  /// 已建立的內建動作(重複的不插入,只記住 id 對映,計入 [dedupedCount]);
  /// 自訂動作(isSystem = false)照原樣搬,保留原 UUID。回傳:舊 id(小寫
  /// UUID 字串)→ 新 id 的對映表(給 TemplateExercises / WorkoutExercises /
  /// PersonalRecords 的 exerciseId 用)、讀到的舊資料筆數([sourceCount])、
  /// 實際 insert 的筆數([landedCount])與去重筆數([dedupedCount])——
  /// `sourceCount == landedCount + dedupedCount` 恆成立,用於驗證帳式沒有
  /// 算錯(見 [ImportResult] 類別文件)。
  Future<
    ({
      Map<String, String> idMap,
      int sourceCount,
      int landedCount,
      int dedupedCount,
    })
  >
  _importExercises(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Set<String> userIds,
    _ImportTally tally,
  ) async {
    final existingSystemExercises = await (db.select(
      db.exercises,
    )..where((t) => t.isSystem.equals(true))).get();
    final seedByNameAndCategory = <String, String>{
      for (final e in existingSystemExercises)
        '${e.name}\u0000${e.categoryId}': e.id,
    };

    final rows = oldDb.select('SELECT * FROM ZEXERCISEENTITY');
    final idMap = <String, String>{};
    var dedupedCount = 0;

    for (final row in rows) {
      final oldId = _uuidFromBlob(row['ZID']);
      final name = row['ZNAME'] as String;
      final categoryId = _uuidFromBlob(row['ZCATEGORYID']);
      final isSystem = _boolFromInt(row['ZISSYSTEM']);

      if (isSystem) {
        final match = seedByNameAndCategory['$name\u0000$categoryId'];
        if (match != null) {
          idMap[oldId] = match;
          dedupedCount++;
          continue;
        }
        tally.warnings.add('系統動作「$name」(舊 id $oldId)未能與內建種子對映,已改為原樣匯入。');
      }

      final rawUserId = _uuidFromBlobOrNull(row['ZUSERID']);
      final resolvedUserId = rawUserId == null
          ? null
          : await _resolveUserId(db, rawUserId, userIds, '自訂動作「$name」', tally);
      await db
          .into(db.exercises)
          .insert(
            ExercisesCompanion.insert(
              id: oldId,
              name: name,
              nameEn: Value(row['ZNAMEEN'] as String?),
              categoryId: categoryId,
              type: row['ZTYPE'] as String,
              movementPattern: Value(row['ZMOVEMENTPATTERN'] as String?),
              primaryMuscleGroup: Value(row['ZPRIMARYMUSCLEGROUP'] as String?),
              descriptionText: Value(row['ZDESCRIPTIONTEXT'] as String?),
              videoURL: Value(row['ZVIDEOURL'] as String?),
              imageURL: Value(row['ZIMAGEURL'] as String?),
              isSystem: Value(isSystem),
              isActive: Value(_boolFromInt(row['ZISACTIVE'])),
              userId: Value(resolvedUserId),
              createdAt: _dateFromCoreData(row['ZCREATEDAT']),
              updatedAt: _dateFromCoreData(row['ZUPDATEDAT']),
            ),
          );
      idMap[oldId] = oldId;
    }

    return (
      idMap: idMap,
      sourceCount: rows.length,
      landedCount: rows.length - dedupedCount,
      dedupedCount: dedupedCount,
    );
  }

  Future<({int sourceCount, Set<String> ids})> _importTemplates(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Set<String> userIds,
    _ImportTally tally,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZTEMPLATEENTITY');
    final ids = <String>{};
    for (final row in rows) {
      final name = row['ZNAME'] as String;
      final id = _uuidFromBlob(row['ZID']);
      await db
          .into(db.templates)
          .insert(
            TemplatesCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                '模板「$name」',
                tally,
              ),
              name: name,
              descriptionText: Value(row['ZDESCRIPTIONTEXT'] as String?),
              isSystem: Value(_boolFromInt(row['ZISSYSTEM'])),
              createdAt: _dateFromCoreData(row['ZCREATEDAT']),
              updatedAt: _dateFromCoreData(row['ZUPDATEDAT']),
            ),
          );
      ids.add(id);
    }
    return (sourceCount: rows.length, ids: ids);
  }

  /// 排序以 ZORDERINDEX 為準(Z_FOK_TEMPLATE 只是備援,業務欄位本來就存在,
  /// 比依賴 CoreData 內部排序欄位可靠,見 spec 第 2.5 節)。
  ///
  /// 結構層孤兒防護:`templateId` 未對到已匯入的模板、或 `exerciseId` 未對
  /// 到任何動作 → 略過該列 + warning(模板項本身沒有動作身分即無意義,且
  /// 它不是訓練歷史,略過只損失該筆,不賠整批 transaction)。
  Future<({int sourceCount, int landedCount, int skippedCount})>
  _importTemplateExercises(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Map<String, String> exerciseIdMap,
    Set<String> templateIds,
    _ImportTally tally,
  ) async {
    final rows = oldDb.select(
      'SELECT * FROM ZTEMPLATEEXERCISEENTITY ORDER BY ZTEMPLATE, ZORDERINDEX',
    );
    var skipped = 0;
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      final templateId = _uuidFromBlob(row['ZTEMPLATEID']);
      if (!templateIds.contains(templateId)) {
        tally.warnings.add(
          '[template_exercises] 模板動作($id)的 templateId($templateId)'
          '未對到任何已匯入的模板,已略過。',
        );
        skipped++;
        continue;
      }

      final oldExerciseId = _uuidFromBlob(row['ZEXERCISEID']);
      final newExerciseId = exerciseIdMap[oldExerciseId];
      if (newExerciseId == null) {
        tally.warnings.add(
          '[template_exercises] 模板動作($id)的 exerciseId($oldExerciseId)'
          '未對到任何動作,已略過。',
        );
        skipped++;
        continue;
      }

      await db
          .into(db.templateExercises)
          .insert(
            TemplateExercisesCompanion.insert(
              id: id,
              templateId: templateId,
              exerciseId: newExerciseId,
              orderIndex: Value((row['ZORDERINDEX'] as int?) ?? 0),
              suggestedSets: Value(row['ZSUGGESTEDSETS'] as int?),
              suggestedReps: Value(row['ZSUGGESTEDREPS'] as int?),
            ),
          );
    }
    return (
      sourceCount: rows.length,
      landedCount: rows.length - skipped,
      skippedCount: skipped,
    );
  }

  Future<({int sourceCount, Set<String> ids})> _importWorkouts(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Set<String> userIds,
    _ImportTally tally,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZWORKOUTENTITY');
    final ids = <String>{};
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      await db
          .into(db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                '訓練($id)',
                tally,
              ),
              startedAt: _dateFromCoreData(row['ZSTARTEDAT']),
              endedAt: Value(_dateFromCoreDataOrNull(row['ZENDEDAT'])),
              duration: Value(row['ZDURATION'] as int?),
              totalVolume: Value(_doubleOrZero(row['ZTOTALVOLUME'])),
              totalSets: Value((row['ZTOTALSETS'] as int?) ?? 0),
              totalExercises: Value((row['ZTOTALEXERCISES'] as int?) ?? 0),
              note: Value(row['ZNOTE'] as String?),
              templateId: Value(_uuidFromBlobOrNull(row['ZTEMPLATEID'])),
              isSynced: Value(_boolFromInt(row['ZISSYNCED'])),
              createdAt: _dateFromCoreData(row['ZCREATEDAT']),
              updatedAt: _dateFromCoreData(row['ZUPDATEDAT']),
            ),
          );
      ids.add(id);
    }
    return (sourceCount: rows.length, ids: ids);
  }

  /// 結構層孤兒防護:`workoutId` 未對到已匯入的訓練 → 略過該列 + warning
  /// (該列連同底下的 sets 都無法歸屬到任何訓練,略過只損失該筆孤兒碎片,
  /// 不賠整批 transaction)。`exerciseId` 對不上任何動作則不略過——改為
  /// 補建佔位動作(見 [_resolveOrCreatePlaceholderExercise]),因為這張表
  /// 底下掛著真實訓練歷史(sets)。
  Future<
    ({int sourceCount, int landedCount, int skippedCount, Set<String> ids})
  >
  _importWorkoutExercises(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Map<String, String> exerciseIdMap,
    Set<String> workoutIds,
    Map<String, String> placeholderExerciseIdsByName,
    _ImportTally tally,
  ) async {
    final rows = oldDb.select(
      'SELECT * FROM ZWORKOUTEXERCISEENTITY ORDER BY ZWORKOUT, ZORDERINDEX',
    );
    final ids = <String>{};
    var skipped = 0;
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      final workoutId = _uuidFromBlob(row['ZWORKOUTID']);
      if (!workoutIds.contains(workoutId)) {
        tally.warnings.add(
          '[workout_exercises] 訓練動作($id)的 workoutId($workoutId)'
          '未對到任何已匯入的訓練,已略過。',
        );
        skipped++;
        continue;
      }

      final oldExerciseId = _uuidFromBlob(row['ZEXERCISEID']);
      final exerciseName = row['ZEXERCISENAME'] as String?;
      final resolvedExerciseId = await _resolveOrCreatePlaceholderExercise(
        db: db,
        oldExerciseId: oldExerciseId,
        name: exerciseName,
        type: null,
        exerciseIdMap: exerciseIdMap,
        placeholderIdsByName: placeholderExerciseIdsByName,
        context: '[workout_exercises] 訓練動作($id)',
        tally: tally,
      );

      await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              id: id,
              workoutId: workoutId,
              exerciseId: resolvedExerciseId,
              exerciseName: Value(exerciseName),
              orderIndex: Value((row['ZORDERINDEX'] as int?) ?? 0),
              totalVolume: Value(_doubleOrZero(row['ZTOTALVOLUME'])),
              totalSets: Value((row['ZTOTALSETS'] as int?) ?? 0),
              isCompleted: Value(_boolFromInt(row['ZISCOMPLETED'])),
              isCustomExercise: Value(_boolFromInt(row['ZISCUSTOMEXERCISE'])),
              note: Value(row['ZNOTE'] as String?),
              createdAt: _dateFromCoreData(row['ZCREATEDAT']),
              updatedAt: _dateFromCoreData(row['ZUPDATEDAT']),
            ),
          );
      ids.add(id);
    }
    return (
      sourceCount: rows.length,
      landedCount: rows.length - skipped,
      skippedCount: skipped,
      ids: ids,
    );
  }

  /// rpe / restSeconds:CoreData 的 0 值視為「未填」轉成 Drift 端的 NULL
  /// (見 app/lib/data/db/README.md review 追蹤事項)。
  ///
  /// 結構層孤兒防護:`workoutExerciseId` 未對到已匯入的訓練動作 → 略過該
  /// 列 + warning(略過只損失該筆孤兒碎片,不賠整批 transaction)。
  Future<({int sourceCount, int landedCount, int skippedCount})>
  _importWorkoutSets(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Set<String> workoutExerciseIds,
    _ImportTally tally,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZWORKOUTSETENTITY');
    var skipped = 0;
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      final workoutExerciseId = _uuidFromBlob(row['ZWORKOUTEXERCISEID']);
      if (!workoutExerciseIds.contains(workoutExerciseId)) {
        tally.warnings.add(
          '[workout_sets] 訓練組數($id)的 workoutExerciseId($workoutExerciseId)'
          '未對到任何已匯入的訓練動作,已略過。',
        );
        skipped++;
        continue;
      }

      await db
          .into(db.workoutSets)
          .insert(
            WorkoutSetsCompanion.insert(
              id: id,
              workoutExerciseId: workoutExerciseId,
              setNumber: Value((row['ZSETNUMBER'] as int?) ?? 0),
              weight: Value(_doubleOrZero(row['ZWEIGHT'])),
              reps: Value((row['ZREPS'] as int?) ?? 0),
              volume: Value(_doubleOrZero(row['ZVOLUME'])),
              rpe: Value(_nonZeroDoubleOrNull(row['ZRPE'])),
              restSeconds: Value(_nonZeroIntOrNull(row['ZRESTSECONDS'])),
              isWarmup: Value(_boolFromInt(row['ZISWARMUP'])),
              note: Value(row['ZNOTE'] as String?),
              createdAt: _dateFromCoreData(row['ZCREATEDAT']),
              updatedAt: _dateFromCoreData(row['ZUPDATEDAT']),
            ),
          );
    }
    return (
      sourceCount: rows.length,
      landedCount: rows.length - skipped,
      skippedCount: skipped,
    );
  }

  Future<int> _importBodyWeights(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Set<String> userIds,
    _ImportTally tally,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZBODYWEIGHTENTITY');
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      await db
          .into(db.bodyWeights)
          .insert(
            BodyWeightsCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                '體重紀錄($id)',
                tally,
              ),
              weight: Value(_doubleOrZero(row['ZWEIGHT'])),
              measuredAt: _dateFromCoreData(row['ZMEASUREDAT']),
              note: Value(row['ZNOTE'] as String?),
              isSynced: Value(_boolFromInt(row['ZISSYNCED'])),
              createdAt: _dateFromCoreData(row['ZCREATEDAT']),
              updatedAt: _dateFromCoreData(row['ZUPDATEDAT']),
            ),
          );
    }
    return rows.length;
  }

  /// 結構層孤兒防護:`exerciseId` 對不上任何動作不略過——改為補建佔位動作
  /// (見 [_resolveOrCreatePlaceholderExercise]),因為這張表底下掛著真實
  /// 的個人紀錄(PR)。`workoutId` 是 denormalized 的裸 UUID,tables.dart
  /// 故意不加 FK(舊資料會懸空,見該檔案欄位註解),原樣保留不需處理。
  Future<int> _importPersonalRecords(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Map<String, String> exerciseIdMap,
    Map<String, String> placeholderExerciseIdsByName,
    Set<String> userIds,
    _ImportTally tally,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZPERSONALRECORDENTITY');
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      final oldExerciseId = _uuidFromBlob(row['ZEXERCISEID']);
      final resolvedExerciseId = await _resolveOrCreatePlaceholderExercise(
        db: db,
        oldExerciseId: oldExerciseId,
        name: null,
        type: null,
        exerciseIdMap: exerciseIdMap,
        placeholderIdsByName: placeholderExerciseIdsByName,
        context: '[personal_records] 個人紀錄($id)',
        tally: tally,
      );
      await db
          .into(db.personalRecords)
          .insert(
            PersonalRecordsCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                '個人紀錄($id)',
                tally,
              ),
              exerciseId: resolvedExerciseId,
              oneRepMax: Value(_doubleOrZero(row['ZONEREPMAX'])),
              weight: Value(_doubleOrZero(row['ZWEIGHT'])),
              reps: Value((row['ZREPS'] as int?) ?? 0),
              achievedAt: _dateFromCoreData(row['ZACHIEVEDAT']),
              workoutId: Value(_uuidFromBlobOrNull(row['ZWORKOUTID'])),
              createdAt: _dateFromCoreData(row['ZCREATEDAT']),
              updatedAt: _dateFromCoreData(row['ZUPDATEDAT']),
            ),
          );
    }
    return rows.length;
  }

  Future<int> _importUserGoals(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Set<String> userIds,
    _ImportTally tally,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZUSERGOALENTITY');
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      await db
          .into(db.userGoals)
          .insert(
            UserGoalsCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                '使用者目標($id)',
                tally,
              ),
              targetWeight: Value(_nullableDouble(row['ZTARGETWEIGHT'])),
              weeklyWorkoutGoal: Value(
                (row['ZWEEKLYWORKOUTGOAL'] as int?) ?? 0,
              ),
              chestVolumeGoal: Value(_nullableDouble(row['ZCHESTVOLUMEGOAL'])),
              backVolumeGoal: Value(_nullableDouble(row['ZBACKVOLUMEGOAL'])),
              legsVolumeGoal: Value(_nullableDouble(row['ZLEGSVOLUMEGOAL'])),
              shouldersVolumeGoal: Value(
                _nullableDouble(row['ZSHOULDERSVOLUMEGOAL']),
              ),
              armsVolumeGoal: Value(_nullableDouble(row['ZARMSVOLUMEGOAL'])),
              coreVolumeGoal: Value(_nullableDouble(row['ZCOREVOLUMEGOAL'])),
              restDayReminder: Value(_boolFromInt(row['ZRESTDAYREMINDER'])),
              createdAt: _dateFromCoreData(row['ZCREATEDAT']),
              updatedAt: _dateFromCoreData(row['ZUPDATEDAT']),
            ),
          );
    }
    return rows.length;
  }

  Future<int> _importPowerLiftRecords(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Set<String> userIds,
    _ImportTally tally,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZPOWERLIFTRECORDENTITY');
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      await db
          .into(db.powerLiftRecords)
          .insert(
            PowerLiftRecordsCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                '三大項紀錄($id)',
                tally,
              ),
              lift: row['ZLIFT'] as String,
              oneRepMax: Value(_doubleOrZero(row['ZONEREPMAX'])),
              weight: Value(_doubleOrZero(row['ZWEIGHT'])),
              reps: Value((row['ZREPS'] as int?) ?? 1),
              achievedAt: _dateFromCoreData(row['ZACHIEVEDAT']),
              note: Value(row['ZNOTE'] as String?),
              createdAt: _dateFromCoreData(row['ZCREATEDAT']),
              updatedAt: _dateFromCoreData(row['ZUPDATEDAT']),
            ),
          );
    }
    return rows.length;
  }
}

/// `importIfNeeded` 用來記錄「目前跑到哪一張表/哪個階段」的可變容器,失敗時
/// 寫進 log(spec 4.6 節)。獨立成一個小容器類別,而不是 [CoreDataImporter]
/// 的 instance 欄位——`CoreDataImporter` 本身是 `const`(無狀態),不該為了
/// 這種每次呼叫都不同的暫時性資訊而變成可變物件。
class _CurrentStepHolder {
  String? value;
}

/// 匯入過程中累積的統計數字,收攏成一個物件在 `_importFromFile` 與各
/// `_import*` helper 之間傳遞——取代原本 `warnings` / `createdPlaceholders`
/// 這兩個可變狀態各自當獨立參數傳給每個 helper 的長參數列(11 個表的 import
/// 函式原本每個都要重複這兩個參數)。純資料容器,不含邏輯,行為與拆分前
/// 完全相同,只是把散落各處的可變狀態收成一份;`counts` /
/// `skippedCounts` / `dedupedCounts` 三個 map 是 `_importFromFile` 自己在
/// transaction 裡逐表寫入,不是 helper 寫的,一併放進同一個物件單純是因為
/// 它們最終要組成同一份 [ImportResult]。
class _ImportTally {
  /// 落地筆數(實際 insert 進 Drift 的筆數,見 [ImportResult] 類別文件的
  /// 帳式說明)。
  final Map<String, int> counts = {};

  /// 只有 template_exercises / workout_exercises / workout_sets 有結構層
  /// 孤兒防護會略過整列,其餘表恆為 0(不特別寫入 key)。
  final Map<String, int> skippedCounts = {};

  /// 目前只有 exercises(系統動作對映到既有種子)有這個概念。
  final Map<String, int> dedupedCounts = {};

  /// 惰性補建的佔位列筆數,只有 users / exercises 會有非零值,見
  /// [CoreDataImporter._resolveUserId] / [CoreDataImporter._resolveOrCreatePlaceholderExercise]。
  final Map<String, int> createdPlaceholders = {};

  final List<String> warnings = [];
}

// ---- 型別轉換工具(見 spec 第 2.3 節)----

String _uuidFromBlob(Object? blob) {
  final bytes = blob as Uint8List;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

String? _uuidFromBlobOrNull(Object? blob) =>
    blob == null ? null : _uuidFromBlob(blob);

final _uuidRandom = Random.secure();

/// 佔位使用者 / 佔位動作用的新 id——不引入外部套件,自己生成標準格式的
/// UUID v4(version/variant bits 依 RFC 4122 設置)。
String _generateUuidV4() {
  final bytes = List<int>.generate(16, (_) => _uuidRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xxxxxx
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

/// Unix 秒 = CoreData 值(2001-01-01 起的秒數)+ 978307200,再轉毫秒給
/// DateTime。
DateTime _dateFromCoreData(Object? value) {
  final seconds = (value as num).toDouble();
  final millis = ((seconds + _coreDataEpochOffsetSeconds) * 1000).round();
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

DateTime? _dateFromCoreDataOrNull(Object? value) =>
    value == null ? null : _dateFromCoreData(value);

bool _boolFromInt(Object? value) => value == 1 || value == true;

double _doubleOrZero(Object? value) => (value as num?)?.toDouble() ?? 0.0;

double? _nullableDouble(Object? value) => (value as num?)?.toDouble();

/// rpe / restSeconds 專用:0(含 CoreData optional 屬性沒賦值時 fallback 用
/// 的 defaultValueString)一律視為「未填」轉成 NULL。
double? _nonZeroDoubleOrNull(Object? value) {
  if (value == null) return null;
  final d = (value as num).toDouble();
  return d == 0.0 ? null : d;
}

int? _nonZeroIntOrNull(Object? value) {
  if (value == null) return null;
  final i = (value as num).toInt();
  return i == 0 ? null : i;
}
