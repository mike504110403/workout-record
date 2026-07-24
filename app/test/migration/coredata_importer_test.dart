// CoreData → Drift 匯入邏輯的驗收測試。
//
// 用真實 fixture(app/test/fixtures/WorkoutRecord.sqlite,見該目錄下
// schema_dump.sql 的實測記錄)模擬「舊 App 沙盒裡的 Application Support
// 目錄」—— 複製到測試專用的臨時目錄,搭配 [CoreDataImporter] 建構子上
// 可覆寫的 supportDirectoryProvider / temporaryDirectoryProvider,不需要
// mock 任何 path_provider platform channel。
//
// 覆蓋:逐表筆數比對(對應「不遺失任何訓練歷史」的量化驗證)、抽樣欄位、
// 動作對映去重、模板動作排序、關聯完整性、冪等、邊界情況
// (舊檔不存在 / 壞檔 / optional 欄位為 NULL / rpe·restSeconds 0→NULL)。
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;
import 'package:workout_record/data/db/app_database.dart';
import 'package:workout_record/data/migration/coredata_importer.dart';

final String _fixtureDbPath = p.join('test', 'fixtures', 'WorkoutRecord.sqlite');

void main() {
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('coredata_importer_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// 把真實 fixture(連同 -wal/-shm)複製到一個臨時目錄,模擬「舊 App 沙盒
  /// 裡的 Application Support 目錄」。
  Directory copyFixtureAsOldAppSupportDir() {
    final supportDir = Directory(p.join(tempDir.path, 'support'))
      ..createSync(recursive: true);
    for (final suffix in ['', '-wal', '-shm']) {
      final source = File('$_fixtureDbPath$suffix');
      if (source.existsSync()) {
        source.copySync(p.join(supportDir.path, 'WorkoutRecord.sqlite$suffix'));
      }
    }
    return supportDir;
  }

  CoreDataImporter importerWithSupportDir(Directory supportDir) {
    return CoreDataImporter(
      supportDirectoryProvider: () async => supportDir,
      temporaryDirectoryProvider: () async {
        final dir = Directory(p.join(tempDir.path, 'tmp_${supportDir.hashCode}'));
        dir.createSync(recursive: true);
        return dir;
      },
    );
  }

  /// 對 fixture 直接下 SELECT COUNT(*),作為逐表比對的基準(spec 5.2 節)。
  Map<String, int> fixtureSourceCounts() {
    final oldDb = sqlite3lib.sqlite3.open(
      _fixtureDbPath,
      mode: sqlite3lib.OpenMode.readOnly,
    );
    try {
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
    } finally {
      oldDb.dispose();
    }
  }

  group('CoreDataImporter - 真實 fixture 完整匯入', () {
    test('各表匯入筆數與 fixture 來源筆數逐表一致', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.skipped, isFalse);
      expect(result.tableCounts, equals(fixtureSourceCounts()));
    });

    test('66 個動作:系統動作與 seed 名稱對映後總數仍 66,id 不重複', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      await importer.importIfNeeded(db);

      final exercises = await db.select(db.exercises).get();
      expect(exercises, hasLength(66));
      expect(exercises.map((e) => e.id).toSet(), hasLength(66));
      expect(exercises.every((e) => e.isSystem), isTrue);
    });

    test('4 個模板、20 個模板動作', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      await importer.importIfNeeded(db);

      expect(await db.select(db.templates).get(), hasLength(4));
      expect(await db.select(db.templateExercises).get(), hasLength(20));
    });

    test('1 個用戶、1 筆體重、3 筆個人紀錄、3 筆三大項紀錄', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      await importer.importIfNeeded(db);

      expect(await db.select(db.users).get(), hasLength(1));
      expect(await db.select(db.bodyWeights).get(), hasLength(1));
      expect(await db.select(db.personalRecords).get(), hasLength(3));
      expect(await db.select(db.powerLiftRecords).get(), hasLength(3));
    });

    test('抽樣:體重的 weight/measuredAt 轉換正確', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      await importer.importIfNeeded(db);

      final bodyWeight = (await db.select(db.bodyWeights).get()).single;
      expect(bodyWeight.weight, 80.0);
      // fixture 的原始 ZMEASUREDAT(Core Data 秒數)是 783421278.973596;
      // Unix 秒 = 該值 + 978307200。Drift 的 dateTime() 欄位本身是以整數秒
      // 儲存(tables.dart 既有設計,不在這次匯入邏輯的改動範圍內),讀回來
      // 的 DateTime 只到秒級精度,所以比對時同樣截到秒。
      const rawCoreDataSeconds = 783421278.973596;
      final expectedSeconds = (rawCoreDataSeconds + 978307200).floor();
      expect(
        bodyWeight.measuredAt.millisecondsSinceEpoch,
        expectedSeconds * 1000,
      );
    });

    test('抽樣:個人紀錄(PR)的 oneRepMax/weight/reps 正確', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      await importer.importIfNeeded(db);

      final records = await db.select(db.personalRecords).get();
      final match = records.singleWhere(
        (r) => r.id == _hexToUuid('75D18EBFB8E047D89DF6FA1714DEBB75'),
      );
      expect(match.oneRepMax, closeTo(53.3333333333333, 1e-9));
      expect(match.weight, 40.0);
      expect(match.reps, 10);
    });

    test('模板動作順序依 ZORDERINDEX 排列正確', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      await importer.importIfNeeded(db);

      final pushTemplateId = _hexToUuid('2339F463F7A44B95BD8BE91F0CC6736B');
      final orderedTemplateExercises = await (db.select(db.templateExercises)
            ..where((t) => t.templateId.equals(pushTemplateId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .get();

      expect(orderedTemplateExercises, hasLength(5));
      final firstExercise = await (db.select(db.exercises)
            ..where((t) => t.id.equals(orderedTemplateExercises.first.exerciseId)))
          .getSingle();
      // fixture 裡 PPL - Push 模板 orderIndex = 0 的動作是「槓鈴臥推」。
      expect(firstExercise.name, '槓鈴臥推');
    });

    test('關聯完整性:TemplateExercises.exerciseId 全部指向存在的動作', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      await importer.importIfNeeded(db);

      final exerciseIds =
          (await db.select(db.exercises).get()).map((e) => e.id).toSet();
      final templateExerciseIds = (await db.select(db.templateExercises).get())
          .map((te) => te.exerciseId)
          .toSet();

      expect(exerciseIds.containsAll(templateExerciseIds), isTrue);
    });

    test('冪等:跑兩次不會重複匯入', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      final first = await importer.importIfNeeded(db);
      final second = await importer.importIfNeeded(db);

      expect(first.skipped, isFalse);
      expect(second.skipped, isTrue);
      expect(await db.select(db.templates).get(), hasLength(4));
    });
  });

  group('CoreDataImporter - 邊界情況', () {
    test('舊檔不存在(全新安裝 / Android)→ 正常返回,標記完成,不是錯誤', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final emptySupportDir = Directory(p.join(tempDir.path, 'empty_support'))
        ..createSync(recursive: true);
      final importer = importerWithSupportDir(emptySupportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue);
      expect(result.skipped, isTrue);
      expect(result.errorMessage, isNull);
      expect(await db.select(db.workouts).get(), isEmpty);
    });

    test('壞檔(隨機 bytes 冒充 .sqlite)→ 匯入失敗但不拋未捕捉例外', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final badSupportDir = Directory(p.join(tempDir.path, 'bad_support'))
        ..createSync(recursive: true);
      File(p.join(badSupportDir.path, 'WorkoutRecord.sqlite'))
          .writeAsBytesSync(List<int>.generate(256, (i) => i % 256));
      final importer = importerWithSupportDir(badSupportDir);

      // 呼叫本身不能拋出未捕捉例外——importIfNeeded 要自己 catch 並回傳失敗
      // 結果。
      final result = await importer.importIfNeeded(db);

      expect(result.success, isFalse);
      expect(result.errorMessage, isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kCoreDataImportCompletedKey) ?? false, isFalse);
    });

    test('optional 欄位為 NULL(使用者 email 為 nil)不因 null 而 crash', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue);
      final user = (await db.select(db.users).get()).single;
      expect(user.email, isNull);
      expect(user.name, '健身愛好者');
    });

    test('rpe / restSeconds 的 0 值轉為 NULL(真實 fixture 沒有 workout_sets,'
        '用合成的最小舊庫驗證這條轉換規則)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = Directory(p.join(tempDir.path, 'synthetic_support'))
        ..createSync(recursive: true);
      _buildSyntheticOldDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      final sets = await (db.select(db.workoutSets)
            ..orderBy([(t) => OrderingTerm.asc(t.setNumber)]))
          .get();
      expect(sets, hasLength(2));
      expect(sets[0].rpe, isNull);
      expect(sets[0].restSeconds, isNull);
      expect(sets[1].rpe, 8.5);
      expect(sets[1].restSeconds, 90);
    });
  });

  group('CoreDataImporter - 孤兒防護(結構層 FK)', () {
    test('workout_exercise 指向不存在的 workout → 該列與其 sets 被 skip,'
        '其他 workout 正常匯入', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = Directory(p.join(tempDir.path, 'orphan_we_support'))
        ..createSync(recursive: true);
      _buildOrphanWorkoutExerciseDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(await db.select(db.workouts).get(), hasLength(1));
      final workoutExercises = await db.select(db.workoutExercises).get();
      expect(workoutExercises, hasLength(1));
      expect(workoutExercises.single.note, 'valid workout exercise');
      final sets = await db.select(db.workoutSets).get();
      expect(sets, hasLength(1));
      expect(sets.single.note, 'valid set');
      expect(
        result.warnings.any((w) => w.contains('workout_exercises') && w.contains('未對到任何已匯入的訓練')),
        isTrue,
      );
    });

    test('workout_set 指向不存在的 workout_exercise → 該列 skip', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = Directory(p.join(tempDir.path, 'orphan_ws_support'))
        ..createSync(recursive: true);
      _buildOrphanWorkoutSetDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      final sets = await db.select(db.workoutSets).get();
      expect(sets, hasLength(1));
      expect(sets.single.note, 'valid set');
      expect(
        result.warnings.any((w) => w.contains('workout_sets') && w.contains('未對到任何已匯入的訓練動作')),
        isTrue,
      );
    });

    test('template_exercise 指向不存在的 template → skip', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = Directory(p.join(tempDir.path, 'orphan_te_support'))
        ..createSync(recursive: true);
      _buildOrphanTemplateExerciseDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      final templateExercises = await db.select(db.templateExercises).get();
      expect(templateExercises, hasLength(1));
      expect(templateExercises.single.suggestedSets, 3);
      expect(
        result.warnings.any((w) => w.contains('template_exercises') && w.contains('未對到任何已匯入的模板')),
        isTrue,
      );
    });

    test('workout_exercise 的 exerciseId 在舊庫 exercises 中不存在 → '
        '佔位動作補建、sets 保留、可讀回', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = Directory(p.join(tempDir.path, 'missing_exercise_we_support'))
        ..createSync(recursive: true);
      _buildMissingExerciseForWorkoutExerciseDb(
        p.join(supportDir.path, 'WorkoutRecord.sqlite'),
      );
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      final workoutExercises = await db.select(db.workoutExercises).get();
      expect(workoutExercises, hasLength(1));
      final placeholderExercise = await (db.select(db.exercises)
            ..where((t) => t.id.equals(workoutExercises.single.exerciseId)))
          .getSingle();
      expect(placeholderExercise.name, 'Ghost Exercise');
      expect(placeholderExercise.isSystem, isFalse);
      expect(placeholderExercise.isActive, isTrue);
      expect(placeholderExercise.userId, isNull);

      final sets = await db.select(db.workoutSets).get();
      expect(sets, hasLength(1));
      expect(sets.single.weight, 60.0);
      expect(sets.single.reps, 5);

      expect(
        result.warnings.any((w) => w.contains('workout_exercises') && w.contains('已補建佔位動作「Ghost Exercise」')),
        isTrue,
      );
    });

    test('personal_record 的 exerciseId 對不上 → 佔位「未知動作」補建、PR 保留', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = Directory(p.join(tempDir.path, 'missing_exercise_pr_support'))
        ..createSync(recursive: true);
      _buildMissingExerciseForPersonalRecordDb(
        p.join(supportDir.path, 'WorkoutRecord.sqlite'),
      );
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      final records = await db.select(db.personalRecords).get();
      expect(records, hasLength(1));
      final placeholderExercise = await (db.select(db.exercises)
            ..where((t) => t.id.equals(records.single.exerciseId)))
          .getSingle();
      expect(placeholderExercise.name, '未知動作');
      expect(records.single.oneRepMax, closeTo(70.0, 1e-9));

      expect(
        result.warnings.any((w) => w.contains('personal_records') && w.contains('已補建佔位動作「未知動作」')),
        isTrue,
      );
    });

    test('舊庫無 user 但有 body_weight → 佔位使用者補建、資料保留', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = Directory(p.join(tempDir.path, 'no_user_support'))
        ..createSync(recursive: true);
      _buildNoUserWithBodyWeightDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      final users = await db.select(db.users).get();
      expect(users, hasLength(1));
      expect(users.single.name, isNull);
      expect(users.single.email, isNull);

      final bodyWeights = await db.select(db.bodyWeights).get();
      expect(bodyWeights, hasLength(1));
      expect(bodyWeights.single.userId, users.single.id);
      expect(bodyWeights.single.weight, 82.5);

      expect(
        result.warnings.any((w) => w.contains('舊庫也沒有任何 UserEntity') && w.contains('已補建佔位使用者')),
        isTrue,
      );
    });
  });
}

String _hexToUuid(String hex) {
  final lower = hex.toLowerCase();
  return '${lower.substring(0, 8)}-${lower.substring(8, 12)}-'
      '${lower.substring(12, 16)}-${lower.substring(16, 20)}-'
      '${lower.substring(20, 32)}';
}

Uint8List _fakeUuidBytes(int seed) {
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = (seed * 7 + i) % 256;
  }
  return bytes;
}

const _syntheticSchema = '''
CREATE TABLE ZBODYWEIGHTENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZISSYNCED INTEGER, ZUSER INTEGER, ZCREATEDAT TIMESTAMP, ZMEASUREDAT TIMESTAMP, ZUPDATEDAT TIMESTAMP, ZWEIGHT FLOAT, ZNOTE VARCHAR, ZID BLOB, ZUSERID BLOB );
CREATE TABLE ZEXERCISEENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZISACTIVE INTEGER, ZISSYSTEM INTEGER, ZUSER INTEGER, ZCREATEDAT TIMESTAMP, ZUPDATEDAT TIMESTAMP, ZDESCRIPTIONTEXT VARCHAR, ZIMAGEURL VARCHAR, ZMOVEMENTPATTERN VARCHAR, ZNAME VARCHAR, ZNAMEEN VARCHAR, ZPRIMARYMUSCLEGROUP VARCHAR, ZTYPE VARCHAR, ZVIDEOURL VARCHAR, ZCATEGORYID BLOB, ZID BLOB, ZUSERID BLOB );
CREATE TABLE ZPERSONALRECORDENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZREPS INTEGER, ZACHIEVEDAT TIMESTAMP, ZCREATEDAT TIMESTAMP, ZONEREPMAX FLOAT, ZUPDATEDAT TIMESTAMP, ZWEIGHT FLOAT, ZEXERCISEID BLOB, ZID BLOB, ZUSERID BLOB, ZWORKOUTID BLOB );
CREATE TABLE ZPOWERLIFTRECORDENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZREPS INTEGER, ZACHIEVEDAT TIMESTAMP, ZCREATEDAT TIMESTAMP, ZONEREPMAX FLOAT, ZUPDATEDAT TIMESTAMP, ZWEIGHT FLOAT, ZLIFT VARCHAR, ZNOTE VARCHAR, ZID BLOB, ZUSERID BLOB );
CREATE TABLE ZTEMPLATEENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZISSYSTEM INTEGER, ZUSER INTEGER, ZCREATEDAT TIMESTAMP, ZUPDATEDAT TIMESTAMP, ZDESCRIPTIONTEXT VARCHAR, ZNAME VARCHAR, ZID BLOB, ZUSERID BLOB );
CREATE TABLE ZTEMPLATEEXERCISEENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZORDERINDEX INTEGER, ZSUGGESTEDREPS INTEGER, ZSUGGESTEDSETS INTEGER, ZTEMPLATE INTEGER, Z_FOK_TEMPLATE INTEGER, ZEXERCISEID BLOB, ZID BLOB, ZTEMPLATEID BLOB );
CREATE TABLE ZUSERENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZCREATEDAT TIMESTAMP, ZUPDATEDAT TIMESTAMP, ZEMAIL VARCHAR, ZNAME VARCHAR, ZID BLOB );
CREATE TABLE ZUSERGOALENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZRESTDAYREMINDER INTEGER, ZWEEKLYWORKOUTGOAL INTEGER, ZARMSVOLUMEGOAL FLOAT, ZBACKVOLUMEGOAL FLOAT, ZCHESTVOLUMEGOAL FLOAT, ZCOREVOLUMEGOAL FLOAT, ZCREATEDAT TIMESTAMP, ZLEGSVOLUMEGOAL FLOAT, ZSHOULDERSVOLUMEGOAL FLOAT, ZTARGETWEIGHT FLOAT, ZUPDATEDAT TIMESTAMP, ZID BLOB, ZUSERID BLOB );
CREATE TABLE ZWORKOUTENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZDURATION INTEGER, ZISSYNCED INTEGER, ZTOTALEXERCISES INTEGER, ZTOTALSETS INTEGER, ZUSER INTEGER, ZCREATEDAT TIMESTAMP, ZENDEDAT TIMESTAMP, ZSTARTEDAT TIMESTAMP, ZTOTALVOLUME FLOAT, ZUPDATEDAT TIMESTAMP, ZNOTE VARCHAR, ZID BLOB, ZTEMPLATEID BLOB, ZUSERID BLOB );
CREATE TABLE ZWORKOUTEXERCISEENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZISCOMPLETED INTEGER, ZISCUSTOMEXERCISE INTEGER, ZORDERINDEX INTEGER, ZTOTALSETS INTEGER, ZEXERCISE INTEGER, ZWORKOUT INTEGER, Z_FOK_WORKOUT INTEGER, ZCREATEDAT TIMESTAMP, ZTOTALVOLUME FLOAT, ZUPDATEDAT TIMESTAMP, ZEXERCISENAME VARCHAR, ZNOTE VARCHAR, ZEXERCISEID BLOB, ZID BLOB, ZWORKOUTID BLOB );
CREATE TABLE ZWORKOUTSETENTITY ( Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZISWARMUP INTEGER, ZREPS INTEGER, ZRESTSECONDS INTEGER, ZSETNUMBER INTEGER, ZWORKOUTEXERCISE INTEGER, Z_FOK_WORKOUTEXERCISE INTEGER, ZCREATEDAT TIMESTAMP, ZRPE FLOAT, ZUPDATEDAT TIMESTAMP, ZVOLUME FLOAT, ZWEIGHT FLOAT, ZNOTE VARCHAR, ZID BLOB, ZWORKOUTEXERCISEID BLOB );
''';

/// 建一個最小可行的合成舊庫(只填 rpe/restSeconds 0→NULL 這條轉換規則需要
/// 的資料鏈:1 使用者 -> 1 自訂動作 -> 1 訓練 -> 1 訓練動作 -> 2 組數),
/// 其餘 6 張表建空表即可(匯入邏輯對全部 11 張表都會下 SELECT,缺表會直接
/// 失敗)。schema 逐字複製自 app/test/fixtures/schema_dump.sql。
void _buildSyntheticOldDb(String path) {
  final db = sqlite3lib.sqlite3.open(path);
  try {
    db.execute(_syntheticSchema);

    final userId = _fakeUuidBytes(1);
    final categoryId = _fakeUuidBytes(2);
    final exerciseId = _fakeUuidBytes(3);
    final workoutId = _fakeUuidBytes(4);
    final workoutExerciseId = _fakeUuidBytes(5);
    final setId1 = _fakeUuidBytes(6);
    final setId2 = _fakeUuidBytes(7);

    db.execute(
      'INSERT INTO ZUSERENTITY (ZID, ZNAME, ZEMAIL, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?, ?)',
      [userId, 'Synthetic User', null, 0.0, 0.0],
    );

    db.execute(
      'INSERT INTO ZEXERCISEENTITY '
      '(ZID, ZNAME, ZCATEGORYID, ZTYPE, ZISSYSTEM, ZISACTIVE, ZUSERID, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [exerciseId, 'Synthetic Exercise', categoryId, 'free_weight', 0, 1, userId, 0.0, 0.0],
    );

    db.execute(
      'INSERT INTO ZWORKOUTENTITY '
      '(ZID, ZUSERID, ZSTARTEDAT, ZTOTALVOLUME, ZTOTALSETS, ZTOTALEXERCISES, '
      'ZISSYNCED, ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [workoutId, userId, 0.0, 940.0, 2, 1, 0, 0.0, 0.0],
    );

    db.execute(
      'INSERT INTO ZWORKOUTEXERCISEENTITY '
      '(ZID, ZWORKOUTID, ZEXERCISEID, ZEXERCISENAME, ZORDERINDEX, '
      'ZTOTALVOLUME, ZTOTALSETS, ZISCOMPLETED, ZISCUSTOMEXERCISE, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        workoutExerciseId,
        workoutId,
        exerciseId,
        'Synthetic Exercise',
        0,
        940.0,
        2,
        1,
        1,
        0.0,
        0.0,
      ],
    );

    // 第一組:rpe = 0.0、restSeconds = 0 → 匯入後應轉為 NULL。
    db.execute(
      'INSERT INTO ZWORKOUTSETENTITY '
      '(ZID, ZWORKOUTEXERCISEID, ZSETNUMBER, ZWEIGHT, ZREPS, ZVOLUME, ZRPE, '
      'ZRESTSECONDS, ZISWARMUP, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [setId1, workoutExerciseId, 1, 50.0, 10, 500.0, 0.0, 0, 0, 0.0, 0.0],
    );

    // 第二組:rpe/restSeconds 皆有實際值 → 原樣保留。
    db.execute(
      'INSERT INTO ZWORKOUTSETENTITY '
      '(ZID, ZWORKOUTEXERCISEID, ZSETNUMBER, ZWEIGHT, ZREPS, ZVOLUME, ZRPE, '
      'ZRESTSECONDS, ZISWARMUP, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [setId2, workoutExerciseId, 2, 55.0, 8, 440.0, 8.5, 90, 0, 0.0, 0.0],
    );
  } finally {
    db.dispose();
  }
}

/// (a) workout_exercise.workoutId 指向不存在的 workout:1 個有效 workout +
/// 有效 workout_exercise/set,另 1 個 workout_exercise(與其 set)的
/// workoutId 是從未寫進 ZWORKOUTENTITY 的懸空 UUID。
void _buildOrphanWorkoutExerciseDb(String path) {
  final db = sqlite3lib.sqlite3.open(path);
  try {
    db.execute(_syntheticSchema);

    final userId = _fakeUuidBytes(10);
    final categoryId = _fakeUuidBytes(11);
    final exerciseId = _fakeUuidBytes(12);
    final validWorkoutId = _fakeUuidBytes(13);
    final danglingWorkoutId = _fakeUuidBytes(14); // 從未寫進 ZWORKOUTENTITY
    final validWorkoutExerciseId = _fakeUuidBytes(15);
    final orphanWorkoutExerciseId = _fakeUuidBytes(16);
    final validSetId = _fakeUuidBytes(17);
    final orphanSetId = _fakeUuidBytes(18);

    db.execute(
      'INSERT INTO ZUSERENTITY (ZID, ZNAME, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?)',
      [userId, 'Synthetic User', 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZEXERCISEENTITY '
      '(ZID, ZNAME, ZCATEGORYID, ZTYPE, ZISSYSTEM, ZISACTIVE, ZUSERID, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [exerciseId, 'Bench Press', categoryId, 'free_weight', 0, 1, userId, 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZWORKOUTENTITY '
      '(ZID, ZUSERID, ZSTARTEDAT, ZTOTALVOLUME, ZTOTALSETS, ZTOTALEXERCISES, '
      'ZISSYNCED, ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [validWorkoutId, userId, 0.0, 500.0, 1, 1, 0, 0.0, 0.0],
    );

    // 有效:workoutId 對得到上面剛插入的 workout。
    db.execute(
      'INSERT INTO ZWORKOUTEXERCISEENTITY '
      '(ZID, ZWORKOUTID, ZEXERCISEID, ZEXERCISENAME, ZORDERINDEX, '
      'ZTOTALVOLUME, ZTOTALSETS, ZISCOMPLETED, ZISCUSTOMEXERCISE, ZNOTE, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        validWorkoutExerciseId,
        validWorkoutId,
        exerciseId,
        'Bench Press',
        0,
        500.0,
        1,
        1,
        0,
        'valid workout exercise',
        0.0,
        0.0,
      ],
    );
    // 孤兒:workoutId 指向從未存在的 workout。
    db.execute(
      'INSERT INTO ZWORKOUTEXERCISEENTITY '
      '(ZID, ZWORKOUTID, ZEXERCISEID, ZEXERCISENAME, ZORDERINDEX, '
      'ZTOTALVOLUME, ZTOTALSETS, ZISCOMPLETED, ZISCUSTOMEXERCISE, ZNOTE, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        orphanWorkoutExerciseId,
        danglingWorkoutId,
        exerciseId,
        'Bench Press',
        1,
        200.0,
        1,
        1,
        0,
        'orphan workout exercise',
        0.0,
        0.0,
      ],
    );

    db.execute(
      'INSERT INTO ZWORKOUTSETENTITY '
      '(ZID, ZWORKOUTEXERCISEID, ZSETNUMBER, ZWEIGHT, ZREPS, ZVOLUME, ZNOTE, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [validSetId, validWorkoutExerciseId, 1, 50.0, 10, 500.0, 'valid set', 0.0, 0.0],
    );
    // 掛在孤兒 workout_exercise 底下的 set,應隨其父列一併被略過。
    db.execute(
      'INSERT INTO ZWORKOUTSETENTITY '
      '(ZID, ZWORKOUTEXERCISEID, ZSETNUMBER, ZWEIGHT, ZREPS, ZVOLUME, ZNOTE, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [orphanSetId, orphanWorkoutExerciseId, 1, 40.0, 8, 320.0, 'orphan set', 0.0, 0.0],
    );
  } finally {
    db.dispose();
  }
}

/// (b) workout_set.workoutExerciseId 指向不存在的 workout_exercise:1 個有效
/// workout_exercise + 有效 set,另 1 個 set 的 workoutExerciseId 是從未寫進
/// ZWORKOUTEXERCISEENTITY 的懸空 UUID。
void _buildOrphanWorkoutSetDb(String path) {
  final db = sqlite3lib.sqlite3.open(path);
  try {
    db.execute(_syntheticSchema);

    final userId = _fakeUuidBytes(20);
    final categoryId = _fakeUuidBytes(21);
    final exerciseId = _fakeUuidBytes(22);
    final workoutId = _fakeUuidBytes(23);
    final validWorkoutExerciseId = _fakeUuidBytes(24);
    final danglingWorkoutExerciseId = _fakeUuidBytes(25); // 從未寫進 ZWORKOUTEXERCISEENTITY
    final validSetId = _fakeUuidBytes(26);
    final orphanSetId = _fakeUuidBytes(27);

    db.execute(
      'INSERT INTO ZUSERENTITY (ZID, ZNAME, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?)',
      [userId, 'Synthetic User', 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZEXERCISEENTITY '
      '(ZID, ZNAME, ZCATEGORYID, ZTYPE, ZISSYSTEM, ZISACTIVE, ZUSERID, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [exerciseId, 'Squat', categoryId, 'free_weight', 0, 1, userId, 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZWORKOUTENTITY '
      '(ZID, ZUSERID, ZSTARTEDAT, ZTOTALVOLUME, ZTOTALSETS, ZTOTALEXERCISES, '
      'ZISSYNCED, ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [workoutId, userId, 0.0, 500.0, 1, 1, 0, 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZWORKOUTEXERCISEENTITY '
      '(ZID, ZWORKOUTID, ZEXERCISEID, ZEXERCISENAME, ZORDERINDEX, '
      'ZTOTALVOLUME, ZTOTALSETS, ZISCOMPLETED, ZISCUSTOMEXERCISE, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        validWorkoutExerciseId,
        workoutId,
        exerciseId,
        'Squat',
        0,
        500.0,
        1,
        1,
        0,
        0.0,
        0.0,
      ],
    );

    db.execute(
      'INSERT INTO ZWORKOUTSETENTITY '
      '(ZID, ZWORKOUTEXERCISEID, ZSETNUMBER, ZWEIGHT, ZREPS, ZVOLUME, ZNOTE, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [validSetId, validWorkoutExerciseId, 1, 60.0, 5, 300.0, 'valid set', 0.0, 0.0],
    );
    // 孤兒:workoutExerciseId 指向從未存在的 workout_exercise。
    db.execute(
      'INSERT INTO ZWORKOUTSETENTITY '
      '(ZID, ZWORKOUTEXERCISEID, ZSETNUMBER, ZWEIGHT, ZREPS, ZVOLUME, ZNOTE, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        orphanSetId,
        danglingWorkoutExerciseId,
        1,
        70.0,
        3,
        210.0,
        'orphan set',
        0.0,
        0.0,
      ],
    );
  } finally {
    db.dispose();
  }
}

/// (c) template_exercise.templateId 指向不存在的 template:1 個有效 template
/// + 有效 template_exercise,另 1 個 template_exercise 的 templateId 是從未
/// 寫進 ZTEMPLATEENTITY 的懸空 UUID。
void _buildOrphanTemplateExerciseDb(String path) {
  final db = sqlite3lib.sqlite3.open(path);
  try {
    db.execute(_syntheticSchema);

    final userId = _fakeUuidBytes(30);
    final categoryId = _fakeUuidBytes(31);
    final exerciseId = _fakeUuidBytes(32);
    final validTemplateId = _fakeUuidBytes(33);
    final danglingTemplateId = _fakeUuidBytes(34); // 從未寫進 ZTEMPLATEENTITY
    final validTemplateExerciseId = _fakeUuidBytes(35);
    final orphanTemplateExerciseId = _fakeUuidBytes(36);

    db.execute(
      'INSERT INTO ZUSERENTITY (ZID, ZNAME, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?)',
      [userId, 'Synthetic User', 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZEXERCISEENTITY '
      '(ZID, ZNAME, ZCATEGORYID, ZTYPE, ZISSYSTEM, ZISACTIVE, ZUSERID, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [exerciseId, 'Deadlift', categoryId, 'free_weight', 0, 1, userId, 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZTEMPLATEENTITY '
      '(ZID, ZUSERID, ZNAME, ZISSYSTEM, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [validTemplateId, userId, 'Pull Day', 0, 0.0, 0.0],
    );

    db.execute(
      'INSERT INTO ZTEMPLATEEXERCISEENTITY '
      '(ZID, ZTEMPLATEID, ZEXERCISEID, ZORDERINDEX, ZSUGGESTEDSETS, '
      'ZSUGGESTEDREPS) VALUES (?, ?, ?, ?, ?, ?)',
      [validTemplateExerciseId, validTemplateId, exerciseId, 0, 3, 8],
    );
    // 孤兒:templateId 指向從未存在的 template。
    db.execute(
      'INSERT INTO ZTEMPLATEEXERCISEENTITY '
      '(ZID, ZTEMPLATEID, ZEXERCISEID, ZORDERINDEX, ZSUGGESTEDSETS, '
      'ZSUGGESTEDREPS) VALUES (?, ?, ?, ?, ?, ?)',
      [orphanTemplateExerciseId, danglingTemplateId, exerciseId, 0, 99, 99],
    );
  } finally {
    db.dispose();
  }
}

/// (d) workout_exercise.exerciseId 在舊庫的 ZEXERCISEENTITY 中完全不存在
/// (該表本身是空的)——應補建佔位動作(名稱取自 ZEXERCISENAME),而不是
/// 略過整列(sets 底下掛著真實訓練歷史)。
void _buildMissingExerciseForWorkoutExerciseDb(String path) {
  final db = sqlite3lib.sqlite3.open(path);
  try {
    db.execute(_syntheticSchema);

    final userId = _fakeUuidBytes(40);
    final workoutId = _fakeUuidBytes(41);
    final ghostExerciseId = _fakeUuidBytes(42); // 從未寫進 ZEXERCISEENTITY
    final workoutExerciseId = _fakeUuidBytes(43);
    final setId = _fakeUuidBytes(44);

    db.execute(
      'INSERT INTO ZUSERENTITY (ZID, ZNAME, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?)',
      [userId, 'Synthetic User', 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZWORKOUTENTITY '
      '(ZID, ZUSERID, ZSTARTEDAT, ZTOTALVOLUME, ZTOTALSETS, ZTOTALEXERCISES, '
      'ZISSYNCED, ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [workoutId, userId, 0.0, 300.0, 1, 1, 0, 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZWORKOUTEXERCISEENTITY '
      '(ZID, ZWORKOUTID, ZEXERCISEID, ZEXERCISENAME, ZORDERINDEX, '
      'ZTOTALVOLUME, ZTOTALSETS, ZISCOMPLETED, ZISCUSTOMEXERCISE, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        workoutExerciseId,
        workoutId,
        ghostExerciseId,
        'Ghost Exercise',
        0,
        300.0,
        1,
        1,
        0,
        0.0,
        0.0,
      ],
    );
    db.execute(
      'INSERT INTO ZWORKOUTSETENTITY '
      '(ZID, ZWORKOUTEXERCISEID, ZSETNUMBER, ZWEIGHT, ZREPS, ZVOLUME, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [setId, workoutExerciseId, 1, 60.0, 5, 300.0, 0.0, 0.0],
    );
  } finally {
    db.dispose();
  }
}

/// (e) personal_record.exerciseId 在舊庫的 ZEXERCISEENTITY 中完全不存在——
/// 應補建「未知動作」佔位(PersonalRecordEntity 沒有名稱欄可用),PR 本身
/// 保留。
void _buildMissingExerciseForPersonalRecordDb(String path) {
  final db = sqlite3lib.sqlite3.open(path);
  try {
    db.execute(_syntheticSchema);

    final userId = _fakeUuidBytes(50);
    final ghostExerciseId = _fakeUuidBytes(51); // 從未寫進 ZEXERCISEENTITY
    final recordId = _fakeUuidBytes(52);

    db.execute(
      'INSERT INTO ZUSERENTITY (ZID, ZNAME, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?)',
      [userId, 'Synthetic User', 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZPERSONALRECORDENTITY '
      '(ZID, ZUSERID, ZEXERCISEID, ZREPS, ZONEREPMAX, ZWEIGHT, ZACHIEVEDAT, '
      'ZCREATEDAT, ZUPDATEDAT) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [recordId, userId, ghostExerciseId, 5, 70.0, 60.0, 0.0, 0.0, 0.0],
    );
  } finally {
    db.dispose();
  }
}

/// (f) 舊庫完全沒有 ZUSERENTITY,但有 body_weight 資料——應補建佔位使用者
/// (name/email 皆為 null),body_weight 保留並掛在該佔位使用者底下。
void _buildNoUserWithBodyWeightDb(String path) {
  final db = sqlite3lib.sqlite3.open(path);
  try {
    db.execute(_syntheticSchema);

    final danglingUserId = _fakeUuidBytes(60); // 從未寫進 ZUSERENTITY(該表本身是空的)
    final bodyWeightId = _fakeUuidBytes(61);

    db.execute(
      'INSERT INTO ZBODYWEIGHTENTITY '
      '(ZID, ZUSERID, ZWEIGHT, ZMEASUREDAT, ZISSYNCED, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [bodyWeightId, danglingUserId, 82.5, 0.0, 0, 0.0, 0.0],
    );
  } finally {
    db.dispose();
  }
}
