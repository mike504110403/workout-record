import 'package:drift/drift.dart';

import '../db/app_database.dart' as db;
import '../models/exercise.dart';
import '../models/personal_record.dart';
import 'exercise_repository.dart';

/// 個人紀錄(PR)的資料存取層。對照 iOS 版
/// `ios/WorkoutRecord/WorkoutRecord/Sources/Repositories/PersonalRecordRepository.swift`。
class PersonalRecordRepository {
  PersonalRecordRepository(this._db, this._exerciseRepository);

  final db.AppDatabase _db;
  final ExerciseRepository _exerciseRepository;

  // MARK: - Create

  Future<void> create(PersonalRecord personalRecord) async {
    await _db.into(_db.personalRecords).insert(personalRecord.toCompanion());
  }

  // MARK: - Fetch

  Future<PersonalRecord?> fetchById(String id) async {
    final row = await (_db.select(_db.personalRecords)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : PersonalRecord.fromRow(row);
  }

  Future<List<PersonalRecord>> fetchByExercise(String exerciseId) async {
    final rows = await (_db.select(_db.personalRecords)
          ..where((t) => t.exerciseId.equals(exerciseId))
          ..orderBy([(t) => OrderingTerm(expression: t.achievedAt, mode: OrderingMode.desc)]))
        .get();
    return rows.map(PersonalRecord.fromRow).toList();
  }

  Future<List<PersonalRecord>> fetchByUser(String userId) async {
    final rows = await (_db.select(_db.personalRecords)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm(expression: t.achievedAt, mode: OrderingMode.desc)]))
        .get();
    return rows.map(PersonalRecord.fromRow).toList();
  }

  Future<List<PersonalRecord>> fetchAll() async {
    final rows = await (_db.select(_db.personalRecords)
          ..orderBy([(t) => OrderingTerm(expression: t.achievedAt, mode: OrderingMode.desc)]))
        .get();
    return rows.map(PersonalRecord.fromRow).toList();
  }

  /// 獲取所有個人記錄(別名方法,對照 Swift `getAllPersonalRecords`)。
  Future<List<PersonalRecord>> getAllPersonalRecords() => fetchAll();

  /// 根據 ID 獲取個人記錄(別名方法,對照 Swift `getPersonalRecord(by:)`)。
  Future<PersonalRecord?> getPersonalRecord(String id) => fetchById(id);

  // MARK: - Get Current PR

  /// 獲取特定動作的當前 PR(最高 1RM)。
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

  Future<void> delete(String id) async {
    final rowsAffected =
        await (_db.delete(_db.personalRecords)..where((t) => t.id.equals(id))).go();
    if (rowsAffected == 0) {
      throw StateError('PersonalRecord not found: $id');
    }
  }

  Future<void> deleteByExercise(String exerciseId) async {
    await (_db.delete(_db.personalRecords)..where((t) => t.exerciseId.equals(exerciseId))).go();
  }

  // MARK: - Check for New PR

  /// 檢查是否為新 PR(根據 1RM)。
  Future<bool> isNewPR(String exerciseId, double oneRepMax) async {
    final currentPR = await getCurrentPR(exerciseId);
    if (currentPR == null) return true;
    return oneRepMax > currentPR.oneRepMax;
  }

  /// 只有在 1RM 高於現有 PR 時才建立新紀錄(更新邏輯:更高 1RM 才覆蓋)。
  /// 回傳 `null` 代表不是新 PR、未寫入。
  Future<PersonalRecord?> createIfNewPR(PersonalRecord candidate) async {
    final isNew = await isNewPR(candidate.exerciseId, candidate.oneRepMax);
    if (!isNew) return null;
    await create(candidate);
    return candidate;
  }
}
