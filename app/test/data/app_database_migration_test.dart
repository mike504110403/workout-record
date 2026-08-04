// schemaVersion 1 -> 2 migration 測試:Templates.userId 從 NOT NULL 改
// nullable(見 lib/data/db/tables.dart 的註解與
// .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md)。
//
// 手刻 v1 schema 的真實 sqlite 檔案(手法對照
// test/migration/coredata_importer_test.dart 用 package:sqlite3 直接開檔、
// 手寫 CREATE TABLE 的既有慣例)——先塞一筆含 userId 的 templates 列與一筆
// template_exercises 子列,再用 AppDatabase.forTesting 開這個檔案觸發
// onUpgrade(1 -> 2),斷言:
//   1. 既有列一列都不能丟,逐欄比對(含子列)。
//   2. 新 schema 允許插入 userId = null 的列(系統模板需要的能力)。
//   3. FK 約束仍然生效(塞不存在的 userId 仍被擋)。
//
// 參照值(v1 fixture 塞進去的原始資料)手算獨立宣告在測試開頭,不透過
// migration 或 seed 相關程式碼產生,純粹是「塞什麼、期待原封不動拿回什麼」
// 的地面真相(ground truth)。
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;
import 'package:workout_record/data/db/app_database.dart';

const _v1Schema = '''
CREATE TABLE users (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT,
  email TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE exercises (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  name_en TEXT,
  category_id TEXT NOT NULL,
  type TEXT NOT NULL,
  movement_pattern TEXT,
  primary_muscle_group TEXT,
  description_text TEXT,
  video_u_r_l TEXT,
  image_u_r_l TEXT,
  is_system INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  user_id TEXT REFERENCES users (id),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE templates (
  id TEXT NOT NULL PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users (id),
  name TEXT NOT NULL,
  description_text TEXT,
  is_system INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX idx_templates_user_id ON templates (user_id);
CREATE TABLE template_exercises (
  id TEXT NOT NULL PRIMARY KEY,
  template_id TEXT NOT NULL REFERENCES templates (id) ON DELETE CASCADE,
  exercise_id TEXT NOT NULL REFERENCES exercises (id),
  order_index INTEGER NOT NULL DEFAULT 0,
  suggested_sets INTEGER,
  suggested_reps INTEGER
);
''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('app_database_migration_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
      'v1 -> v2:既有 templates 列(含 userId)與其 template_exercises 子列'
      '完整保留,新 schema 允許 userId = null,FK 約束仍生效', () async {
    final dbPath = p.join(tempDir.path, 'v1_fixture.sqlite');

    // ---- 參照值(地面真相,不經任何 migration/seed 程式碼產生) ----
    const userId = 'v1-user';
    const exerciseId = 'v1-exercise';
    const templateId = 'v1-template';
    const templateExerciseId = 'v1-template-exercise';
    const templateName = '既有的個人模板';
    const templateDescription = '升級前就存在的模板,不能因為 migration 消失';
    final createdAtSeconds = DateTime.utc(2024, 3, 1, 8).millisecondsSinceEpoch ~/ 1000;
    final updatedAtSeconds = DateTime.utc(2024, 3, 2, 9).millisecondsSinceEpoch ~/ 1000;

    // ---- 手刻 v1 schema 的真實 sqlite 檔案 ----
    final rawDb = sqlite3lib.sqlite3.open(dbPath);
    try {
      rawDb.execute(_v1Schema);
      rawDb.execute('PRAGMA user_version = 1;');

      rawDb.execute(
        'INSERT INTO users (id, name, email, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [userId, 'V1 User', 'v1@example.com', createdAtSeconds, updatedAtSeconds],
      );
      rawDb.execute(
        'INSERT INTO exercises '
        '(id, name, category_id, type, is_system, is_active, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [exerciseId, '槓鈴臥推', 'cat-chest', 'free_weight', 0, 1, createdAtSeconds, updatedAtSeconds],
      );
      // 這是本測試的核心參照物:升級前就存在、userId 有值的一筆模板。
      rawDb.execute(
        'INSERT INTO templates '
        '(id, user_id, name, description_text, is_system, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [templateId, userId, templateName, templateDescription, 0, createdAtSeconds, updatedAtSeconds],
      );
      rawDb.execute(
        'INSERT INTO template_exercises '
        '(id, template_id, exercise_id, order_index, suggested_sets, suggested_reps) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [templateExerciseId, templateId, exerciseId, 0, 4, 8],
      );
    } finally {
      rawDb.dispose();
    }

    // ---- 開啟觸發 onUpgrade(1 -> 2) ----
    final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
    addTearDown(db.close);

    // 斷言 1:既有列一列都不能丟,逐欄比對(含子列)。斷言鎖定「非系統
    // 模板」——onUpgrade 走 seedIfEmpty()(db review r2 自癒改法),這個
    // fixture 的 exercises 是空的,升級時會先自癒種回 66 筆動作、連帶種出
    // 5 筆系統模板,那是預期行為,不影響本測試守的「既有使用者列保留」。
    final templatesAfter = await (db.select(db.templates)
          ..where((t) => t.isSystem.equals(false)))
        .get();
    expect(templatesAfter, hasLength(1));
    final migratedTemplate = templatesAfter.single;
    expect(migratedTemplate.id, templateId);
    expect(migratedTemplate.userId, userId); // userId 保留原值,沒有被清成 null
    expect(migratedTemplate.name, templateName);
    expect(migratedTemplate.descriptionText, templateDescription);
    expect(migratedTemplate.isSystem, isFalse);
    expect(migratedTemplate.createdAt.millisecondsSinceEpoch, createdAtSeconds * 1000);
    expect(migratedTemplate.updatedAt.millisecondsSinceEpoch, updatedAtSeconds * 1000);

    final templateExercisesAfter = await (db.select(db.templateExercises)
          ..where((te) => te.templateId.equals(templateId)))
        .get();
    expect(templateExercisesAfter, hasLength(1));
    final migratedTemplateExercise = templateExercisesAfter.single;
    expect(migratedTemplateExercise.id, templateExerciseId);
    expect(migratedTemplateExercise.templateId, templateId);
    expect(migratedTemplateExercise.exerciseId, exerciseId);
    expect(migratedTemplateExercise.orderIndex, 0);
    expect(migratedTemplateExercise.suggestedSets, 4);
    expect(migratedTemplateExercise.suggestedReps, 8);

    // 斷言 2:新 schema 允許插入 userId = null 的列(系統模板需要的能力)。
    final now = DateTime.now();
    await db.into(db.templates).insert(
          TemplatesCompanion.insert(
            id: 'system-template-after-migration',
            userId: const Value(null),
            name: '系統模板(migration 後新增)',
            isSystem: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final systemTemplate = await (db.select(db.templates)
          ..where((t) => t.id.equals('system-template-after-migration')))
        .getSingle();
    expect(systemTemplate.userId, isNull);
    expect(systemTemplate.isSystem, isTrue);

    // 斷言 3:FK 約束仍然生效——塞不存在的 userId 仍被擋(具體比對是
    // FOREIGN KEY 違規訊息,不是隨便什麼例外都算過——這樣如果 migration
    // 不小心把 FK 弄丟,這裡才會真的紅,而不是隨便抓到別的錯誤就矇混過關)。
    await expectLater(
      db.into(db.templates).insert(
            TemplatesCompanion.insert(
              id: 'dangling-user-template',
              userId: const Value('does-not-exist-user-id'),
              name: '不該插得進去的模板',
              createdAt: now,
              updatedAt: now,
            ),
          ),
      throwsA(
        isA<sqlite3lib.SqliteException>().having(
          (e) => e.toString(),
          'message',
          contains('FOREIGN KEY constraint failed'),
        ),
      ),
    );

    // 斷言 4(minor,db-reviewer 補件):alterTable 的「重新建立關聯 index」
    // 那一步真的把 v1 就存在的 idx_templates_user_id 帶過來,不是巧合對得上
    // 而已。
    final indexRows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_templates_user_id'",
        )
        .get();
    expect(indexRows, hasLength(1));

    // 斷言 5(minor):schemaVersion 真的落地成 2,不是程式碼裡寫 2 但
    // PRAGMA user_version 沒跟著更新這種半吊子狀態。
    final userVersionRow = await db.customSelect('PRAGMA user_version').getSingle();
    expect(userVersionRow.read<int>('user_version'), 2);
  });

  group('db-M1:升級裝置(from < 2)補種系統模板', () {
    /// 建立一個「exercises 表已有既有系統動作、templates 是空的」v1
    /// fixture——模擬升級裝置本來就有系統動作,但因為 v1 的
    /// `Templates.userId` NOT NULL,系統模板(userId = null)從來沒能插進去
    /// 這個真實情境(db-reviewer 實跑升級後 isSystem = 1 為 0 筆抓到的
    /// bug)。[existingExerciseNames] 只需要列出這次驗證用得到的名稱——
    /// `buildSeedTemplateCompanions` 只在乎 exerciseIdByName 裡有沒有它要
    /// 的名稱,不必真的塞滿 66 筆。
    void buildV1FixtureWithExercises(String path, List<String> existingExerciseNames) {
      final rawDb = sqlite3lib.sqlite3.open(path);
      try {
        rawDb.execute(_v1Schema);
        rawDb.execute('PRAGMA user_version = 1;');
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        for (var i = 0; i < existingExerciseNames.length; i++) {
          rawDb.execute(
            'INSERT INTO exercises '
            '(id, name, category_id, type, is_system, is_active, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            ['v1-exercise-$i', existingExerciseNames[i], 'cat-x', 'free_weight', 1, 1, now, now],
          );
        }
      } finally {
        rawDb.dispose();
      }
    }

    /// kSeedTemplates(seed_data.dart)5 個模板實際用到的全部動作名稱
    /// (去重,15 個)——手動抄錄,獨立於 seed_data.dart 本身。
    const allTemplateExerciseNames = [
      '槓鈴臥推', '上斜啞鈴臥推', '肩推', '側平舉', '三頭下壓',
      '硬舉', '引體向上', '槓鈴划船', '坐姿划船', '槓鈴彎舉',
      '深蹲', '羅馬尼亞硬舉', '腿推機', '腿彎舉', '提踵',
    ];

    test('裝置既有動作齊全 -> 升級後補種 5 個系統模板 + 25 個 template_exercises', () async {
      final dbPath = p.join(tempDir.path, 'v1_upgrade_full.sqlite');
      buildV1FixtureWithExercises(dbPath, allTemplateExerciseNames);

      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final systemTemplates =
          await (db.select(db.templates)..where((t) => t.isSystem.equals(true))).get();
      expect(systemTemplates, hasLength(5));

      final systemTemplateIds = systemTemplates.map((t) => t.id).toSet();
      final templateExercises = await db.select(db.templateExercises).get();
      final systemTemplateExercises =
          templateExercises.where((te) => systemTemplateIds.contains(te.templateId)).toList();
      expect(systemTemplateExercises, hasLength(25));
    });

    test(
        '裝置既有動作缺一筆(側平舉,只有 PPL - Push 用到)-> 升級仍成功,'
        '只有那個模板被跳過,不 throw、不讓升級/開機失敗', () async {
      final dbPath = p.join(tempDir.path, 'v1_upgrade_missing_one.sqlite');
      final namesMissingLateralRaise =
          allTemplateExerciseNames.where((name) => name != '側平舉').toList();
      buildV1FixtureWithExercises(dbPath, namesMissingLateralRaise);

      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final systemTemplates =
          await (db.select(db.templates)..where((t) => t.isSystem.equals(true))).get();
      expect(
        systemTemplates,
        hasLength(4),
        reason: '缺「側平舉」的 PPL - Push 應該被整筆跳過,其餘 4 個模板用到的名稱都在,正常種完',
      );
      expect(systemTemplates.map((t) => t.name), isNot(contains('PPL - Push (推)')));

      final systemTemplateIds = systemTemplates.map((t) => t.id).toSet();
      final templateExercises = await db.select(db.templateExercises).get();
      final systemTemplateExercises =
          templateExercises.where((te) => systemTemplateIds.contains(te.templateId)).toList();
      expect(systemTemplateExercises, hasLength(20));
    });
  });
}
