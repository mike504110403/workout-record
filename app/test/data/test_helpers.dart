// 資料層測試共用的小工具:全部使用 NativeDatabase.memory() 開一個乾淨的
// in-memory 資料庫,並提供最小可行的 Users fixture(多數表的 userId 都有
// FK 參照 Users,且 beforeOpen 會開 PRAGMA foreign_keys = ON,所以測試建立
// Workout/BodyWeight/... 之前必須先塞一筆 Users)。

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:workout_record/data/db/app_database.dart';

/// 開一個全新的 in-memory 測試資料庫(會觸發 onCreate -> createAll +
/// seedIfEmpty,所以建完就已經有 66 筆系統動作)。呼叫端負責在測試結束時
/// `await db.close()`。
AppDatabase openTestDatabase() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

const testUserId = 'test-user-1';

/// 插入一筆最小可行的 Users row,回傳其 id(固定為 [testUserId])。
Future<String> seedTestUser(AppDatabase db, {String id = testUserId}) async {
  final now = DateTime.now();
  await db.into(db.users).insert(
        UsersCompanion.insert(
          id: id,
          name: const Value('Test User'),
          email: const Value('test@example.com'),
          createdAt: now,
          updatedAt: now,
        ),
      );
  return id;
}
