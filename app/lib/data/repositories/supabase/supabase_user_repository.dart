import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../db/app_database.dart';
import '../user_repository.dart';
import 'supabase_mapping.dart';

/// [UserRepository] 的 Supabase 實作。`public.users.id` 就是 `auth.users.id`,
/// RLS 只讓登入者讀寫自己那一列。
///
/// 與 [DriftUserRepository] 的差異(待登入波對齊 session 的 userId 與 auth uid):
/// - [getById]:[id] 不是登入者 auth uid 時直接回 null(RLS 本來就看不到別人的
///   列;先擋掉也避免非 uuid 格式的舊 Apple userIdentifier 觸發 Postgres
///   uuid 轉型錯誤)。
/// - [ensure]:[id] 不是登入者 auth uid 時拋 StateError——Supabase 版只能為
///   登入者本人建列,不靜默改寫成別的 id,讓 session id 與 auth uid 不一致的
///   問題在登入波浮出來。
class SupabaseUserRepository implements UserRepository {
  SupabaseUserRepository(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('users');

  @override
  Future<User?> getById(String id) async {
    final uid = requireUid(_client);
    if (id != uid) return null;
    final row = await _table.select().eq('id', uid).maybeSingle();
    return row == null ? null : userRowFromJson(row);
  }

  @override
  Future<bool> ensure(String id, {String? name, String? email}) async {
    final uid = requireUid(_client);
    if (id != uid) {
      throw StateError('Supabase 模式下只能為登入者本人建立 users row(id=$id, auth uid=$uid)');
    }
    final now = encodeValue(DateTime.now());
    // ignoreDuplicates:已存在就不動(對齊 Drift 版「沿用既有 row」),
    // 回傳空清單代表沒有新建。
    final inserted = await _table
        .upsert(
          {'id': uid, 'name': name, 'email': email, 'created_at': now, 'updated_at': now},
          onConflict: 'id',
          ignoreDuplicates: true,
        )
        .select('id');
    return inserted.isNotEmpty;
  }
}
