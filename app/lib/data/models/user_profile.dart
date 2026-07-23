import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart' as db;

/// 使用者基本資料,對應 Drift `Users` 表。
///
/// 目前 iOS 版沒有對應的 Repository(帳號/認證邏輯在 Services 層),
/// 此 model 保留給之後接上認證流程時使用。
class UserProfile {
  final String id;
  final String? name;
  final String? email;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    this.name,
    this.email,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromRow(db.User row) {
    return UserProfile(
      id: row.id,
      name: row.name,
      email: row.email,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  db.UsersCompanion toCompanion() {
    return db.UsersCompanion(
      id: Value(id),
      name: Value(name),
      email: Value(email),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  UserProfile copyWith({
    String? name,
    String? email,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
