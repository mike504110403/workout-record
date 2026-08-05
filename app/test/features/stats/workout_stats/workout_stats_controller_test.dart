// WorkoutStatsController 的競態防護測試:快速連續切換時間範圍時,較早
// 發出但較晚完成的查詢不能覆蓋較新查詢已經寫入的結果(request id 守衛,
// 對照 exercise_picker selectCategory 的前例手法)。直接用 ProviderContainer
// 操作 controller,不透過 widget——精準控制兩次 DB 查詢的完成順序是重點,
// 用 widget test 反而難以卡住非同步時序。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/stats/workout_stats/chart_time_range.dart';
import 'package:workout_record/features/stats/workout_stats/workout_stats_controller.dart';

import '../../../data/test_helpers.dart';

/// 讓測試可以精準控制「第幾次呼叫 fetchByDateRange」何時完成。呼叫序號 0
/// (controller.build() 的初始查詢)永遠不受控制、直接放行;之後每呼叫一次
/// [addGate],下一次 `fetchByDateRange` 呼叫就會卡在該 gate,直到測試呼叫
/// `complete()`。
class _GatedWorkoutRepository extends WorkoutRepository {
  _GatedWorkoutRepository(super.db, super.exerciseRepository);

  final List<Completer<void>> _gates = [];
  var _callIndex = 0;

  Completer<void> addGate() {
    final completer = Completer<void>();
    _gates.add(completer);
    return completer;
  }

  @override
  Future<List<Workout>> fetchByDateRange(DateTime from, DateTime to) async {
    final index = _callIndex;
    _callIndex += 1;
    final gateIndex = index - 1; // 第 0 次(初始 build)不受控制。
    if (gateIndex >= 0 && gateIndex < _gates.length) {
      await _gates[gateIndex].future;
    }
    return super.fetchByDateRange(from, to);
  }
}

void main() {
  test(
    'changeTimeRange 快速連續呼叫時,較早發出但較晚完成的請求不會覆蓋較新請求的結果'
    '(request id 防後發先至)',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await seedTestUser(db);
      final repo = _GatedWorkoutRepository(db, ExerciseRepository(db));

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          workoutRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // 觸發初始 build()(呼叫序號 0,不受 gate 控制,直接完成)。
      await container.read(workoutStatsControllerProvider.future);
      final controller = container.read(workoutStatsControllerProvider.notifier);

      // 準備兩道 gate,對應接下來兩次 changeTimeRange 各自觸發的
      // fetchByDateRange 呼叫(呼叫序號 1、2)。
      final gateForYear = repo.addGate();
      final gateForWeek = repo.addGate();

      // 先發出「年」的請求(較早發出),還卡在 gate 裡沒完成。
      final yearFuture = controller.changeTimeRange(ChartTimeRange.year);
      // 再發出「週」的請求(較新發出),也卡在 gate 裡沒完成。
      final weekFuture = controller.changeTimeRange(ChartTimeRange.week);

      // 讓「週」(較新的請求)先完成。
      gateForWeek.complete();
      await weekFuture;
      expect(container.read(workoutStatsControllerProvider).value?.timeRange, ChartTimeRange.week);

      // 「年」(較舊的請求)才姍姍來遲完成——不應該覆蓋掉「週」已經寫入
      // state 的結果。若拿掉 request id 守衛,這裡的斷言會失敗(state 被
      // 「年」的結果覆蓋回去)。
      gateForYear.complete();
      await yearFuture;
      expect(
        container.read(workoutStatsControllerProvider).value?.timeRange,
        ChartTimeRange.week,
        reason: '較舊請求(年)後發完成,不應覆蓋較新請求(週)已寫入的結果',
      );
    },
  );
}
