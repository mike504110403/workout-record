import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/exercise.dart';
import '../exercise_repository.dart';
import '../supabase/supabase_mapping.dart';

/// 雲端模式的 [ExerciseRepository] 裝飾器:動作清單離線快取,讓選動作器在
/// 訓練進行中離線也能加動作。
///
/// - [fetchAll] 雲端成功 → 依(目前 auth uid, includeInactive)寫快取;網路失敗
///   ([Exception])→ 回傳目前 uid 的快取(沒有就拋原錯誤)。快取以 uid 區隔,
///   因為清單含登入者自己的自訂動作(RLS),不同帳號互不可見。
/// - [fetchByCategory] 網路失敗 → 由 active 清單快取篩 categoryId(雲端版同樣
///   只回 is_active 的列,快取已依 name、id 排序,順序一致)。
/// - 其他方法(含新增自訂動作)直接委派,離線照舊失敗、由呼叫端既有錯誤提示處理。
class OfflineCachedExerciseRepository implements ExerciseRepository {
  OfflineCachedExerciseRepository(this._remote, this._prefs, this._currentUid);

  final ExerciseRepository _remote;
  final SharedPreferences _prefs;
  final String? Function() _currentUid;

  /// 快取 key 前綴(後接 `<uid>.active` 或 `<uid>.all`)。
  static const keyPrefix = 'offline_cache.exercises.v1.';

  String _key(String uid, {required bool includeInactive}) =>
      '$keyPrefix$uid.${includeInactive ? 'all' : 'active'}';

  List<Exercise>? _readCache(String uid, {required bool includeInactive}) {
    final raw = _prefs.getString(_key(uid, includeInactive: includeInactive));
    if (raw == null) return null;
    return [
      for (final j in jsonDecode(raw) as List)
        Exercise.fromRow(
          exerciseRowFromJson(Map<String, dynamic>.from(j as Map)),
        ),
    ];
  }

  @override
  Future<List<Exercise>> fetchAll({bool includeInactive = false}) async {
    try {
      final exercises = await _remote.fetchAll(
        includeInactive: includeInactive,
      );
      final uid = _currentUid();
      if (uid != null) {
        await _prefs.setString(
          _key(uid, includeInactive: includeInactive),
          jsonEncode([
            for (final e in exercises) companionToJson(e.toCompanion()),
          ]),
        );
      }
      return exercises;
    } on Exception {
      final uid = _currentUid();
      final cached = uid == null
          ? null
          : _readCache(uid, includeInactive: includeInactive);
      if (cached == null) rethrow;
      return cached;
    }
  }

  @override
  Future<List<Exercise>> fetchByCategory(String categoryId) async {
    try {
      return await _remote.fetchByCategory(categoryId);
    } on Exception {
      final uid = _currentUid();
      final cached = uid == null
          ? null
          : _readCache(uid, includeInactive: false);
      if (cached == null) rethrow;
      return [
        for (final e in cached)
          if (e.categoryId == categoryId) e,
      ];
    }
  }

  @override
  Future<void> create(Exercise exercise) => _remote.create(exercise);

  @override
  Future<void> batchCreate(List<Exercise> exercises) =>
      _remote.batchCreate(exercises);

  @override
  Future<Exercise?> fetchById(String id) => _remote.fetchById(id);

  @override
  Future<List<Exercise>> fetchByType(ExerciseType type) =>
      _remote.fetchByType(type);

  @override
  Future<List<Exercise>> fetchSystemExercises() =>
      _remote.fetchSystemExercises();

  @override
  Future<List<Exercise>> fetchCustomExercises(String userId) =>
      _remote.fetchCustomExercises(userId);

  @override
  Future<List<Exercise>> getCustomExercises() => _remote.getCustomExercises();

  @override
  Future<Exercise?> getExercise(String id) => _remote.getExercise(id);

  @override
  Future<List<Exercise>> search(String keyword) => _remote.search(keyword);

  @override
  Future<void> update(Exercise exercise) => _remote.update(exercise);

  @override
  Future<void> delete(String id) => _remote.delete(id);

  @override
  Future<void> permanentDelete(String id) => _remote.permanentDelete(id);
}
