import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart' as db;
import 'exercise.dart';

/// 訓練記錄 domain model,對應 Drift `Workouts` 表。
///
/// [exercises] 不是資料庫欄位,由 repository 組裝(join `WorkoutExercises` + `WorkoutSets`)。
class Workout {
  final String id;
  final String userId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? duration;
  final double totalVolume;
  final int totalSets;
  final int totalExercises;
  final String? note;
  final String? templateId;
  final bool isSynced;
  final List<WorkoutExercise> exercises;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Workout({
    required this.id,
    required this.userId,
    required this.startedAt,
    this.endedAt,
    this.duration,
    this.totalVolume = 0,
    this.totalSets = 0,
    this.totalExercises = 0,
    this.note,
    this.templateId,
    this.isSynced = false,
    this.exercises = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// 由 Drift row 轉換,[exercises] 需另外由 repository 填入(預設空)。
  factory Workout.fromRow(db.Workout row, {List<WorkoutExercise> exercises = const []}) {
    return Workout(
      id: row.id,
      userId: row.userId,
      startedAt: row.startedAt,
      endedAt: row.endedAt,
      duration: row.duration,
      totalVolume: row.totalVolume,
      totalSets: row.totalSets,
      totalExercises: row.totalExercises,
      note: row.note,
      templateId: row.templateId,
      isSynced: row.isSynced,
      exercises: exercises,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  db.WorkoutsCompanion toCompanion() {
    return db.WorkoutsCompanion(
      id: Value(id),
      userId: Value(userId),
      startedAt: Value(startedAt),
      endedAt: Value(endedAt),
      duration: Value(duration),
      totalVolume: Value(totalVolume),
      totalSets: Value(totalSets),
      totalExercises: Value(totalExercises),
      note: Value(note),
      templateId: Value(templateId),
      isSynced: Value(isSynced),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  Workout copyWith({
    DateTime? endedAt,
    int? duration,
    double? totalVolume,
    int? totalSets,
    int? totalExercises,
    String? note,
    bool? isSynced,
    List<WorkoutExercise>? exercises,
    DateTime? updatedAt,
  }) {
    return Workout(
      id: id,
      userId: userId,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      duration: duration ?? this.duration,
      totalVolume: totalVolume ?? this.totalVolume,
      totalSets: totalSets ?? this.totalSets,
      totalExercises: totalExercises ?? this.totalExercises,
      note: note ?? this.note,
      templateId: templateId,
      isSynced: isSynced ?? this.isSynced,
      exercises: exercises ?? this.exercises,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 訓練中的單一動作,對應 Drift `WorkoutExercises` 表。
///
/// [exercise] 為選填的關聯動作資料(由 repository join `Exercises` 表填入)。
class WorkoutExercise {
  final String id;
  final String workoutId;
  final String exerciseId;
  final Exercise? exercise;
  final String? exerciseName;
  final int orderIndex;
  final double totalVolume;
  final int totalSets;
  final bool isCompleted;
  final bool isCustomExercise;
  final String? note;
  final List<WorkoutSet> sets;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WorkoutExercise({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    this.exercise,
    this.exerciseName,
    this.orderIndex = 0,
    this.totalVolume = 0,
    this.totalSets = 0,
    this.isCompleted = false,
    this.isCustomExercise = false,
    this.note,
    this.sets = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkoutExercise.fromRow(
    db.WorkoutExercise row, {
    Exercise? exercise,
    List<WorkoutSet> sets = const [],
  }) {
    return WorkoutExercise(
      id: row.id,
      workoutId: row.workoutId,
      exerciseId: row.exerciseId,
      exercise: exercise,
      exerciseName: row.exerciseName,
      orderIndex: row.orderIndex,
      totalVolume: row.totalVolume,
      totalSets: row.totalSets,
      isCompleted: row.isCompleted,
      isCustomExercise: row.isCustomExercise,
      note: row.note,
      sets: sets,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  db.WorkoutExercisesCompanion toCompanion() {
    return db.WorkoutExercisesCompanion(
      id: Value(id),
      workoutId: Value(workoutId),
      exerciseId: Value(exerciseId),
      exerciseName: Value(exerciseName),
      orderIndex: Value(orderIndex),
      totalVolume: Value(totalVolume),
      totalSets: Value(totalSets),
      isCompleted: Value(isCompleted),
      isCustomExercise: Value(isCustomExercise),
      note: Value(note),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  WorkoutExercise copyWith({
    Exercise? exercise,
    String? exerciseName,
    int? orderIndex,
    double? totalVolume,
    int? totalSets,
    bool? isCompleted,
    String? note,
    List<WorkoutSet>? sets,
    DateTime? updatedAt,
  }) {
    return WorkoutExercise(
      id: id,
      workoutId: workoutId,
      exerciseId: exerciseId,
      exercise: exercise ?? this.exercise,
      exerciseName: exerciseName ?? this.exerciseName,
      orderIndex: orderIndex ?? this.orderIndex,
      totalVolume: totalVolume ?? this.totalVolume,
      totalSets: totalSets ?? this.totalSets,
      isCompleted: isCompleted ?? this.isCompleted,
      isCustomExercise: isCustomExercise,
      note: note ?? this.note,
      sets: sets ?? this.sets,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 單一組數,對應 Drift `WorkoutSets` 表。
class WorkoutSet {
  final String id;
  final String workoutExerciseId;
  final int setNumber;
  final double weight;
  final int reps;
  final double volume;
  final double? rpe;
  final int? restSeconds;
  final bool isWarmup;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkoutSet({
    required this.id,
    required this.workoutExerciseId,
    required this.setNumber,
    required this.weight,
    required this.reps,
    double? volume,
    this.rpe,
    this.restSeconds,
    this.isWarmup = false,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  }) : volume = volume ?? weight * reps;

  factory WorkoutSet.fromRow(db.WorkoutSet row) {
    return WorkoutSet(
      id: row.id,
      workoutExerciseId: row.workoutExerciseId,
      setNumber: row.setNumber,
      weight: row.weight,
      reps: row.reps,
      volume: row.volume,
      rpe: row.rpe,
      restSeconds: row.restSeconds,
      isWarmup: row.isWarmup,
      note: row.note,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  db.WorkoutSetsCompanion toCompanion() {
    return db.WorkoutSetsCompanion(
      id: Value(id),
      workoutExerciseId: Value(workoutExerciseId),
      setNumber: Value(setNumber),
      weight: Value(weight),
      reps: Value(reps),
      volume: Value(volume),
      rpe: Value(rpe),
      restSeconds: Value(restSeconds),
      isWarmup: Value(isWarmup),
      note: Value(note),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  WorkoutSet copyWith({
    int? setNumber,
    double? weight,
    int? reps,
    double? rpe,
    int? restSeconds,
    bool? isWarmup,
    String? note,
    DateTime? updatedAt,
  }) {
    final newWeight = weight ?? this.weight;
    final newReps = reps ?? this.reps;
    return WorkoutSet(
      id: id,
      workoutExerciseId: workoutExerciseId,
      setNumber: setNumber ?? this.setNumber,
      weight: newWeight,
      reps: newReps,
      volume: newWeight * newReps,
      rpe: rpe ?? this.rpe,
      restSeconds: restSeconds ?? this.restSeconds,
      isWarmup: isWarmup ?? this.isWarmup,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 排除暖身組後,單一動作的容量(重量 × 次數加總)。[nonWarmupTotalVolume]
/// 對每個動作呼叫這個函式再加總——波 4 stats 訓練統計子頁的容量趨勢圖
/// (`features/stats/workout_stats/volume_aggregation.dart`)也需要「單一
/// 動作、排除暖身」的容量(用來算每個動作對所屬肌群的貢獻),原本在那邊
/// 私下重寫一份幾乎一樣的 fold,抽出來共用,避免重演本檔案上面這段註解
/// 提到的「兩處一度不同步」。
double nonWarmupExerciseVolume(WorkoutExercise exercise) =>
    exercise.sets.where((s) => !s.isWarmup).fold<double>(0, (sum, set) => sum + set.weight * set.reps);

/// 排除暖身組後的總容量(重量 × 次數加總)。對齊 iOS
/// `WorkoutViewModel.swift:233-236`(`updateTotals()`)與 `:402-405`
/// (`WorkoutExerciseViewModel.totalVolume`)——兩處皆先
/// `filter { !$0.isWarmup }` 才加總。`WorkoutRepository.completeWorkout`
/// (現算已完成訓練的統計)與 `workout_in_progress_view.dart` 的即時統計列
/// 曾經各自重寫一份這個邏輯,兩處一度不同步,收斂成單一函式共用。
double nonWarmupTotalVolume(List<WorkoutExercise> exercises) =>
    exercises.fold<double>(0, (sum, e) => sum + nonWarmupExerciseVolume(e));

/// 排除暖身組後的總組數,理由同 [nonWarmupTotalVolume]。
int nonWarmupTotalSets(List<WorkoutExercise> exercises) =>
    exercises.fold<int>(0, (sum, e) => sum + e.sets.where((s) => !s.isWarmup).length);
