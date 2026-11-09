import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/exercise.dart';
import '../exercise_repository.dart';
import 'supabase_mapping.dart';

/// [ExerciseRepository] 的 Supabase 實作。
///
/// 與 [DriftExerciseRepository] 的差異:
/// - 可見範圍由 RLS 決定:系統動作(全體共享唯讀)+ 登入者自己的自訂動作。
/// - 寫入時 `user_id` 一律覆寫成登入者 auth uid(model 的 userId 不採用)。
/// - 系統動作唯讀:[update]/[delete] 對系統動作不會生效(RLS 擋下 → 0 列);
///   [update] 因此拋 StateError(同 Drift「找不到」路徑),[delete] 靜默 no-op
///   (Drift 版會把系統動作標成 isActive = false)。
/// - [search] 用 `ilike`(SQLite LIKE 對 ASCII 本來就不分大小寫,語義一致)。
/// - 排序用 Postgres 的 collation,中文名稱排序可能與 SQLite BINARY 不同。
class SupabaseExerciseRepository implements ExerciseRepository {
  SupabaseExerciseRepository(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('exercises');

  Map<String, dynamic> _toJson(Exercise exercise) => {
        ...companionToJson(exercise.toCompanion()),
        'user_id': requireUid(_client),
      };

  List<Exercise> _parse(List<Map<String, dynamic>> rows) =>
      rows.map((j) => Exercise.fromRow(exerciseRowFromJson(j))).toList();

  @override
  Future<void> create(Exercise exercise) async {
    await _table.insert(_toJson(exercise));
  }

  @override
  Future<void> batchCreate(List<Exercise> exercises) async {
    if (exercises.isEmpty) return;
    await _table.insert(exercises.map(_toJson).toList());
  }

  @override
  Future<List<Exercise>> fetchAll({bool includeInactive = false}) async {
    var query = _table.select();
    if (!includeInactive) query = query.eq('is_active', true);
    return _parse(await query.order('name', ascending: true));
  }

  @override
  Future<Exercise?> fetchById(String id) async {
    final row = await _table.select().eq('id', id).maybeSingle();
    return row == null ? null : Exercise.fromRow(exerciseRowFromJson(row));
  }

  @override
  Future<List<Exercise>> fetchByCategory(String categoryId) async {
    return _parse(await _table
        .select()
        .eq('category_id', categoryId)
        .eq('is_active', true)
        .order('name', ascending: true));
  }

  @override
  Future<List<Exercise>> fetchByType(ExerciseType type) async {
    return _parse(await _table
        .select()
        .eq('type', type.value)
        .eq('is_active', true)
        .order('name', ascending: true));
  }

  @override
  Future<List<Exercise>> fetchSystemExercises() async {
    return _parse(await _table
        .select()
        .eq('is_system', true)
        .eq('is_active', true)
        .order('name', ascending: true));
  }

  /// [userId] 不參與查詢:擁有者一律是登入者(RLS),見類別文件。
  @override
  Future<List<Exercise>> fetchCustomExercises(String userId) async {
    return _parse(await _table
        .select()
        .eq('is_system', false)
        .eq('user_id', requireUid(_client))
        .eq('is_active', true)
        .order('name', ascending: true));
  }

  @override
  Future<List<Exercise>> getCustomExercises() async {
    return _parse(await _table
        .select()
        .eq('is_system', false)
        .eq('is_active', true)
        .order('name', ascending: true));
  }

  @override
  Future<Exercise?> getExercise(String id) => fetchById(id);

  @override
  Future<List<Exercise>> search(String keyword) async {
    // PostgREST or() 的值用雙引號包起來,keyword 裡的逗號/括號才不會破壞語法。
    final escaped = keyword.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final pattern = '"%$escaped%"';
    return _parse(await _table
        .select()
        .or('name.ilike.$pattern,name_en.ilike.$pattern')
        .eq('is_active', true)
        .order('name', ascending: true));
  }

  @override
  Future<void> update(Exercise exercise) async {
    final rows = await _table
        .update({
          'name': exercise.name,
          'name_en': exercise.nameEn,
          'category_id': exercise.categoryId,
          'type': exercise.type.value,
          'movement_pattern': exercise.movementPattern?.value,
          'primary_muscle_group': exercise.primaryMuscleGroup?.value,
          'description_text': exercise.description,
          'video_url': exercise.videoUrl,
          'image_url': exercise.imageUrl,
          'updated_at': encodeValue(DateTime.now()),
        })
        .eq('id', exercise.id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('Exercise not found: ${exercise.id}');
    }
  }

  @override
  Future<void> delete(String id) async {
    await _table.update({
      'is_active': false,
      'updated_at': encodeValue(DateTime.now()),
    }).eq('id', id);
  }

  @override
  Future<void> permanentDelete(String id) async {
    await _table.delete().eq('id', id).eq('is_system', false);
  }
}
