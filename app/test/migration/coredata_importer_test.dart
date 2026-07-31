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
// (舊檔不存在 / 壞檔 / optional 欄位為 NULL / rpe·restSeconds 0→NULL)、
// 連續失敗 3 次後標記 permanently failed + 手動重試、tableCounts 落地量
// 對照 skippedCounts(spec 4.5/4.6 節)。
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;
import 'package:workout_record/data/db/app_database.dart';
import 'package:workout_record/data/migration/coredata_importer.dart';
import 'package:workout_record/data/migration/import_log.dart';

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

  /// 用隨機 bytes 冒充 .sqlite 檔,模擬「打不開的壞舊庫」——連續失敗上限
  /// 與 retryAfterPermanentFailure 兩組測試都要用到。
  Directory buildBadSupportDir(String name) {
    final dir = Directory(p.join(tempDir.path, name))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'WorkoutRecord.sqlite'))
        .writeAsBytesSync(List<int>.generate(256, (i) => i % 256));
    return dir;
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
    test('各表落地筆數與 fixture 來源筆數逐表一致(exercises 表因 66 筆'
        '系統動作全部去重合併到既有 seed,落地量為 0,見 dedupedCounts)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.skipped, isFalse);
      final expectedLanded = Map<String, int>.from(fixtureSourceCounts())
        ..['exercises'] = 0;
      expect(result.tableCounts, equals(expectedLanded));
      expect(result.dedupedCounts['exercises'], 66);
      expect(result.createdPlaceholders['users'] ?? 0, 0);
      expect(result.createdPlaceholders['exercises'] ?? 0, 0);
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
      // 舊庫 ZEXERCISEENTITY 本身是空的(見 fixture 文件註解),落地的這 1
      // 筆 exercise 完全是補建的佔位,不是任何來源列。
      expect(result.createdPlaceholders['exercises'], 1);
      expect(result.tableCounts['exercises'], 1);
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
      // 同上——舊庫 ZEXERCISEENTITY 是空的,落地的這 1 筆 exercise 完全是
      // 補建的佔位。
      expect(result.createdPlaceholders['exercises'], 1);
      expect(result.tableCounts['exercises'], 1);
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
      // 舊庫 ZUSERENTITY 是空的,落地的這 1 筆 user 完全是補建的佔位;
      // body_weight 則有 1 筆真正的來源資料落地。
      expect(result.createdPlaceholders['users'], 1);
      expect(result.tableCounts['users'], 1);
      expect(result.tableCounts['body_weights'], 1);
    });

    test('template_exercise 的 exerciseId 在舊庫不存在 → 該列被 skip'
        '(對照 workout_exercises:那邊會補建佔位動作,這裡不會)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir =
          Directory(p.join(tempDir.path, 'missing_exercise_te_support'))
            ..createSync(recursive: true);
      _buildMissingExerciseForTemplateExerciseDb(
        p.join(supportDir.path, 'WorkoutRecord.sqlite'),
      );
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      final templateExercises = await db.select(db.templateExercises).get();
      expect(templateExercises, isEmpty);

      // 不像 workout_exercises,這裡不會補建佔位動作——67 筆系統種子動作
      // 之外沒有任何新增的自訂/佔位動作。
      final customOrPlaceholderExercises =
          (await db.select(db.exercises).get())
              .where((e) => !e.isSystem)
              .toList();
      expect(customOrPlaceholderExercises, isEmpty);

      expect(
        result.warnings.any(
          (w) => w.contains('[template_exercises]') && w.contains('未對到任何動作'),
        ),
        isTrue,
      );
      expect(result.tableCounts['template_exercises'], 0);
      expect(result.skippedCounts['template_exercises'], 1);
    });
  });

  group('CoreDataImporter - 連續失敗上限與手動重試(spec 4.6 節)', () {

    test('連續失敗 3 次後標記 permanently failed,第 4 次直接 skip 不再嘗試開檔', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer =
          importerWithSupportDir(buildBadSupportDir('retry_limit_support'));

      for (var i = 1; i <= 3; i++) {
        final result = await importer.importIfNeeded(db);
        expect(result.success, isFalse);
        // 第 3 次剛好跨過上限——這次呼叫本身就要誠實回報 permanentlyFailed
        // = true,呼叫端(ImportRetryTile)不需要另外讀 prefs 才知道已達
        // 上限(major 1:狀態誠實)。
        expect(
          result.permanentlyFailed,
          i >= 3,
          reason: i < 3 ? '第 $i 次還沒到上限' : '第 3 次剛好跨過上限,回傳就該誠實反映',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(kCoreDataImportAttemptsKey), i);
      }

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kCoreDataImportFailedPermanentlyKey), isTrue);

      final fourth = await importer.importIfNeeded(db);
      expect(fourth.skipped, isTrue);
      expect(fourth.success, isFalse);
      expect(fourth.permanentlyFailed, isTrue);
      // 短路後不再嘗試開檔,attempts 計數維持在 3,不會變成 4。
      expect(prefs.getInt(kCoreDataImportAttemptsKey), 3);
    });

    test('手動重試:清掉旗標與計數、修好舊檔後可以重新成功匯入', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = buildBadSupportDir('retry_fix_support');
      final importer = importerWithSupportDir(supportDir);

      for (var i = 0; i < 3; i++) {
        await importer.importIfNeeded(db);
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kCoreDataImportFailedPermanentlyKey), isTrue);

      // 「修好」:把壞檔換成真正的 fixture(同一個 supportDir 物件,
      // importer 本身不需要重建)。
      File(p.join(supportDir.path, 'WorkoutRecord.sqlite')).deleteSync();
      for (final suffix in ['', '-wal', '-shm']) {
        final source = File('$_fixtureDbPath$suffix');
        if (source.existsSync()) {
          source.copySync(p.join(supportDir.path, 'WorkoutRecord.sqlite$suffix'));
        }
      }

      // 對應 ImportRetryTile._retry() 的行為:先清旗標與計數,再重新呼叫
      // importIfNeeded()。
      await prefs.setBool(kCoreDataImportFailedPermanentlyKey, false);
      await prefs.setInt(kCoreDataImportAttemptsKey, 0);

      final retried = await importer.importIfNeeded(db);

      expect(retried.success, isTrue, reason: retried.errorMessage);
      expect(retried.skipped, isFalse);
      expect(prefs.getInt(kCoreDataImportAttemptsKey), 0);
      expect(prefs.getBool(kCoreDataImportCompletedKey), isTrue);
      expect(prefs.getBool(kCoreDataImportFailedPermanentlyKey), isFalse);
    });
  });

  group('CoreDataImporter.retryAfterPermanentFailure(spec 4.6 節手動重試,'
      'major 1:狀態誠實)', () {
    test('重試成功:清掉旗標與計數,回傳成功結果', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = buildBadSupportDir('retry_success_support');
      final importer = importerWithSupportDir(supportDir);

      // 先失敗 3 次,進入 permanently failed 狀態。
      for (var i = 0; i < 3; i++) {
        await importer.importIfNeeded(db);
      }
      final prefsBefore = await SharedPreferences.getInstance();
      expect(prefsBefore.getBool(kCoreDataImportFailedPermanentlyKey), isTrue);

      // 「修好」:把壞檔換成真正的 fixture。
      File(p.join(supportDir.path, 'WorkoutRecord.sqlite')).deleteSync();
      for (final suffix in ['', '-wal', '-shm']) {
        final source = File('$_fixtureDbPath$suffix');
        if (source.existsSync()) {
          source.copySync(p.join(supportDir.path, 'WorkoutRecord.sqlite$suffix'));
        }
      }

      final result = await importer.retryAfterPermanentFailure(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.skipped, isFalse);
      expect(result.permanentlyFailed, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kCoreDataImportFailedPermanentlyKey), isFalse);
      expect(prefs.getInt(kCoreDataImportAttemptsKey), 0);
      expect(prefs.getBool(kCoreDataImportCompletedKey), isTrue);
    });

    test('重試仍失敗:旗標與計數立刻復原為「已達上限」,不吃掉自動重試的 3 次'
        '額度——回傳結果的 permanentlyFailed 誠實反映這個狀態,呼叫端不用'
        '另外讀 prefs', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer =
          importerWithSupportDir(buildBadSupportDir('retry_still_bad_support'));

      for (var i = 0; i < 3; i++) {
        await importer.importIfNeeded(db);
      }
      final prefsBefore = await SharedPreferences.getInstance();
      expect(prefsBefore.getBool(kCoreDataImportFailedPermanentlyKey), isTrue);

      // 壞檔沒有被修好,重試理應仍然失敗。
      final result = await importer.retryAfterPermanentFailure(db);

      expect(result.success, isFalse);
      expect(result.skipped, isFalse);
      expect(result.permanentlyFailed, isTrue);

      final prefs = await SharedPreferences.getInstance();
      // 沒有真的要求使用者再連續點 3 次才會又看到手動重試按鈕——一次失敗
      // 就立刻復原回「已達上限」的狀態。
      expect(prefs.getBool(kCoreDataImportFailedPermanentlyKey), isTrue);
      expect(prefs.getInt(kCoreDataImportAttemptsKey), 3);

      // 緊接著再跑一次 importIfNeeded 應該直接短路 skip,不會又去開壞檔
      // (attempts 沒有被吃掉,不需要真的再失敗 3 次)。
      final next = await importer.importIfNeeded(db);
      expect(next.skipped, isTrue);
      expect(next.permanentlyFailed, isTrue);
    });
  });

  group('CoreDataImporter - 「已 commit 未標旗」窗口(spec 4.6 節,major 3)', () {
    test('資料已在 Drift(如崩潰在寫完成旗標前)→ 重跑偵測到既有 id,'
        '不撞主鍵、直接補標完成', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = Directory(p.join(tempDir.path, 'already_landed_support'))
        ..createSync(recursive: true);
      _buildSyntheticOldDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      final first = await importer.importIfNeeded(db);
      expect(first.success, isTrue, reason: first.errorMessage);
      expect(first.skipped, isFalse);

      // 模擬「transaction 已 commit,但寫完成旗標前 App 被中斷」:清掉完成
      // 旗標,資料本身(Drift)完全不動。
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kCoreDataImportCompletedKey, false);

      final second = await importer.importIfNeeded(db);

      expect(second.success, isTrue, reason: second.errorMessage);
      expect(second.skipped, isTrue);
      expect(second.skipReason, ImportSkipReason.alreadyLanded);
      // 沒有撞主鍵:workouts 表依然只有合成庫的 1 筆(不是丟例外,也不是
      // 重複匯入出 2 筆)。
      expect(await db.select(db.workouts).get(), hasLength(1));
      expect(prefs.getBool(kCoreDataImportCompletedKey), isTrue);
    });

    test('Drift 有使用者自建資料,但沒有任何舊庫 id 存在其中 → 不誤判成'
        '已落地,照常跑一次正常匯入', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      // 使用者在匯入前已經自己開始記錄了一筆新訓練,userId/workoutId 都是
      // 跟舊庫毫無關係的新 UUID。
      const userCreatedUserId = '11111111-1111-1111-1111-111111111111';
      await db.into(db.users).insert(
            UsersCompanion.insert(
              id: userCreatedUserId,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      await db.into(db.workouts).insert(
            WorkoutsCompanion.insert(
              id: '22222222-2222-2222-2222-222222222222',
              userId: userCreatedUserId,
              startedAt: DateTime.now(),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      final supportDir =
          Directory(p.join(tempDir.path, 'user_created_before_import_support'))
            ..createSync(recursive: true);
      _buildSyntheticOldDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      // 不是誤判成 already landed——是正常跑了一次真的匯入。
      expect(result.skipped, isFalse);
      // 合成庫的 1 筆訓練被正常匯入,連同使用者自建的那 1 筆,共 2 筆。
      expect(await db.select(db.workouts).get(), hasLength(2));
    });

    test('多表多樣本①:舊庫無 user、無 workout,只有 body_weight,且該'
        'body_weight 已在 Drift → 命中(抽樣退到 body_weights 表才找到樣本)',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir =
          Directory(p.join(tempDir.path, 'already_landed_bw_only_support'))
            ..createSync(recursive: true);
      _buildNoUserWithBodyWeightDb(
        p.join(supportDir.path, 'WorkoutRecord.sqlite'),
      );
      final importer = importerWithSupportDir(supportDir);

      final first = await importer.importIfNeeded(db);
      expect(first.success, isTrue, reason: first.errorMessage);
      expect(first.skipped, isFalse);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kCoreDataImportCompletedKey, false);

      final second = await importer.importIfNeeded(db);

      expect(second.success, isTrue, reason: second.errorMessage);
      expect(second.skipped, isTrue);
      expect(second.skipReason, ImportSkipReason.alreadyLanded);
      // 沒有撞主鍵:body_weight 依然只有合成庫的 1 筆。
      expect(await db.select(db.bodyWeights).get(), hasLength(1));
    });

    test('多表多樣本②:舊庫 workouts 的抽樣列已被使用者刪掉,但 users 仍在'
        'Drift → 命中(修正前只抽 workouts、抽樣落空就直接 return false,'
        '此測試修正前必須紅——重跑會因 users 主鍵衝突而失敗)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir =
          Directory(p.join(tempDir.path, 'workout_deleted_support'))
            ..createSync(recursive: true);
      _buildSyntheticOldDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      final first = await importer.importIfNeeded(db);
      expect(first.success, isTrue, reason: first.errorMessage);

      // 模擬使用者事後把這筆訓練刪掉了(但沒有動使用者本身)——依 FK
      // cascade 順序刪:sets -> workout_exercises -> workouts。
      await db.delete(db.workoutSets).go();
      await db.delete(db.workoutExercises).go();
      await db.delete(db.workouts).go();
      expect(await db.select(db.workouts).get(), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kCoreDataImportCompletedKey, false);

      final second = await importer.importIfNeeded(db);

      expect(second.success, isTrue, reason: second.errorMessage);
      expect(second.skipped, isTrue);
      expect(second.skipReason, ImportSkipReason.alreadyLanded);
      // 依然沒有撞主鍵:users 表只有合成庫的 1 筆,workouts 維持刪除後的
      // 空狀態(沒有被誤重跑一次匯入)。
      expect(await db.select(db.users).get(), hasLength(1));
      expect(await db.select(db.workouts).get(), isEmpty);
    });
  });

  group('CoreDataImporter - 核帳快照(spec 4.5 節,minor:alreadyLanded 也要留痕)',
      () {
    test('成功匯入時,核帳快照存進 SharedPreferences 且與 Drift 實際筆數一致',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      final result = await importer.importIfNeeded(db);
      expect(result.success, isTrue, reason: result.errorMessage);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(kCoreDataImportVerifiedCountsKey);
      expect(stored, isNotNull);
      final verifiedCounts =
          (jsonDecode(stored!) as Map<String, dynamic>).cast<String, int>();
      // exercises 落地量是 0(全部去重合併到既有種子),但核帳快照是「Drift
      // 現有筆數」,兩者不是同一個數字——快照應該看得到那 66 筆既有種子。
      expect(verifiedCounts['exercises'], greaterThan(0));
      expect(
        verifiedCounts['exercises'],
        (await db.select(db.exercises).get()).length,
      );
      expect(
        verifiedCounts['workouts'],
        (await db.select(db.workouts).get()).length,
      );
    });

    test('alreadyLanded 命中時,即使沒有 tableCounts 也照樣存核帳快照', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir =
          Directory(p.join(tempDir.path, 'verified_counts_already_landed'))
            ..createSync(recursive: true);
      _buildSyntheticOldDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      await importer.importIfNeeded(db);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kCoreDataImportCompletedKey, false);

      final second = await importer.importIfNeeded(db);
      expect(second.skipReason, ImportSkipReason.alreadyLanded);
      // alreadyLanded 的 ImportResult 本身沒有 tableCounts,但快照仍然要有。
      expect(second.tableCounts, isEmpty);

      final stored = prefs.getString(kCoreDataImportVerifiedCountsKey);
      expect(stored, isNotNull);
      final verifiedCounts =
          (jsonDecode(stored!) as Map<String, dynamic>).cast<String, int>();
      expect(verifiedCounts['workouts'], 1);
      expect(verifiedCounts['users'], 1);
    });
  });

  group('CoreDataImporter - 統計口徑:tableCounts 落地量 vs skippedCounts(spec 4.5 節)', () {
    test('沒有孤兒的真實 fixture:三張易孤兒表的 skippedCounts 皆為 0,'
        'tableCounts 為落地量(exercises 因全數去重為 0,其餘表與來源筆數'
        '相等)', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final importer = importerWithSupportDir(copyFixtureAsOldAppSupportDir());

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.skippedCounts['template_exercises'], 0);
      expect(result.skippedCounts['workout_exercises'], 0);
      expect(result.skippedCounts['workout_sets'], 0);
      final expectedLanded = Map<String, int>.from(fixtureSourceCounts())
        ..['exercises'] = 0;
      expect(result.tableCounts, equals(expectedLanded));

      // 成功匯入的落地量摘要(連同 skippedCounts/dedupedCounts/
      // createdPlaceholders)也會存進 SharedPreferences(spec 4.5 節)。
      final prefs = await SharedPreferences.getInstance();
      final storedTableCounts = prefs.getString(kCoreDataImportTableCountsKey);
      expect(storedTableCounts, isNotNull);
      expect(
        jsonDecode(storedTableCounts!) as Map<String, dynamic>,
        equals(result.tableCounts),
      );
      final storedSkippedCounts =
          prefs.getString(kCoreDataImportSkippedCountsKey);
      expect(storedSkippedCounts, isNotNull);
      expect(
        jsonDecode(storedSkippedCounts!) as Map<String, dynamic>,
        equals(result.skippedCounts),
      );
      final storedDedupedCounts =
          prefs.getString(kCoreDataImportDedupedCountsKey);
      expect(storedDedupedCounts, isNotNull);
      expect(
        jsonDecode(storedDedupedCounts!) as Map<String, dynamic>,
        equals(result.dedupedCounts),
      );
    });

    test('workout_exercise 孤兒 skip 時:tableCounts 只算落地筆數,'
        'skippedCounts 另外記錄被略過的孤兒數', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir =
          Directory(p.join(tempDir.path, 'counts_orphan_we_support'))
            ..createSync(recursive: true);
      _buildOrphanWorkoutExerciseDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      // fixture 有 2 筆 workout_exercise 來源(1 有效 + 1 孤兒),落地量只
      // 算成功寫入的 1 筆,不能拿「讀到的筆數」(2)當作零遺失的證據。
      expect(result.tableCounts['workout_exercises'], 1);
      expect(result.skippedCounts['workout_exercises'], 1);
      // 孤兒 workout_exercise 底下的 set 隨其父列一併略過:來源 2 筆,
      // 落地 1 筆。
      expect(result.tableCounts['workout_sets'], 1);
      expect(result.skippedCounts['workout_sets'], 1);
    });

    test('template_exercise 孤兒 skip 時:tableCounts 只算落地筆數,'
        'skippedCounts 另外記錄被略過的孤兒數', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir =
          Directory(p.join(tempDir.path, 'counts_orphan_te_support'))
            ..createSync(recursive: true);
      _buildOrphanTemplateExerciseDb(p.join(supportDir.path, 'WorkoutRecord.sqlite'));
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);

      expect(result.success, isTrue, reason: result.errorMessage);
      expect(result.tableCounts['template_exercises'], 1);
      expect(result.skippedCounts['template_exercises'], 1);
    });
  });

  group('CoreDataImporter - 本地 log(spec 4.6 節,不只靠 debugPrint)', () {
    File logFileFor(Directory supportDir) =>
        File(p.join(supportDir.path, 'logs', 'import.log'));

    test('匯入成功時,log 檔案追加一行含 tableCounts 的摘要', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = copyFixtureAsOldAppSupportDir();
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);
      expect(result.success, isTrue, reason: result.errorMessage);

      final logFile = logFileFor(supportDir);
      expect(logFile.existsSync(), isTrue);
      final content = logFile.readAsStringSync();
      expect(content, contains('匯入成功'));
      expect(content, contains('tableCounts'));
    });

    test('匯入失敗時,log 檔案追加一行含錯誤訊息', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final supportDir = Directory(p.join(tempDir.path, 'log_bad_support'))
        ..createSync(recursive: true);
      File(p.join(supportDir.path, 'WorkoutRecord.sqlite'))
          .writeAsBytesSync(List<int>.generate(256, (i) => i % 256));
      final importer = importerWithSupportDir(supportDir);

      final result = await importer.importIfNeeded(db);
      expect(result.success, isFalse);

      final logFile = logFileFor(supportDir);
      expect(logFile.existsSync(), isTrue);
      final content = logFile.readAsStringSync();
      expect(content, contains('匯入失敗'));
      // 「進行到:XXX」記錄失敗當下卡在哪個階段(見 _CurrentStepHolder),
      // 不只是丟一堆 stacktrace 讓人猜是哪一步壞的。
      expect(content, contains('進行到'));
    });
  });

  group('truncateForImportLog - 截斷邊界(500/501 字元)', () {
    test('剛好 500 字元不截斷', () {
      final message = 'a' * kImportLogMaxMessageLength;
      final result = truncateForImportLog(message);

      expect(result, message);
      expect(result, isNot(contains('截斷')));
    });

    test('501 字元(剛超過上限 1 個字元)開始截斷', () {
      final message = 'a' * (kImportLogMaxMessageLength + 1);
      final result = truncateForImportLog(message);

      expect(result, startsWith('a' * kImportLogMaxMessageLength));
      expect(result, contains('截斷'));
      expect(result, contains('原始長度 ${kImportLogMaxMessageLength + 1} 字元'));
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

/// (g) template_exercise.exerciseId 在舊庫的 ZEXERCISEENTITY 中完全不存在
/// (該表本身是空的)——對照 (d) `_buildMissingExerciseForWorkoutExerciseDb`:
/// workout_exercises 遇到同樣情況會補建佔位動作,但 template_exercises 的
/// 結構層孤兒防護是直接略過整列(見 coredata_importer_io.dart
/// `_importTemplateExercises`)——模板項本身沒有動作身分即無意義,且它不是
/// 訓練歷史,略過只損失該筆,不需要補建佔位動作。
void _buildMissingExerciseForTemplateExerciseDb(String path) {
  final db = sqlite3lib.sqlite3.open(path);
  try {
    db.execute(_syntheticSchema);

    final userId = _fakeUuidBytes(70);
    final templateId = _fakeUuidBytes(71);
    final ghostExerciseId = _fakeUuidBytes(72); // 從未寫進 ZEXERCISEENTITY
    final templateExerciseId = _fakeUuidBytes(73);

    db.execute(
      'INSERT INTO ZUSERENTITY (ZID, ZNAME, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?)',
      [userId, 'Synthetic User', 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZTEMPLATEENTITY '
      '(ZID, ZUSERID, ZNAME, ZISSYSTEM, ZCREATEDAT, ZUPDATEDAT) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [templateId, userId, 'Ghost Exercise Template', 0, 0.0, 0.0],
    );
    db.execute(
      'INSERT INTO ZTEMPLATEEXERCISEENTITY '
      '(ZID, ZTEMPLATEID, ZEXERCISEID, ZORDERINDEX, ZSUGGESTEDSETS, '
      'ZSUGGESTEDREPS) VALUES (?, ?, ?, ?, ?, ?)',
      [templateExerciseId, templateId, ghostExerciseId, 0, 3, 8],
    );
  } finally {
    db.dispose();
  }
}
