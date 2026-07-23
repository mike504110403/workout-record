import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart' as db;

/// 動作類型。對應 Drift `Exercises.type` 欄位(儲存為字串)。
enum ExerciseType {
  machine('machine', '器材'),
  freeWeight('free_weight', '自由重量'),
  bodyweight('bodyweight', '徒手');

  const ExerciseType(this.value, this.displayName);

  final String value;
  final String displayName;

  static ExerciseType fromValue(String value) {
    return ExerciseType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ExerciseType.freeWeight,
    );
  }
}

/// 動作模式。對應 Drift `Exercises.movementPattern` 欄位。
enum MovementPattern {
  push('push', '推'),
  pull('pull', '拉'),
  squat('squat', '蹲'),
  hinge('hinge', '髖鉸鏈'),
  carry('carry', '負重行走'),
  rotation('rotation', '旋轉'),
  isolation('isolation', '孤立');

  const MovementPattern(this.value, this.displayName);

  final String value;
  final String displayName;

  static MovementPattern? fromValue(String? value) {
    if (value == null) return null;
    for (final pattern in MovementPattern.values) {
      if (pattern.value == value) return pattern;
    }
    return null;
  }
}

/// 主要肌群。對應 Drift `Exercises.primaryMuscleGroup` 欄位。
enum PrimaryMuscleGroup {
  chest('chest', '胸'),
  back('back', '背'),
  legs('legs', '腿'),
  shoulders('shoulders', '肩'),
  arms('arms', '手臂'),
  core('core', '核心'),
  glutes('glutes', '臀部'),
  fullBody('full_body', '全身');

  const PrimaryMuscleGroup(this.value, this.displayName);

  final String value;
  final String displayName;

  static PrimaryMuscleGroup? fromValue(String? value) {
    if (value == null) return null;
    for (final group in PrimaryMuscleGroup.values) {
      if (group.value == value) return group;
    }
    return null;
  }
}

/// 動作庫 domain model,對應 Drift `Exercises` 表。
class Exercise {
  final String id;
  final String name;
  final String? nameEn;
  final String categoryId;
  final ExerciseType type;
  final MovementPattern? movementPattern;
  final PrimaryMuscleGroup? primaryMuscleGroup;
  final String? description;
  final String? videoUrl;
  final String? imageUrl;
  final bool isSystem;
  final bool isActive;
  final String? userId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Exercise({
    required this.id,
    required this.name,
    this.nameEn,
    required this.categoryId,
    required this.type,
    this.movementPattern,
    this.primaryMuscleGroup,
    this.description,
    this.videoUrl,
    this.imageUrl,
    this.isSystem = false,
    this.isActive = true,
    this.userId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Exercise.fromRow(db.Exercise row) {
    return Exercise(
      id: row.id,
      name: row.name,
      nameEn: row.nameEn,
      categoryId: row.categoryId,
      type: ExerciseType.fromValue(row.type),
      movementPattern: MovementPattern.fromValue(row.movementPattern),
      primaryMuscleGroup: PrimaryMuscleGroup.fromValue(row.primaryMuscleGroup),
      description: row.descriptionText,
      videoUrl: row.videoURL,
      imageUrl: row.imageURL,
      isSystem: row.isSystem,
      isActive: row.isActive,
      userId: row.userId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  db.ExercisesCompanion toCompanion() {
    return db.ExercisesCompanion(
      id: Value(id),
      name: Value(name),
      nameEn: Value(nameEn),
      categoryId: Value(categoryId),
      type: Value(type.value),
      movementPattern: Value(movementPattern?.value),
      primaryMuscleGroup: Value(primaryMuscleGroup?.value),
      descriptionText: Value(description),
      videoURL: Value(videoUrl),
      imageURL: Value(imageUrl),
      isSystem: Value(isSystem),
      isActive: Value(isActive),
      userId: Value(userId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  Exercise copyWith({
    String? name,
    String? nameEn,
    String? categoryId,
    ExerciseType? type,
    MovementPattern? movementPattern,
    PrimaryMuscleGroup? primaryMuscleGroup,
    String? description,
    String? videoUrl,
    String? imageUrl,
    bool? isSystem,
    bool? isActive,
    String? userId,
    DateTime? updatedAt,
  }) {
    return Exercise(
      id: id,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      categoryId: categoryId ?? this.categoryId,
      type: type ?? this.type,
      movementPattern: movementPattern ?? this.movementPattern,
      primaryMuscleGroup: primaryMuscleGroup ?? this.primaryMuscleGroup,
      description: description ?? this.description,
      videoUrl: videoUrl ?? this.videoUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      isSystem: isSystem ?? this.isSystem,
      isActive: isActive ?? this.isActive,
      userId: userId ?? this.userId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
