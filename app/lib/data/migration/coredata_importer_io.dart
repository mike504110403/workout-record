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

import 'package:drift/drift.dart' show Value;
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
  })  : _supportDirectoryProvider = supportDirectoryProvider,
        _temporaryDirectoryProvider = temporaryDirectoryProvider;

  final Future<Directory> Function() _supportDirectoryProvider;
  final Future<Directory> Function() _temporaryDirectoryProvider;

  Future<ImportResult> importIfNeeded(AppDatabase db) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kCoreDataImportCompletedKey) ?? false) {
      return const ImportResult.skippedNoOldDb();
    }
    if (prefs.getBool(kCoreDataImportFailedPermanentlyKey) ?? false) {
      return const ImportResult.skippedPermanentlyFailed();
    }

    final supportDir = await _supportDirectoryProvider();
    final log = ImportLog(supportDirectoryProvider: _supportDirectoryProvider);
    final oldDbFile = File(p.join(supportDir.path, _oldDbFileName));
    if (!oldDbFile.existsSync()) {
      await prefs.setBool(kCoreDataImportCompletedKey, true);
      return const ImportResult.skippedNoOldDb();
    }

    File? copiedDbFile;
    try {
      copiedDbFile = await _copyToTemp(supportDir);
      final result = await _importFromFile(db, copiedDbFile);
      if (result.success) {
        await prefs.setBool(kCoreDataImportCompletedKey, true);
        await prefs.setInt(kCoreDataImportAttemptsKey, 0);
        await prefs.setString(
          kCoreDataImportTableCountsKey,
          jsonEncode(result.tableCounts),
        );
        await log.append(
          '匯入成功:tableCounts=${result.tableCounts}, '
          'skippedCounts=${result.skippedCounts}, warnings=${result.warnings.length} 則',
        );
      }
      return result;
    } catch (e, st) {
      // 任何未預期例外(檔案損毀、schema 不符...)→ 不寫入完成旗標,
      // 下次啟動會重新偵測到「舊檔存在 + 完成旗標未設置」,自動重試,直到
      // 連續失敗達 _maxConsecutiveFailures 次為止(spec 4.6 節)。
      final attempts = (prefs.getInt(kCoreDataImportAttemptsKey) ?? 0) + 1;
      await prefs.setInt(kCoreDataImportAttemptsKey, attempts);
      await log.append('匯入失敗(連續第 $attempts 次):$e\n$st');

      if (attempts >= _maxConsecutiveFailures) {
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
      );
    } finally {
      if (copiedDbFile != null) {
        await _safeDelete(copiedDbFile);
        await _safeDelete(File('${copiedDbFile.path}-wal'));
        await _safeDelete(File('${copiedDbFile.path}-shm'));
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
  Future<ImportResult> _importFromFile(AppDatabase db, File dbFile) async {
    final oldDb = sqlite3lib.sqlite3.open(
      dbFile.path,
      mode: sqlite3lib.OpenMode.readOnly,
    );
    try {
      // 落地筆數(實際 insert 進 Drift 的筆數,見 ImportResult 類別註解)。
      final counts = <String, int>{};
      // 只有 template_exercises / workout_exercises / workout_sets 有結構層
      // 孤兒防護會略過整列,其餘表恆為 0(不特別寫入 key)。
      final skippedCounts = <String, int>{};
      final warnings = <String>[];

      await db.transaction(() async {
        final usersImport = await _importUsers(db, oldDb);
        counts['users'] = usersImport.sourceCount;
        final userIds = usersImport.ids;

        final exercisesImport =
            await _importExercises(db, oldDb, userIds, warnings);
        counts['exercises'] = exercisesImport.sourceCount;
        final exerciseIdMap = exercisesImport.idMap;
        // 名稱 → 補建的佔位動作 id,讓不同的舊 exerciseId 若解析到同一個
        // 名稱時共用同一筆佔位動作,不會重複補建(見 _resolveOrCreatePlaceholderExercise)。
        final placeholderExerciseIdsByName = <String, String>{};

        final templatesImport =
            await _importTemplates(db, oldDb, userIds, warnings);
        counts['templates'] = templatesImport.sourceCount;
        final templateExercisesImport = await _importTemplateExercises(
          db,
          oldDb,
          exerciseIdMap,
          templatesImport.ids,
          warnings,
        );
        counts['template_exercises'] = templateExercisesImport.landedCount;
        skippedCounts['template_exercises'] = templateExercisesImport.skippedCount;

        final workoutsImport =
            await _importWorkouts(db, oldDb, userIds, warnings);
        counts['workouts'] = workoutsImport.sourceCount;
        final workoutExercisesImport = await _importWorkoutExercises(
          db,
          oldDb,
          exerciseIdMap,
          workoutsImport.ids,
          placeholderExerciseIdsByName,
          warnings,
        );
        counts['workout_exercises'] = workoutExercisesImport.landedCount;
        skippedCounts['workout_exercises'] = workoutExercisesImport.skippedCount;

        final workoutSetsImport = await _importWorkoutSets(
          db,
          oldDb,
          workoutExercisesImport.ids,
          warnings,
        );
        counts['workout_sets'] = workoutSetsImport.landedCount;
        skippedCounts['workout_sets'] = workoutSetsImport.skippedCount;

        counts['body_weights'] =
            await _importBodyWeights(db, oldDb, userIds, warnings);
        counts['personal_records'] = await _importPersonalRecords(
          db,
          oldDb,
          exerciseIdMap,
          placeholderExerciseIdsByName,
          userIds,
          warnings,
        );
        counts['user_goals'] = await _importUserGoals(db, oldDb, userIds, warnings);
        counts['power_lift_records'] =
            await _importPowerLiftRecords(db, oldDb, userIds, warnings);
      });

      return ImportResult(
        success: true,
        skipped: false,
        tableCounts: counts,
        skippedCounts: skippedCounts,
        warnings: warnings,
      );
    } finally {
      oldDb.dispose();
    }
  }

  Future<({int sourceCount, Set<String> ids})> _importUsers(
    AppDatabase db,
    sqlite3lib.Database oldDb,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZUSERENTITY');
    final ids = <String>{};
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      await db.into(db.users).insert(
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
  /// fallback 到這筆佔位使用者,不會重複補建。
  Future<String> _resolveUserId(
    AppDatabase db,
    String candidateUserId,
    Set<String> userIds,
    List<String> warnings,
    String context,
  ) async {
    if (userIds.contains(candidateUserId)) {
      return candidateUserId;
    }
    if (userIds.isEmpty) {
      final placeholderId = _generateUuidV4();
      final now = DateTime.now();
      await db.into(db.users).insert(
            UsersCompanion.insert(
              id: placeholderId,
              createdAt: now,
              updatedAt: now,
            ),
          );
      userIds.add(placeholderId);
      warnings.add(
        '$context 的 userId($candidateUserId)未對到任何使用者,'
        '舊庫也沒有任何 UserEntity,已補建佔位使用者($placeholderId)。',
      );
      return placeholderId;
    }
    final fallback = userIds.first;
    warnings.add(
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
  /// 補建。
  Future<String> _resolveOrCreatePlaceholderExercise({
    required AppDatabase db,
    required String oldExerciseId,
    required String? name,
    required String? type,
    required Map<String, String> exerciseIdMap,
    required Map<String, String> placeholderIdsByName,
    required List<String> warnings,
    required String context,
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
    await db.into(db.exercises).insert(
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
    warnings.add(
      '$context 的 exerciseId($oldExerciseId)未對到任何動作,'
      '已補建佔位動作「$resolvedName」($placeholderId)。',
    );
    return placeholderId;
  }

  /// 系統動作(isSystem = true)以「名稱 + categoryId」對映到 seedIfEmpty()
  /// 已建立的內建動作(重複的不插入,只記住 id 對映);自訂動作(isSystem =
  /// false)照原樣搬,保留原 UUID。回傳:舊 id(小寫 UUID 字串)→ 新 id 的
  /// 對映表(給 TemplateExercises / WorkoutExercises / PersonalRecords 的
  /// exerciseId 用),以及讀到的舊資料筆數。
  Future<({Map<String, String> idMap, int sourceCount})> _importExercises(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Set<String> userIds,
    List<String> warnings,
  ) async {
    final existingSystemExercises = await (db.select(db.exercises)
          ..where((t) => t.isSystem.equals(true)))
        .get();
    final seedByNameAndCategory = <String, String>{
      for (final e in existingSystemExercises) '${e.name}\u0000${e.categoryId}': e.id,
    };

    final rows = oldDb.select('SELECT * FROM ZEXERCISEENTITY');
    final idMap = <String, String>{};

    for (final row in rows) {
      final oldId = _uuidFromBlob(row['ZID']);
      final name = row['ZNAME'] as String;
      final categoryId = _uuidFromBlob(row['ZCATEGORYID']);
      final isSystem = _boolFromInt(row['ZISSYSTEM']);

      if (isSystem) {
        final match = seedByNameAndCategory['$name\u0000$categoryId'];
        if (match != null) {
          idMap[oldId] = match;
          continue;
        }
        warnings.add('系統動作「$name」(舊 id $oldId)未能與內建種子對映,已改為原樣匯入。');
      }

      final rawUserId = _uuidFromBlobOrNull(row['ZUSERID']);
      final resolvedUserId = rawUserId == null
          ? null
          : await _resolveUserId(db, rawUserId, userIds, warnings, '自訂動作「$name」');
      await db.into(db.exercises).insert(
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

    return (idMap: idMap, sourceCount: rows.length);
  }

  Future<({int sourceCount, Set<String> ids})> _importTemplates(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Set<String> userIds,
    List<String> warnings,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZTEMPLATEENTITY');
    final ids = <String>{};
    for (final row in rows) {
      final name = row['ZNAME'] as String;
      final id = _uuidFromBlob(row['ZID']);
      await db.into(db.templates).insert(
            TemplatesCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                warnings,
                '模板「$name」',
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
    List<String> warnings,
  ) async {
    final rows = oldDb.select(
      'SELECT * FROM ZTEMPLATEEXERCISEENTITY ORDER BY ZTEMPLATE, ZORDERINDEX',
    );
    var skipped = 0;
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      final templateId = _uuidFromBlob(row['ZTEMPLATEID']);
      if (!templateIds.contains(templateId)) {
        warnings.add(
          '[template_exercises] 模板動作($id)的 templateId($templateId)'
          '未對到任何已匯入的模板,已略過。',
        );
        skipped++;
        continue;
      }

      final oldExerciseId = _uuidFromBlob(row['ZEXERCISEID']);
      final newExerciseId = exerciseIdMap[oldExerciseId];
      if (newExerciseId == null) {
        warnings.add(
          '[template_exercises] 模板動作($id)的 exerciseId($oldExerciseId)'
          '未對到任何動作,已略過。',
        );
        skipped++;
        continue;
      }

      await db.into(db.templateExercises).insert(
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
    List<String> warnings,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZWORKOUTENTITY');
    final ids = <String>{};
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      await db.into(db.workouts).insert(
            WorkoutsCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                warnings,
                '訓練($id)',
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
  Future<({int sourceCount, int landedCount, int skippedCount, Set<String> ids})>
      _importWorkoutExercises(
    AppDatabase db,
    sqlite3lib.Database oldDb,
    Map<String, String> exerciseIdMap,
    Set<String> workoutIds,
    Map<String, String> placeholderExerciseIdsByName,
    List<String> warnings,
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
        warnings.add(
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
        warnings: warnings,
        context: '[workout_exercises] 訓練動作($id)',
      );

      await db.into(db.workoutExercises).insert(
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
    List<String> warnings,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZWORKOUTSETENTITY');
    var skipped = 0;
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      final workoutExerciseId = _uuidFromBlob(row['ZWORKOUTEXERCISEID']);
      if (!workoutExerciseIds.contains(workoutExerciseId)) {
        warnings.add(
          '[workout_sets] 訓練組數($id)的 workoutExerciseId($workoutExerciseId)'
          '未對到任何已匯入的訓練動作,已略過。',
        );
        skipped++;
        continue;
      }

      await db.into(db.workoutSets).insert(
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
    List<String> warnings,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZBODYWEIGHTENTITY');
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      await db.into(db.bodyWeights).insert(
            BodyWeightsCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                warnings,
                '體重紀錄($id)',
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
    List<String> warnings,
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
        warnings: warnings,
        context: '[personal_records] 個人紀錄($id)',
      );
      await db.into(db.personalRecords).insert(
            PersonalRecordsCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                warnings,
                '個人紀錄($id)',
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
    List<String> warnings,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZUSERGOALENTITY');
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      await db.into(db.userGoals).insert(
            UserGoalsCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                warnings,
                '使用者目標($id)',
              ),
              targetWeight: Value(_nullableDouble(row['ZTARGETWEIGHT'])),
              weeklyWorkoutGoal: Value((row['ZWEEKLYWORKOUTGOAL'] as int?) ?? 0),
              chestVolumeGoal: Value(_nullableDouble(row['ZCHESTVOLUMEGOAL'])),
              backVolumeGoal: Value(_nullableDouble(row['ZBACKVOLUMEGOAL'])),
              legsVolumeGoal: Value(_nullableDouble(row['ZLEGSVOLUMEGOAL'])),
              shouldersVolumeGoal:
                  Value(_nullableDouble(row['ZSHOULDERSVOLUMEGOAL'])),
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
    List<String> warnings,
  ) async {
    final rows = oldDb.select('SELECT * FROM ZPOWERLIFTRECORDENTITY');
    for (final row in rows) {
      final id = _uuidFromBlob(row['ZID']);
      await db.into(db.powerLiftRecords).insert(
            PowerLiftRecordsCompanion.insert(
              id: id,
              userId: await _resolveUserId(
                db,
                _uuidFromBlob(row['ZUSERID']),
                userIds,
                warnings,
                '三大項紀錄($id)',
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
