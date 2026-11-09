import 'package:drift/drift.dart';

import '../db/app_database.dart' as db;
import '../models/body_weight.dart';

/// BodyWeightRepository 的資料存取介面(公開方法簽名即原本 Drift 實作的公開 API)。
///
/// 實作:[DriftBodyWeightRepository](本機 Drift,`USE_MOCK`/測試/未設定 Supabase 時使用)、
/// `SupabaseBodyWeightRepository`(`supabase/supabase_body_weight_repository.dart`)。由
/// `data/providers.dart` 依 `supabaseClientProvider` 切換。各方法語義以
/// [DriftBodyWeightRepository] 的文件為準,Supabase 版的差異寫在該實作的類別文件。
abstract interface class BodyWeightRepository {
  Future<void> create(BodyWeight bodyWeight);
  Future<List<BodyWeight>> fetchAll();
  Future<List<BodyWeight>> fetchByDateRange(DateTime from, DateTime to);
  Future<List<BodyWeight>> fetchRecent(int limit);
  Future<void> update(BodyWeight bodyWeight);
  Future<void> delete(String id);
  Future<BodyWeight?> getLatestWeight();
  Future<double?> getAverageWeight(DateTime from, DateTime to);
}

/// 體重記錄的資料存取層。對照 iOS 版
/// `ios/WorkoutRecord/WorkoutRecord/Sources/Repositories/BodyWeightRepository.swift`。
class DriftBodyWeightRepository implements BodyWeightRepository {
  DriftBodyWeightRepository(this._db);

  final db.AppDatabase _db;

  // MARK: - Create

  @override
  Future<void> create(BodyWeight bodyWeight) async {
    await _db.into(_db.bodyWeights).insert(bodyWeight.toCompanion());
  }

  // MARK: - Read

  @override
  Future<List<BodyWeight>> fetchAll() async {
    final rows = await (_db.select(_db.bodyWeights)
          ..orderBy([(t) => OrderingTerm(expression: t.measuredAt, mode: OrderingMode.desc)]))
        .get();
    return rows.map(BodyWeight.fromRow).toList();
  }

  @override
  Future<List<BodyWeight>> fetchByDateRange(DateTime from, DateTime to) async {
    final rows = await (_db.select(_db.bodyWeights)
          ..where((t) => t.measuredAt.isBetweenValues(from, to))
          ..orderBy([(t) => OrderingTerm(expression: t.measuredAt)]))
        .get();
    return rows.map(BodyWeight.fromRow).toList();
  }

  @override
  Future<List<BodyWeight>> fetchRecent(int limit) async {
    final rows = await (_db.select(_db.bodyWeights)
          ..orderBy([(t) => OrderingTerm(expression: t.measuredAt, mode: OrderingMode.desc)])
          ..limit(limit))
        .get();
    return rows.map(BodyWeight.fromRow).toList();
  }

  // MARK: - Update

  @override
  Future<void> update(BodyWeight bodyWeight) async {
    final rowsAffected = await (_db.update(_db.bodyWeights)
          ..where((t) => t.id.equals(bodyWeight.id)))
        .write(
      db.BodyWeightsCompanion(
        weight: Value(bodyWeight.weight),
        measuredAt: Value(bodyWeight.measuredAt),
        note: Value(bodyWeight.note),
        isSynced: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (rowsAffected == 0) {
      throw StateError('BodyWeight not found: ${bodyWeight.id}');
    }
  }

  // MARK: - Delete

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.bodyWeights)..where((t) => t.id.equals(id))).go();
  }

  // MARK: - Statistics

  @override
  Future<BodyWeight?> getLatestWeight() async {
    final row = await (_db.select(_db.bodyWeights)
          ..orderBy([(t) => OrderingTerm(expression: t.measuredAt, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : BodyWeight.fromRow(row);
  }

  @override
  Future<double?> getAverageWeight(DateTime from, DateTime to) async {
    final weights = await fetchByDateRange(from, to);
    if (weights.isEmpty) return null;
    final sum = weights.fold<double>(0, (total, w) => total + w.weight);
    return sum / weights.length;
  }
}
