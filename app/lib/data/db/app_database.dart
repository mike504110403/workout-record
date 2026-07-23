import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'seed_data.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// 手動 NativeDatabase(不能用 drift_flutter,見 app/lib/data/db/README.md 版本限制)。
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'workout_record.db'));
    return NativeDatabase.createInBackground(file);
  });
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
