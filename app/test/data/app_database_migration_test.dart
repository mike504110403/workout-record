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

    // 斷言 1:既有列一列都不能丟,逐欄比對(含子列)。
    final templatesAfter = await db.select(db.templates).get();
    expect(templatesAfter, hasLength(1));
    final migratedTemplate = templatesAfter.single;
    expect(migratedTemplate.id, templateId);
    expect(migratedTemplate.userId, userId); // userId 保留原值,沒有被清成 null
    expect(migratedTemplate.name, templateName);
    expect(migratedTemplate.descriptionText, templateDescription);
    expect(migratedTemplate.isSystem, isFalse);
    expect(migratedTemplate.createdAt.millisecondsSinceEpoch, createdAtSeconds * 1000);
    expect(migratedTemplate.updatedAt.millisecondsSinceEpoch, updatedAtSeconds * 1000);

    final templateExercisesAfter = await db.select(db.templateExercises).get();
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
  });
}
