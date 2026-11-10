import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../db/app_database.dart';
import '../supabase/supabase_mapping.dart';
import '../user_repository.dart';

/// 雲端模式的 [UserRepository] 裝飾器:[getById] 雲端成功時把結果快取到本機
/// (key = 目前登入者 auth uid),網路失敗時回傳快取——讓 `WorkoutController`
/// 與選動作器解析 userId 時離線也能過。
///
/// - 只快取/回傳**目前登入者本人**([_currentUid])的列:查詢 id 不等於目前
///   auth uid 時不寫快取、失敗時也不回快取(直接拋出原錯誤),不會把別人的
///   快取交給另一個帳號。
/// - 雲端明確回 null(列不存在)時清掉該 uid 的快取。
/// - 只攔 [Exception](網路/PostgREST/Auth 錯誤);[Error](例如未登入的
///   StateError)照原樣拋出。
/// - [ensure] 直接委派(寫入不離線排隊)。
class OfflineCachedUserRepository implements UserRepository {
  OfflineCachedUserRepository(this._remote, this._prefs, this._currentUid);

  final UserRepository _remote;
  final SharedPreferences _prefs;
  final String? Function() _currentUid;

  /// 快取 key 前綴(後接 auth uid)。
  static const keyPrefix = 'offline_cache.user.v1.';

  @override
  Future<User?> getById(String id) async {
    try {
      final user = await _remote.getById(id);
      final uid = _currentUid();
      if (uid != null && id == uid) {
        if (user != null && user.id == uid) {
          await _prefs.setString(
            '$keyPrefix$uid',
            jsonEncode(companionToJson(user.toCompanion(false))),
          );
        } else if (user == null) {
          await _prefs.remove('$keyPrefix$uid');
        }
      }
      return user;
    } on Exception {
      final uid = _currentUid();
      if (uid == null || uid != id) rethrow;
      final raw = _prefs.getString('$keyPrefix$uid');
      if (raw == null) rethrow;
      return userRowFromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    }
  }

  @override
  Future<bool> ensure(String id, {String? name, String? email}) =>
      _remote.ensure(id, name: name, email: email);
}
