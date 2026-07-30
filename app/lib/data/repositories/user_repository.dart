// Users 表的最小存取介面。現階段 App 只有單一使用者身分(Apple/測試登入
// id 當主鍵),沒有多帳號並存需求,所以介面刻意精簡成「有沒有、拿第一筆、
// 確保有一筆可用」,不做通用 CRUD。
//
// 「該用哪個 id、要不要沿用既有的第一筆」是呼叫端(OnboardingController)
// 的業務決策,這裡只做純粹的 DB 存取。
import 'package:drift/drift.dart';

import '../db/app_database.dart';

class UserRepository {
  UserRepository(this._db);

  final AppDatabase _db;

  Future<User?> getById(String id) =>
      (_db.select(_db.users)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<User?> getFirst() => (_db.select(_db.users)..limit(1)).getSingleOrNull();

  /// 確保 [id] 這筆 Users row 存在:已存在就不動作,否則新建。
  Future<void> ensure(String id, {String? name, String? email}) async {
    final existing = await getById(id);
    if (existing != null) return;

    final now = DateTime.now();
    await _db.into(_db.users).insert(
          UsersCompanion.insert(
            id: id,
            name: Value(name),
            email: Value(email),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
