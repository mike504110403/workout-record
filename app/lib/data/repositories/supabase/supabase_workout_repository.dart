import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/workout.dart';
import '../workout_repository.dart';
import 'supabase_mapping.dart';

/// [WorkoutRepository] 的 Supabase 實作。
///
/// 草稿寫穿語義照 [DriftWorkoutRepository]:開始訓練即建 `ended_at IS NULL`
/// 的草稿列,每個操作即時落庫,呼叫端每次操作後重新 [fetchById]。
///
/// Drift 版靠 transaction 保證的多步寫入,這裡收進 Postgres function(一次
/// RPC = 一個 transaction,定義見 supabase/migrations/20261110000300_rpc.sql):
/// - [create] → `create_workout`;[addExerciseToWorkout] → `insert_workout_children`
/// - [removeExercise] → `remove_workout_exercise`(刪除 + orderIndex 重編 0..N-1)
/// - [deleteSet] → `delete_workout_set`(刪除 + setNumber 重編 1..N)
/// - [completeWorkout] → `complete_workout`(DB 級冪等:只更新 ended_at IS NULL)
/// - [recomputeSummary] → `recompute_workout_summary`(草稿拋 StateError)
/// 統計公式與 [nonWarmupTotalVolume]/[nonWarmupTotalSets] 相同(暖身組排除)。
///
/// 與 Drift 版的差異:
/// - 擁有者一律是登入者 auth uid(RLS);[fetchDraft] 的 userId 參數與 model 的
///   userId 不參與查詢/寫入。
/// - [completeWorkout]/[recomputeSummary] 的 `updated_at` 與(未指定 endedAt 時的)
///   `ended_at` 由 DB `now()` 決定,Drift 版用 client 時鐘。
/// - 重編號遇到同號時以 created_at、id 當次排序鍵(Drift 版同號順序未定義)。
/// - [calculateTotalVolume] 取回各列 total_volume 在 client 端加總(PostgREST
///   預設不開 aggregate);[countWorkouts] 用 PostgREST exact count。
class SupabaseWorkoutRepository implements WorkoutRepository {
  SupabaseWorkoutRepository(this._client);

  final SupabaseClient _client;

  static const _select = '*, workout_exercises(*, exercises(*), workout_sets(*))';

  SupabaseQueryBuilder get _table => _client.from('workouts');

  // MARK: - Create

  @override
  Future<void> create(Workout workout) async {
    requireUid(_client);
    await _client.rpc<void>('create_workout', params: {
      'p_workout': companionToJson(workout.toCompanion()),
      'p_exercises': [for (final e in workout.exercises) companionToJson(e.toCompanion())],
      'p_sets': [
        for (final e in workout.exercises)
          for (final s in e.sets) companionToJson(s.toCompanion()),
      ],
    });
  }

  // MARK: - Draft mutations

  @override
  Future<void> addExerciseToWorkout(WorkoutExercise exercise) async {
    requireUid(_client);
    await _client.rpc<void>('insert_workout_children', params: {
      'p_exercises': [companionToJson(exercise.toCompanion())],
      'p_sets': [for (final s in exercise.sets) companionToJson(s.toCompanion())],
    });
  }

  @override
  Future<void> removeExercise(String workoutExerciseId, {required String workoutId}) {
    return rethrowAsStateError(() => _client.rpc<void>('remove_workout_exercise', params: {
          'p_workout_exercise_id': workoutExerciseId,
          'p_workout_id': workoutId,
        }));
  }

  @override
  Future<void> setExerciseCompleted(String workoutExerciseId, {required bool isCompleted}) async {
    final rows = await _client
        .from('workout_exercises')
        .update({
          'is_completed': isCompleted,
          'updated_at': encodeValue(DateTime.now()),
        })
        .eq('id', workoutExerciseId)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('WorkoutExercise not found: $workoutExerciseId');
    }
  }

  @override
  Future<void> addSet(WorkoutSet set) async {
    // user_id 由 DB default auth.uid() 帶入。
    await _client.from('workout_sets').insert(companionToJson(set.toCompanion()));
  }

  @override
  Future<void> updateSet(WorkoutSet set) async {
    final rows = await _client
        .from('workout_sets')
        .update({
          'weight': set.weight,
          'reps': set.reps,
          'volume': set.volume,
          'rpe': set.rpe,
          'rest_seconds': set.restSeconds,
          'is_warmup': set.isWarmup,
          'updated_at': encodeValue(DateTime.now()),
        })
        .eq('id', set.id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('WorkoutSet not found: ${set.id}');
    }
  }

  @override
  Future<void> deleteSet(String setId, {required String workoutExerciseId}) {
    return rethrowAsStateError(() => _client.rpc<void>('delete_workout_set', params: {
          'p_set_id': setId,
          'p_workout_exercise_id': workoutExerciseId,
        }));
  }

  @override
  Future<void> discardDraft(String workoutId) async {
    await _table.delete().eq('id', workoutId).isFilter('ended_at', null);
  }

  // MARK: - Read

  @override
  Future<List<Workout>> fetchAll() async {
    final rows = await selectAllPages(() => _table
        .select(_select)
        .not('ended_at', 'is', null)
        .order('started_at', ascending: false)
        .order('id', ascending: true));
    return rows.map(_hydrate).toList();
  }

  @override
  Future<List<Workout>> getAllWorkouts() => fetchAll();

  @override
  Future<Workout?> fetchById(String id) async {
    final row = await _table.select(_select).eq('id', id).maybeSingle();
    return row == null ? null : _hydrate(row);
  }

  @override
  Future<Workout?> getWorkout(String id) => fetchById(id);

  @override
  Future<Workout?> fetchDraft(String userId) async {
    final row = await _table
        .select(_select)
        .eq('user_id', requireUid(_client))
        .isFilter('ended_at', null)
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : _hydrate(row);
  }

  @override
  Future<List<Workout>> fetchByDateRange(DateTime from, DateTime to) async {
    final rows = await selectAllPages(() => _table
        .select(_select)
        .gte('started_at', encodeValue(from)!)
        .lte('started_at', encodeValue(to)!)
        .not('ended_at', 'is', null)
        .order('started_at', ascending: false)
        .order('id', ascending: true));
    return rows.map(_hydrate).toList();
  }

  @override
  Future<List<Workout>> fetchRecent(int limit) async {
    final rows = await selectAllPages(
        () => _table
            .select(_select)
            .not('ended_at', 'is', null)
            .order('started_at', ascending: false)
            .order('id', ascending: true),
        maxRows: limit);
    return rows.map(_hydrate).toList();
  }

  // MARK: - Update

  @override
  Future<void> update(Workout workout) async {
    final rows = await _table
        .update({
          'ended_at': encodeValue(workout.endedAt),
          'duration': workout.duration,
          'total_volume': workout.totalVolume,
          'total_sets': workout.totalSets,
          'total_exercises': workout.totalExercises,
          'note': workout.note,
          'updated_at': encodeValue(DateTime.now()),
          'is_synced': false,
        })
        .eq('id', workout.id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('Workout not found: ${workout.id}');
    }
  }

  // MARK: - Delete

  @override
  Future<void> delete(String id) async {
    await _table.delete().eq('id', id);
  }

  @override
  Future<void> deleteOlderThan(DateTime date) async {
    await _table.delete().lt('started_at', encodeValue(date)!).not('ended_at', 'is', null);
  }

  // MARK: - Statistics

  @override
  Future<double> calculateTotalVolume({DateTime? from, DateTime? to}) async {
    // 全量掃描 total_volume:超過 1000 場會被截斷,所以分頁取完再加總
    // (PostgREST 聚合預設關閉,不依賴;排序用 started_at + id 確保翻頁穩定)。
    final rows = await selectAllPages(() {
      var query = _table.select('total_volume').not('ended_at', 'is', null);
      if (from != null) query = query.gte('started_at', encodeValue(from)!);
      if (to != null) query = query.lte('started_at', encodeValue(to)!);
      return query.order('started_at', ascending: false).order('id', ascending: true);
    });
    return rows.fold<double>(0, (sum, row) => sum + (row['total_volume'] as num).toDouble());
  }

  @override
  Future<int> countWorkouts({DateTime? from, DateTime? to}) async {
    var query = _table.count(CountOption.exact).not('ended_at', 'is', null);
    if (from != null) query = query.gte('started_at', encodeValue(from)!);
    if (to != null) query = query.lte('started_at', encodeValue(to)!);
    return await query;
  }

  @override
  Future<Workout> completeWorkout(String workoutId, {DateTime? endedAt}) async {
    await rethrowAsStateError(() => _client.rpc<void>('complete_workout', params: {
          'p_workout_id': workoutId,
          'p_ended_at': encodeValue(endedAt),
        }));
    return (await fetchById(workoutId))!;
  }

  @override
  Future<Workout> recomputeSummary(String workoutId) async {
    await rethrowAsStateError(() => _client.rpc<void>('recompute_workout_summary', params: {
          'p_workout_id': workoutId,
        }));
    return (await fetchById(workoutId))!;
  }

  // MARK: - Conversion

  Workout _hydrate(Map<String, dynamic> row) => workoutFromNestedJson(row);
}
