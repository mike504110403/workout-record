// 計畫組(Mike 2026-11-11 裁示 2):從模板開始時,模板帶入的組不再寫成真實
// `WorkoutSet`,而是「計畫組」——畫面上灰色顯示、打勾才變成真實組。
//
// **刻意不進資料庫 schema**(`app/lib/data/` 不改):計畫組只是「這次訓練
// 打算做什麼」的本機草稿提示,沒打勾的組不該被同步、也不該出現在歷史裡。
// 存在 SharedPreferences,key 帶 workoutId,值是 JSON;App 重開續訓時由
// `WorkoutController` 依草稿 id 讀回,完成或放棄訓練時清掉。
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/shared_preferences_provider.dart';

/// 一筆計畫組(尚未打勾、不是真實組)。[weight] 一律 kg(與 `WorkoutSet`
/// 儲存值同單位),顯示時再換算。
@immutable
class PlannedSet {
  const PlannedSet({required this.id, required this.weight, required this.reps});

  /// 本機產生的識別碼,只用來在畫面與儲存裡定位這一筆(打勾/滑掉)。
  final String id;
  final double weight;
  final int reps;

  Map<String, Object> toJson() => {'id': id, 'weight': weight, 'reps': reps};

  static PlannedSet? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final weight = json['weight'];
    final reps = json['reps'];
    if (id is! String || weight is! num || reps is! num) return null;
    return PlannedSet(id: id, weight: weight.toDouble(), reps: reps.toInt());
  }

  @override
  bool operator ==(Object other) =>
      other is PlannedSet && other.id == id && other.weight == weight && other.reps == reps;

  @override
  int get hashCode => Object.hash(id, weight, reps);
}

/// 計畫組的本機附屬儲存。對外只有「整包讀 / 整包寫 / 清除」三個操作——
/// 資料量是單次訓練的幾個動作×幾組,整包覆寫比逐筆增刪簡單且不會失準。
class PlannedSetsStore {
  PlannedSetsStore(this._prefs);

  final SharedPreferences _prefs;

  static const keyPrefix = 'workout_planned_sets_';

  static String keyFor(String workoutId) => '$keyPrefix$workoutId';

  /// 讀回 [workoutId] 的計畫組,key 是 workoutExerciseId。沒有資料或 JSON
  /// 毀損時回空 map——計畫組只是提示,壞掉就當作沒有,不擋續訓。
  Map<String, List<PlannedSet>> read(String workoutId) {
    final raw = _prefs.getString(keyFor(workoutId));
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <String, List<PlannedSet>>{};
      decoded.forEach((key, value) {
        if (key is! String || value is! List) return;
        final sets = [
          for (final item in value) ?PlannedSet.fromJson(item),
        ];
        if (sets.isNotEmpty) result[key] = sets;
      });
      return result;
    } on FormatException {
      return const {};
    }
  }

  /// 整包覆寫;全部清空時直接移除 key,不留空殼。
  Future<void> write(String workoutId, Map<String, List<PlannedSet>> planned) async {
    final nonEmpty = {
      for (final entry in planned.entries)
        if (entry.value.isNotEmpty) entry.key: [for (final s in entry.value) s.toJson()],
    };
    if (nonEmpty.isEmpty) {
      await _prefs.remove(keyFor(workoutId));
      return;
    }
    await _prefs.setString(keyFor(workoutId), jsonEncode(nonEmpty));
  }

  Future<void> clear(String workoutId) => _prefs.remove(keyFor(workoutId));

  /// 清掉 [keepWorkoutId] 以外的所有計畫組 key。換帳號、刪帳號、或草稿在別處
  /// 被結清時,舊 key 沒有其他清除時機(`auth/`、`data/` 不歸這裡管),由
  /// `WorkoutController` 在 build 與草稿檢查時以「目前使用者的草稿 id」呼叫。
  /// [keepWorkoutId] 為 null 代表目前使用者沒有草稿,全部清掉。
  Future<void> removeAllExcept(String? keepWorkoutId) async {
    final stale = [
      for (final key in _prefs.getKeys())
        if (key.startsWith(keyPrefix) && (keepWorkoutId == null || key != keyFor(keepWorkoutId))) key,
    ];
    for (final key in stale) {
      await _prefs.remove(key);
    }
  }
}

final plannedSetsStoreProvider = Provider<PlannedSetsStore>(
  (ref) => PlannedSetsStore(ref.watch(sharedPreferencesProvider)),
);
