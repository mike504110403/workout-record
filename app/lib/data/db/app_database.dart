import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'seed_data.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// `drift_flutter` 用 conditional export 在 native 平台接 NativeDatabase、
/// web 平台接 WasmDatabase(見 app/lib/data/db/README.md web 支援章節),
/// 上層(AppDatabase / repositories)不需要為平台分流寫任何 if/else。
///
/// native 端沿用原本檔名/路徑(`<Application Support>/workout_record.db`),
/// 不影響既有(開發中)資料庫檔案位置。
QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'workout_record',
    native: DriftNativeOptions(
      databasePath: () async {
        final dir = await getApplicationSupportDirectory();
        return p.join(dir.path, 'workout_record.db');
      },
    ),
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}

@DriftDatabase(
  tables: [
    Users,
    BodyWeights,
    Workouts,
    WorkoutExercises,
    WorkoutSets,
    Exercises,
    Templates,
    TemplateExercises,
    PersonalRecords,
    UserGoals,
    PowerLiftRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.connection);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await seedIfEmpty();
        },
        // v1 -> v2:Templates.userId 從 NOT NULL 改 nullable(系統模板需要
        // userId = null,見 tables.dart 的註解與
        // .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md)。
        // 用 `alterTable(TableMigration(...))` 做官方建議的「12-step ALTER
        // TABLE」表重建程序——只放鬆約束、沒有改欄名/型別,不需要
        // columnTransformer,既有列逐欄原封複製,一列都不會丟。
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            // ignore: experimental_member_use
            await m.alterTable(TableMigration(templates));
            // db-reviewer 抓到的真實 bug:升級裝置在 alterTable 之前一直
            // 卡在 v1 的 userId NOT NULL 限制,系統模板(userId = null)根本
            // 插不進去,所以升級路徑永遠沒有系統模板可用(實跑升級後
            // isSystem = 1 為 0 筆)。約束放鬆之後,這裡照 onCreate 的路徑
            // 補種——呼叫完整的 `seedIfEmpty()`(db review r2):動作齊全時
            // 與只種模板行為相同(exercises 非空就跳過),但若裝置動作種子
            // 曾缺漏,能先自我修復再種模板,避免「升級成功但模板永久 0 筆
            // 且 user_version 已前進、再也不重試」的死局。冪等 + 容錯
            // (某模板動作名稱找不到只跳過該模板 + log,不讓升級失敗,見
            // seed_data.dart `buildSeedTemplateCompanions` 文件註解)。
            await seedIfEmpty();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// 內建動作庫種子。供 [migration] 的 onCreate 呼叫,也給匯入流程使用
  /// (例如還原舊備份時,確保系統動作庫存在)。
  ///
  /// 去重採「簡單版」:只要目前 isSystem = true 的動作不是空的,就整批跳過
  /// 不再插入。系統動作的穩定鍵是「名稱」而非 id(理由見 seed_data.dart
  /// 開頭的 UUID 策略說明——id 每次安裝都重新隨機產生,無法跨裝置比對),
  /// 因此「已經 seed 過」是判斷是否重複的合理簡化條件;若要做到「單筆
  /// 依名稱比對、增量補齊缺漏的內建動作」則需要更複雜的邏輯,目前不在範圍內。
  Future<void> seedIfEmpty() async {
    final hasSystemExercises = await (select(exercises)
          ..where((t) => t.isSystem.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (hasSystemExercises == null) {
      await batch((b) {
        b.insertAll(exercises, buildSeedExerciseCompanions());
      });
    }

    // 獨立於上面的 exercises 去重判斷之外呼叫——即使 exercises 已經種過
    // (上面不會再插入),模板種子仍要照跑自己的去重檢查,兩者互不影響。
    await _seedSystemTemplatesIfEmpty();
  }

  /// 內建訓練模板種子(5 個系統模板,對照 iOS mock,見 seed_data.dart 開頭
  /// 的完整說明與對應假設申報)。去重邏輯同 exercises:只要已經有
  /// isSystem = true 的模板就整批跳過,不重複插入。
  Future<void> _seedSystemTemplatesIfEmpty() async {
    final hasSystemTemplates = await (select(templates)
          ..where((t) => t.isSystem.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (hasSystemTemplates != null) return;

    // 依 categoryId 排序:kSeedExercises 裡「硬舉」「臉拉」等名稱跨分類重複
    // (見 seed_data.dart 開頭說明),用 categoryId 排序 + putIfAbsent 讓撞名
    // 時穩定保留固定的那一筆(依 SeedCategoryIds 常數順序),不吃 SQL 查詢
    // 順序這種未定義行為。
    final systemExercises = await (select(exercises)
          ..where((t) => t.isSystem.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.categoryId)]))
        .get();
    final exerciseIdByName = <String, String>{};
    for (final exercise in systemExercises) {
      exerciseIdByName.putIfAbsent(exercise.name, () => exercise.id);
    }

    final seedResult = buildSeedTemplateCompanions(exerciseIdByName);
    await batch((b) {
      b.insertAll(templates, seedResult.templates);
      b.insertAll(templateExercises, seedResult.templateExercises);
    });
  }

  /// 帳號隔離用:清空全部 11 張表 + 重種系統動作庫,把本機 Drift 重置成
  /// 「剛完成 onCreate、還沒有任何使用者資料」的狀態,交給下一個帳號從零
  /// 開始(換帳號登入、使用者確認清除後呼叫,見
  /// `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md`)。名字
  /// 特意不叫 `clearAllTables`——這個方法的契約不只是「清空」,還包含
  /// 「清完立刻重種系統動作庫」,呼叫端不需要另外記得補呼叫 [seedIfEmpty]。
  ///
  /// 刪除順序手動排成「children 先於 parents」,不靠切換
  /// `PRAGMA foreign_keys`——SQLite 規定該 pragma 在交易中是 no-op(不在交易
  /// 裡切又抓不到清空這段操作結尾的時機關掉),排順序才是可攜、
  /// native/web 兩平台通用的做法,且不需要碰任何平台特定 API。
  ///
  /// 清完立刻呼叫 [seedIfEmpty] 補回系統動作庫——那是 App 共用的參照資料
  /// (`isSystem = true`,`userId` 為 null),不屬於任何帳號,換帳號不該讓
  /// 新使用者連動作庫都是空的(等同於全新安裝後的 onCreate 行為)。
  Future<void> resetForNewOwner() async {
    await transaction(() async {
      await delete(workoutSets).go();
      await delete(workoutExercises).go();
      await delete(templateExercises).go();
      await delete(personalRecords).go();
      await delete(workouts).go();
      await delete(templates).go();
      await delete(userGoals).go();
      await delete(powerLiftRecords).go();
      await delete(bodyWeights).go();
      await delete(exercises).go();
      await delete(users).go();

      await seedIfEmpty();
    });
  }
}
