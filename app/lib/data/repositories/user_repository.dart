// Users 表的最小存取介面。現階段 App 只有單一使用者身分(Apple/測試登入
// id 當主鍵),沒有多帳號並存需求,所以介面刻意精簡成「有沒有、確保有一筆
// 可用」,不做通用 CRUD。
//
// 「該用哪個 id、要不要沿用既有的 row」是呼叫端(OnboardingController)的
// 業務決策,這裡只做純粹的 DB 存取。
//
// 原本還有 `getFirst()`(不排序、任意拿一筆),曾被 OnboardingController
// 拿來當「升級用戶沒有明確血緣 id 時的保險 fallback」——已隨血緣誤判修正
// (見 review 2026-07-30)改用 `getById(coredata_imported_user_id)`,不再
// 需要「隨便拿一筆」這種語意含糊的查詢,直接刪除。
import 'package:drift/drift.dart';

import '../db/app_database.dart';

class UserRepository {
  UserRepository(this._db);

  final AppDatabase _db;

  Future<User?> getById(String id) =>
      (_db.select(_db.users)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 確保 [id] 這筆 Users row 存在:已存在就不動作,否則新建。回傳是否為
  /// 本次呼叫新建的 row(false = 沿用既有 row)——呼叫端(OnboardingController)
  /// 拿這個結果決定要不要另外寫一筆初始 BodyWeight(只有真正新建的使用者
  /// 才該有「初始體重」,沿用既有 row 不該重複寫,見重複初始體重回歸修正,
  /// review 2026-07-30)。
  Future<bool> ensure(String id, {String? name, String? email}) async {
    final existing = await getById(id);
    if (existing != null) return false;

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
    return true;
  }
}
