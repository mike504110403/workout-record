import 'package:drift/drift.dart';

import '../db/app_database.dart' as db;
import '../models/power_lift_record.dart';

/// 三項力量紀錄的資料存取層。對照 iOS 版
/// `ios/WorkoutRecord/WorkoutRecord/Sources/Repositories/PowerLiftRepository.swift`。
class PowerLiftRecordRepository {
  PowerLiftRecordRepository(this._db);

  final db.AppDatabase _db;

  // MARK: - Create

  Future<PowerLiftRecord> create(PowerLiftRecord record) async {
    await _db.into(_db.powerLiftRecords).insert(record.toCompanion());
    return record;
  }

  // MARK: - Read

  /// 獲取指定用戶的所有三項記錄。
  Future<List<PowerLiftRecord>> getAll(String userId) async {
    final rows = await (_db.select(_db.powerLiftRecords)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm(expression: t.achievedAt, mode: OrderingMode.desc)]))
        .get();
    return rows.map(PowerLiftRecord.fromRow).toList();
  }

  /// 獲取指定三項動作的所有記錄。
  Future<List<PowerLiftRecord>> getRecords(PowerLift lift, String userId) async {
    final rows = await (_db.select(_db.powerLiftRecords)
          ..where((t) => t.userId.equals(userId) & t.lift.equals(lift.value))
          ..orderBy([(t) => OrderingTerm(expression: t.achievedAt, mode: OrderingMode.desc)]))
        .get();
    return rows.map(PowerLiftRecord.fromRow).toList();
  }

  /// 獲取指定三項動作的最佳記錄。
  Future<PowerLiftRecord?> getBestRecord(PowerLift lift, String userId) async {
    final row = await (_db.select(_db.powerLiftRecords)
          ..where((t) => t.userId.equals(userId) & t.lift.equals(lift.value))
          ..orderBy([(t) => OrderingTerm(expression: t.oneRepMax, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : PowerLiftRecord.fromRow(row);
  }

  /// 根據 ID 獲取記錄。
  Future<PowerLiftRecord?> getById(String id) async {
    final row = await (_db.select(_db.powerLiftRecords)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : PowerLiftRecord.fromRow(row);
  }

  // MARK: - Update

  /// 更新三項記錄。
  Future<PowerLiftRecord> update(PowerLiftRecord record) async {
    final rowsAffected =
        await (_db.update(_db.powerLiftRecords)..where((t) => t.id.equals(record.id))).write(
      db.PowerLiftRecordsCompanion(
        weight: Value(record.weight),
        reps: Value(record.reps),
        oneRepMax: Value(record.oneRepMax),
        achievedAt: Value(record.achievedAt),
        note: Value(record.note),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (rowsAffected == 0) {
      throw StateError('記錄不存在: ${record.id}');
    }
    return record;
  }

  // MARK: - Delete

  /// 刪除三項記錄。
  Future<void> delete(String id) async {
    final rowsAffected =
        await (_db.delete(_db.powerLiftRecords)..where((t) => t.id.equals(id))).go();
    if (rowsAffected == 0) {
      throw StateError('記錄不存在: $id');
    }
  }

  /// 刪除指定用戶的所有記錄。
  Future<void> deleteAll(String userId) async {
    await (_db.delete(_db.powerLiftRecords)..where((t) => t.userId.equals(userId))).go();
  }
}
