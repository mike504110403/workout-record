// 「訓練統計」子頁的資料組裝與狀態控制。對應 iOS 版
// `VolumeChartViewModel` + `DashboardViewModel`(本週統計/最近訓練那兩塊
// WorkoutStatsView 直接借用 DashboardViewModel 的欄位,這裡改成子頁自己的
// controller 一次算好,不 import dashboard controller)。
//
// 週起算沿用 dashboard_controller.dart 的慣例:固定 ISO 8601(週一為一週
// 開始),跨裝置/測試環境一致。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/workout.dart';
import '../../../data/providers.dart';
import '../chart_palette.dart';
import 'chart_time_range.dart';
import 'volume_aggregation.dart';

class WorkoutStatsState {
  const WorkoutStatsState({
    required this.timeRange,
    required this.muscleGroupFilter,
    required this.dataPoints,
    required this.stats,
    required this.weekWorkoutCount,
    required this.weekTotalVolume,
    required this.recentWorkouts,
  });

  final ChartTimeRange timeRange;
  final MuscleGroupFilter muscleGroupFilter;
  final List<VolumeDataPoint> dataPoints;
  final VolumeStats stats;
  final int weekWorkoutCount;
  final double weekTotalVolume;
  final List<Workout> recentWorkouts;

  WorkoutStatsState copyWith({
    ChartTimeRange? timeRange,
    MuscleGroupFilter? muscleGroupFilter,
    List<VolumeDataPoint>? dataPoints,
    VolumeStats? stats,
    int? weekWorkoutCount,
    double? weekTotalVolume,
    List<Workout>? recentWorkouts,
  }) {
    return WorkoutStatsState(
      timeRange: timeRange ?? this.timeRange,
      muscleGroupFilter: muscleGroupFilter ?? this.muscleGroupFilter,
      dataPoints: dataPoints ?? this.dataPoints,
      stats: stats ?? this.stats,
      weekWorkoutCount: weekWorkoutCount ?? this.weekWorkoutCount,
      weekTotalVolume: weekTotalVolume ?? this.weekTotalVolume,
      recentWorkouts: recentWorkouts ?? this.recentWorkouts,
    );
  }
}

class WorkoutStatsController extends AsyncNotifier<WorkoutStatsState> {
  @override
  Future<WorkoutStatsState> build() {
    return _load(timeRange: kDefaultChartTimeRange, filter: MuscleGroupFilter.all);
  }

  /// 對外重新整理(對照 dashboard 的 `refresh()`/router.dart 分頁 invalidate
  /// 慣例)。切到「數據」分頁時 router.dart 會呼叫
  /// `ref.invalidate(workoutStatsControllerProvider)`,直接讓 build() 重跑
  /// ——不透過這個方法;這個方法保留給頁面內主動下拉刷新等場景使用。
  Future<void> refresh() async {
    final current = state.value;
    state = await AsyncValue.guard(
      () => _load(
        timeRange: current?.timeRange ?? kDefaultChartTimeRange,
        filter: current?.muscleGroupFilter ?? MuscleGroupFilter.all,
      ),
    );
  }

  /// 切換時間範圍:天數範圍改變,需要重新查詢 DB。
  Future<void> changeTimeRange(ChartTimeRange range) async {
    final current = state.value;
    state = await AsyncValue.guard(
      () => _load(
        timeRange: range,
        filter: current?.muscleGroupFilter ?? MuscleGroupFilter.all,
      ),
    );
  }

  /// 切換肌群篩選:同一批 [VolumeDataPoint] 已經含各肌群的容量拆分
  /// (見 [aggregateVolumeByDate]),不需要重新查詢 DB,純粹在既有資料上
  /// 重算 [VolumeStats]。
  void selectMuscleGroupFilter(MuscleGroupFilter filter) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        muscleGroupFilter: filter,
        stats: calculateVolumeStats(current.dataPoints, filter),
      ),
    );
  }

  Future<WorkoutStatsState> _load({
    required ChartTimeRange timeRange,
    required MuscleGroupFilter filter,
  }) async {
    final workoutRepo = ref.read(workoutRepositoryProvider);
    final now = DateTime.now();

    // DateTime(y, m, d - offset) 日曆算術,不用 `Duration` 位移——理由同
    // dashboard_controller.dart 的 `_startOfWeek`/`endOfToday`:跨 DST
    // 邊界時 `.subtract(Duration(days: n))` 可能算出偏差一小時的邊界,讓
    // 時間範圍篩選漏掉或多算邊界那天的訓練。
    final rangeStart = DateTime(now.year, now.month, now.day - (timeRange.days - 1));
    final rangeEndExclusive = DateTime(now.year, now.month, now.day + 1);
    final workouts = await workoutRepo.fetchByDateRange(rangeStart, rangeEndExclusive);
    final dataPoints = aggregateVolumeByDate(workouts);
    final stats = calculateVolumeStats(dataPoints, filter);

    final weekStart = _startOfWeek(now);
    final weekWorkoutCount = await workoutRepo.countWorkouts(from: weekStart, to: now);
    final weekTotalVolume = await workoutRepo.calculateTotalVolume(from: weekStart, to: now);
    final recentWorkouts = await workoutRepo.fetchRecent(5);

    return WorkoutStatsState(
      timeRange: timeRange,
      muscleGroupFilter: filter,
      dataPoints: dataPoints,
      stats: stats,
      weekWorkoutCount: weekWorkoutCount,
      weekTotalVolume: weekTotalVolume,
      recentWorkouts: recentWorkouts,
    );
  }

  /// ISO 8601:週一為一週開始。與 dashboard_controller.dart 的
  /// `_startOfWeek` 同一套算法(刻意各自維護一份,不 import dashboard 的
  /// controller)。
  DateTime _startOfWeek(DateTime now) {
    return DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }
}

final workoutStatsControllerProvider =
    AsyncNotifierProvider<WorkoutStatsController, WorkoutStatsState>(WorkoutStatsController.new);
