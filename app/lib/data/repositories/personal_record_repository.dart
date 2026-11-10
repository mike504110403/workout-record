import 'package:drift/drift.dart';

import '../db/app_database.dart' as db;
import '../models/exercise.dart';
import '../models/personal_record.dart';
import 'exercise_repository.dart';

/// PersonalRecordRepository 的資料存取介面(公開方法簽名即原本 Drift 實作的公開 API)。
///
/// 實作:[DriftPersonalRecordRepository](本機 Drift,`USE_MOCK`/測試/未設定 Supabase 時使用)、
/// `SupabasePersonalRecordRepository`(`supabase/supabase_personal_record_repository.dart`)。由
/// `data/providers.dart` 依 `supabaseClientProvider` 切換。各方法語義以
/// [DriftPersonalRecordRepository] 的文件為準,Supabase 版的差異寫在該實作的類別文件。
abstract interface class PersonalRecordRepository {
  Future<void> create(PersonalRecord personalRecord);
  Future<PersonalRecord?> fetchById(String id);
  Future<List<PersonalRecord>> fetchByExercise(String exerciseId);
  Future<List<PersonalRecord>> fetchByUser(String userId);
  Future<List<PersonalRecord>> fetchAll();
  Future<List<PersonalRecord>> getAllPersonalRecords();
  Future<PersonalRecord?> getPersonalRecord(String id);
  Future<PersonalRecord?> getCurrentPR(String exerciseId);
  Future<List<PRSummary>> getPRSummary(String userId);
  Future<void> update(PersonalRecord personalRecord);
  Future<void> delete(String id);
  Future<void> deleteByExercise(String exerciseId);
  Future<bool> isNewPR(String exerciseId, double oneRepMax);
  Future<PersonalRecord?> createIfNewPR(PersonalRecord candidate);
}

/// 個人紀錄(PR)的資料存取層。對照 iOS 版
/// `ios/WorkoutRecord/WorkoutRecord/Sources/Repositories/PersonalRecordRepository.swift`。
class DriftPersonalRecordRepository implements PersonalRecordRepository {
  DriftPersonalRecordRepository(this._db, this._exerciseRepository);

  final db.AppDatabase _db;
  final ExerciseRepository _exerciseRepository;

  // MARK: - Create

  @override
  Future<void> create(PersonalRecord personalRecord) async {
    await _db.into(_db.personalRecords).insert(personalRecord.toCompanion());
  }

  // MARK: - Fetch

  @override
  Future<PersonalRecord?> fetchById(String id) async {
    final row = await (_db.select(_db.personalRecords)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : PersonalRecord.fromRow(row);
  }

  @override
  Future<List<PersonalRecord>> fetchByExercise(String exerciseId) async {
    final rows = await (_db.select(_db.personalRecords)
          ..where((t) => t.exerciseId.equals(exerciseId))
          ..orderBy([(t) => OrderingTerm(expression: t.achievedAt, mode: OrderingMode.desc)]))
        .get();
    return rows.map(PersonalRecord.fromRow).toList();
  }

  @override
  Future<List<PersonalRecord>> fetchByUser(String userId) async {
    final rows = await (_db.select(_db.personalRecords)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm(expression: t.achievedAt, mode: OrderingMode.desc)]))
        .get();
    return rows.map(PersonalRecord.fromRow).toList();
  }

  @override
  Future<List<PersonalRecord>> fetchAll() async {
    final rows = await (_db.select(_db.personalRecords)
          ..orderBy([(t) => OrderingTerm(expression: t.achievedAt, mode: OrderingMode.desc)]))
        .get();
    return rows.map(PersonalRecord.fromRow).toList();
  }

  /// 獲取所有個人記錄(別名方法,對照 Swift `getAllPersonalRecords`)。
  @override
  Future<List<PersonalRecord>> getAllPersonalRecords() => fetchAll();

  /// 根據 ID 獲取個人記錄(別名方法,對照 Swift `getPersonalRecord(by:)`)。
  @override
  Future<PersonalRecord?> getPersonalRecord(String id) => fetchById(id);

  // MARK: - Get Current PR

  /// 獲取特定動作的當前 PR(最高 1RM)。
  @override
  Future<PersonalRecord?> getCurrentPR(String exerciseId) async {
    final row = await (_db.select(_db.personalRecords)
          ..where((t) => t.exerciseId.equals(exerciseId))
          ..orderBy([(t) => OrderingTerm(expression: t.oneRepMax, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : PersonalRecord.fromRow(row);
  }

  // MARK: - Get PR Summary

  /// 獲取用戶所有動作的 PR 總結(按動作分組,含歷史紀錄)。
  @override
  Future<List<PRSummary>> getPRSummary(String userId) async {
    final allPRs = await fetchByUser(userId);

    final prByExercise = <String, List<PersonalRecord>>{};
    for (final pr in allPRs) {
      prByExercise.putIfAbsent(pr.exerciseId, () => []).add(pr);
    }

    final summaries = <PRSummary>[];
    for (final entry in prByExercise.entries) {
      final Exercise? exercise = await _exerciseRepository.fetchById(entry.key);
      if (exercise == null) continue;

      final prs = entry.value;
      final currentPR = prs.reduce((a, b) => a.oneRepMax >= b.oneRepMax ? a : b);
      final history = [...prs]..sort((a, b) => b.achievedAt.compareTo(a.achievedAt));

      summaries.add(PRSummary(
        exerciseId: entry.key,
        exerciseName: exercise.name,
        primaryMuscleGroup: exercise.primaryMuscleGroup,
        currentPR: currentPR,
        prHistory: history,
      ));
    }

    summaries.sort((a, b) {
      final group1 = a.primaryMuscleGroup?.value ?? '';
      final group2 = b.primaryMuscleGroup?.value ?? '';
      if (group1 != group2) return group1.compareTo(group2);
      return a.exerciseName.compareTo(b.exerciseName);
    });

    return summaries;
  }

  // MARK: - Update

  @override
  Future<void> update(PersonalRecord personalRecord) async {
    final rowsAffected = await (_db.update(_db.personalRecords)
          ..where((t) => t.id.equals(personalRecord.id)))
        .write(
      db.PersonalRecordsCompanion(
        weight: Value(personalRecord.weight),
        reps: Value(personalRecord.reps),
        oneRepMax: Value(personalRecord.oneRepMax),
        achievedAt: Value(personalRecord.achievedAt),
        workoutId: Value(personalRecord.workoutId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (rowsAffected == 0) {
      throw StateError('PersonalRecord not found: ${personalRecord.id}');
    }
  }

  // MARK: - Delete

  @override
  Future<void> delete(String id) async {
    final rowsAffected =
        await (_db.delete(_db.personalRecords)..where((t) => t.id.equals(id))).go();
    if (rowsAffected == 0) {
      throw StateError('PersonalRecord not found: $id');
    }
  }

  @override
  Future<void> deleteByExercise(String exerciseId) async {
    await (_db.delete(_db.personalRecords)..where((t) => t.exerciseId.equals(exerciseId))).go();
  }

  // MARK: - Check for New PR

  /// 檢查是否為新 PR(根據 1RM)。
  @override
  Future<bool> isNewPR(String exerciseId, double oneRepMax) async {
    final currentPR = await getCurrentPR(exerciseId);
    if (currentPR == null) return true;
    return oneRepMax > currentPR.oneRepMax;
  }

  /// 只有在 1RM 高於現有 PR 時才建立新紀錄(更新邏輯:更高 1RM 才覆蓋)。
  /// 回傳 `null` 代表不是新 PR、未寫入。
  @override
  Future<PersonalRecord?> createIfNewPR(PersonalRecord candidate) async {
    // 重量或 1RM <= 0(模板帶入未填的 0 kg 組等)不算 PR。
    if (candidate.weight <= 0 || candidate.oneRepMax <= 0) return null;
    final isNew = await isNewPR(candidate.exerciseId, candidate.oneRepMax);
    if (!isNew) return null;
    await create(candidate);
    return candidate;
  }
}
