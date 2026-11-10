import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/workout_template.dart';
import '../supabase/supabase_mapping.dart';
import '../template_repository.dart';

/// 雲端模式的 [TemplateRepository] 裝飾器:模板清單離線快取,讓離線也能
/// 「從模板開始訓練」。
///
/// - [fetchAll]/[fetchSystemTemplates] 雲端成功 → 依目前 auth uid 寫快取;
///   網路失敗([Exception])→ 回傳快取(沒有就拋原錯誤)。系統模板也以 uid
///   區隔,讓清本機資料時一個前綴就清乾淨。
/// - [fetchById] 網路失敗 → 從兩份快取找同 id。
/// - 寫入(create/update/delete)直接委派,離線照舊失敗。
class OfflineCachedTemplateRepository implements TemplateRepository {
  OfflineCachedTemplateRepository(this._remote, this._prefs, this._currentUid);

  final TemplateRepository _remote;
  final SharedPreferences _prefs;
  final String? Function() _currentUid;

  /// 快取 key 前綴(後接 `<uid>.user` 或 `<uid>.system`)。
  static const keyPrefix = 'offline_cache.templates.v1.';

  String _key(String uid, String kind) => '$keyPrefix$uid.$kind';

  List<WorkoutTemplate>? _read(String uid, String kind) {
    final raw = _prefs.getString(_key(uid, kind));
    if (raw == null) return null;
    return [
      for (final j in jsonDecode(raw) as List)
        templateFromNestedJson(Map<String, dynamic>.from(j as Map)),
    ];
  }

  Future<List<WorkoutTemplate>> _cached(
    String kind,
    Future<List<WorkoutTemplate>> Function() fetch,
  ) async {
    try {
      final templates = await fetch();
      final uid = _currentUid();
      if (uid != null) {
        await _prefs.setString(
          _key(uid, kind),
          jsonEncode([for (final t in templates) templateToNestedJson(t)]),
        );
      }
      return templates;
    } on Exception {
      final uid = _currentUid();
      final cached = uid == null ? null : _read(uid, kind);
      if (cached == null) rethrow;
      return cached;
    }
  }

  @override
  Future<List<WorkoutTemplate>> fetchAll(String userId) =>
      _cached('user', () => _remote.fetchAll(userId));

  @override
  Future<List<WorkoutTemplate>> fetchSystemTemplates() =>
      _cached('system', _remote.fetchSystemTemplates);

  @override
  Future<WorkoutTemplate?> fetchById(String id) async {
    try {
      return await _remote.fetchById(id);
    } on Exception {
      final uid = _currentUid();
      if (uid == null) rethrow;
      final all = [...?_read(uid, 'user'), ...?_read(uid, 'system')];
      for (final t in all) {
        if (t.id == id) return t;
      }
      rethrow;
    }
  }

  @override
  Future<void> create(WorkoutTemplate template) => _remote.create(template);

  @override
  Future<void> update(WorkoutTemplate template) => _remote.update(template);

  @override
  Future<void> delete(String id) => _remote.delete(id);
}
