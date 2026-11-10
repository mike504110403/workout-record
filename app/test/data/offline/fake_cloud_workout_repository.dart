// 假雲端 WorkoutRepository:不連網、記錄每一次呼叫,可切離線或「上傳成功但
// 回應遺失」。給 OfflineDraftWorkoutRepository 的測試當 `_remote` 用。
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';

/// 模擬網路不通(對應 SocketException/ClientException 這類 [Exception])。
class FakeOfflineException implements Exception {
  const FakeOfflineException();
  @override
  String toString() => 'FakeOfflineException: 網路不通';
}

class FakeCloudWorkoutRepository implements WorkoutRepository {
  /// 每一次呼叫的方法名(含離線時失敗的呼叫)。
  final List<String> calls = [];

  /// 雲端已存在的訓練(id → workout)。
  final Map<String, Workout> rows = {};

  /// 實際寫入雲端的次數(create 成功插入列)。
  int insertCount = 0;

  bool offline = false;

  /// 下一次 create 寫入成功,但回應遺失:對呼叫端拋錯,且之後轉為離線
  /// (模擬寫入後斷網,回查也失敗)。
  bool loseNextCreateResponse = false;

  void _enter(String name) {
    calls.add(name);
    if (offline) throw const FakeOfflineException();
  }

  @override
  Future<void> create(Workout workout) async {
    _enter('create');
    if (rows.containsKey(workout.id)) {
      throw Exception(
        'duplicate key value violates unique constraint "workouts_pkey"',
      );
    }
    rows[workout.id] = workout;
    insertCount += 1;
    if (loseNextCreateResponse) {
      loseNextCreateResponse = false;
      offline = true;
      throw const FakeOfflineException();
    }
  }

  @override
  Future<Workout?> fetchById(String id) async {
    _enter('fetchById');
    return rows[id];
  }

  @override
  Future<Workout?> getWorkout(String id) => fetchById(id);

  /// 同 `complete_workout` RPC:已完成的列不改寫,直接回傳。
  @override
  Future<Workout> completeWorkout(String workoutId, {DateTime? endedAt}) async {
    _enter('completeWorkout');
    final row = rows[workoutId];
    if (row == null) throw StateError('Workout not found: $workoutId');
    if (row.endedAt != null) return row;
    final completed = row.copyWith(endedAt: endedAt ?? DateTime.now());
    rows[workoutId] = completed;
    return completed;
  }

  @override
  Future<void> discardDraft(String workoutId) async {
    _enter('discardDraft');
    final row = rows[workoutId];
    if (row != null && row.endedAt == null) rows.remove(workoutId);
  }

  @override
  Future<Workout?> fetchDraft(String userId) async {
    _enter('fetchDraft');
    return null;
  }

  @override
  Future<List<Workout>> fetchAll() async {
    _enter('fetchAll');
    return [
      for (final w in rows.values)
        if (w.endedAt != null) w,
    ];
  }

  /// 其餘方法:記錄呼叫後拋錯(這些測試不該走到)。
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    calls.add(name);
    throw UnimplementedError('FakeCloudWorkoutRepository: $name');
  }
}
