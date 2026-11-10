import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/exercise.dart';
import '../../models/personal_record.dart';
import '../personal_record_repository.dart';
import 'supabase_mapping.dart';

/// [PersonalRecordRepository] 的 Supabase 實作。
///
/// 與 [DriftPersonalRecordRepository] 的差異:
/// - 擁有者一律是登入者 auth uid(RLS);[fetchByUser]/[getPRSummary] 的 userId
///   參數與 model 的 userId 不參與查詢/寫入。Drift 版 [getCurrentPR]/[isNewPR]
///   不分使用者(本機只有一個擁有者),這裡由 RLS 自然限定本人,語義等價。
/// - [createIfNewPR] 走 RPC `create_personal_record_if_new`:「查目前最高 →
///   比較 → 寫入」在同一個 transaction 內、以 (user, exercise) advisory lock
///   序列化,多裝置同時結算不會各寫一筆(Drift 版是先查再寫兩步)。判準相同:
///   沒有既有 PR,或候選 1RM 嚴格大於目前最高才寫入。
/// - [getPRSummary] 用 PostgREST embed 一次撈 PR + 動作,不逐筆查動作。
class SupabasePersonalRecordRepository implements PersonalRecordRepository {
  SupabasePersonalRecordRepository(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('personal_records');

  List<PersonalRecord> _parse(List<Map<String, dynamic>> rows) =>
      rows.map((j) => PersonalRecord.fromRow(personalRecordRowFromJson(j))).toList();

  Map<String, dynamic> _toJson(PersonalRecord record) => {
        ...companionToJson(record.toCompanion()),
        'user_id': requireUid(_client),
      };

  @override
  Future<void> create(PersonalRecord personalRecord) async {
    await _table.insert(_toJson(personalRecord));
  }

  @override
  Future<PersonalRecord?> fetchById(String id) async {
    final row = await _table.select().eq('id', id).maybeSingle();
    return row == null ? null : PersonalRecord.fromRow(personalRecordRowFromJson(row));
  }

  @override
  Future<List<PersonalRecord>> fetchByExercise(String exerciseId) async {
    return _parse(await selectAllPages(() => _table
        .select()
        .eq('exercise_id', exerciseId)
        .order('achieved_at', ascending: false)
        .order('id', ascending: true)));
  }

  @override
  Future<List<PersonalRecord>> fetchByUser(String userId) async {
    return _parse(await selectAllPages(() => _table
        .select()
        .eq('user_id', requireUid(_client))
        .order('achieved_at', ascending: false)
        .order('id', ascending: true)));
  }

  @override
  Future<List<PersonalRecord>> fetchAll() async {
    return _parse(await selectAllPages(
        () => _table.select().order('achieved_at', ascending: false).order('id', ascending: true)));
  }

  @override
  Future<List<PersonalRecord>> getAllPersonalRecords() => fetchAll();

  @override
  Future<PersonalRecord?> getPersonalRecord(String id) => fetchById(id);

  @override
  Future<PersonalRecord?> getCurrentPR(String exerciseId) async {
    final row = await _table
        .select()
        .eq('exercise_id', exerciseId)
        .order('one_rep_max', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : PersonalRecord.fromRow(personalRecordRowFromJson(row));
  }

  @override
  Future<List<PRSummary>> getPRSummary(String userId) async {
    final rows = await selectAllPages(() => _table
        .select('*, exercises(*)')
        .eq('user_id', requireUid(_client))
        .order('achieved_at', ascending: false)
        .order('id', ascending: true));

    final prByExercise = <String, List<PersonalRecord>>{};
    final exerciseById = <String, Exercise>{};
    for (final row in rows) {
      final pr = PersonalRecord.fromRow(personalRecordRowFromJson(row));
      prByExercise.putIfAbsent(pr.exerciseId, () => []).add(pr);
      final exerciseJson = row['exercises'];
      if (exerciseJson is Map<String, dynamic>) {
        exerciseById[pr.exerciseId] = Exercise.fromRow(exerciseRowFromJson(exerciseJson));
      }
    }

    final summaries = <PRSummary>[];
    for (final entry in prByExercise.entries) {
      final exercise = exerciseById[entry.key];
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

  @override
  Future<void> update(PersonalRecord personalRecord) async {
    final rows = await _table
        .update({
          'weight': personalRecord.weight,
          'reps': personalRecord.reps,
          'one_rep_max': personalRecord.oneRepMax,
          'achieved_at': encodeValue(personalRecord.achievedAt),
          'workout_id': personalRecord.workoutId,
          'updated_at': encodeValue(DateTime.now()),
        })
        .eq('id', personalRecord.id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('PersonalRecord not found: ${personalRecord.id}');
    }
  }

  @override
  Future<void> delete(String id) async {
    final rows = await _table.delete().eq('id', id).select('id');
    if (rows.isEmpty) {
      throw StateError('PersonalRecord not found: $id');
    }
  }

  @override
  Future<void> deleteByExercise(String exerciseId) async {
    await _table.delete().eq('exercise_id', exerciseId);
  }

  @override
  Future<bool> isNewPR(String exerciseId, double oneRepMax) async {
    final currentPR = await getCurrentPR(exerciseId);
    if (currentPR == null) return true;
    return oneRepMax > currentPR.oneRepMax;
  }

  @override
  Future<PersonalRecord?> createIfNewPR(PersonalRecord candidate) async {
    // 重量或 1RM <= 0(模板帶入未填的 0 kg 組等)不算 PR,不打 RPC。
    if (candidate.weight <= 0 || candidate.oneRepMax <= 0) return null;
    final created = await _client.rpc<bool>(
      'create_personal_record_if_new',
      params: {'p_record': _toJson(candidate)},
    );
    return created ? candidate : null;
  }
}
