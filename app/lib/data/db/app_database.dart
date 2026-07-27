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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await seedIfEmpty();
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
    if (hasSystemExercises != null) return;

    await batch((b) {
      b.insertAll(exercises, buildSeedExerciseCompanions());
    });
  }
}
