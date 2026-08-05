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
  /// 遞增的請求序號,防止「後發先至」的舊查詢結果覆蓋掉新查詢的結果——
  /// 例如使用者快速連續切時間範圍(週→月→年),月的查詢若比年的查詢晚
  /// 完成,不能讓月的結果蓋掉年的結果。對照 exercise_picker 的
  /// `selectCategory` 前例(同一套「只接受最新一次請求的結果」手法)。每個
  /// 會改變資料再寫回 [state] 的方法(`refresh`/`changeTimeRange`)呼叫前
  /// 先遞增拿到自己的 [_requestId] 快照,await 完成後比對:序號被更新的
  /// 呼叫超前(代表在等待期間又有更新的請求發出),就丟棄這次的結果、不
  /// 寫回 state。[selectMuscleGroupFilter] 是同步操作(不 await 任何東西),
  /// 也遞增這個序號——確保它之後才寫回 state 的任何一次 async 呼叫,若是
  /// 在它之前發出的,同樣會被判定為過期並丟棄。
  int _requestId = 0;

  @override
  Future<WorkoutStatsState> build() {
    return _load(timeRange: kDefaultChartTimeRange, filter: MuscleGroupFilter.all);
  }

  /// 對外重新整理(對照 dashboard 的 `refresh()`/router.dart 分頁 invalidate
  /// 慣例)。切到「數據」分頁時 router.dart 會呼叫
  /// `ref.invalidate(workoutStatsControllerProvider)`,直接讓 build() 重跑
  /// ——不透過這個方法;這個方法接在 `RefreshIndicator`(見
  /// workout_stats_tab.dart)的下拉刷新手勢上。
  Future<void> refresh() async {
    final current = state.value;
    final requestId = ++_requestId;
    final result = await AsyncValue.guard(
      () => _load(
        timeRange: current?.timeRange ?? kDefaultChartTimeRange,
        filter: current?.muscleGroupFilter ?? MuscleGroupFilter.all,
      ),
    );
    if (requestId != _requestId) return; // 已被更新的請求取代,丟棄過期結果。
    state = result;
  }

  /// 切換時間範圍:天數範圍改變,需要重新查詢 DB。
  Future<void> changeTimeRange(ChartTimeRange range) async {
    final current = state.value;
    final requestId = ++_requestId;
    final result = await AsyncValue.guard(
      () => _load(
        timeRange: range,
        filter: current?.muscleGroupFilter ?? MuscleGroupFilter.all,
      ),
    );
    if (requestId != _requestId) return; // 已被更新的請求取代,丟棄過期結果。
    state = result;
  }

  /// 切換肌群篩選:同一批 [VolumeDataPoint] 已經含各肌群的容量拆分
  /// (見 [aggregateVolumeByDate]),不需要重新查詢 DB,純粹在既有資料上
  /// 重算 [VolumeStats]。
  void selectMuscleGroupFilter(MuscleGroupFilter filter) {
    _requestId++; // 讓在此之前發出、還沒完成的 changeTimeRange/refresh 過期。
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

    // 時間範圍口徑對齊 iOS `VolumeChartViewModel.loadData()`:
    // `calendar.date(byAdding: .day, value: -selectedTimeRange.days, to:
    // endDate)`——這是對「現在這個時間點」往回退 N 個日曆天,不是先把
    // 「現在」normalize 到當天午夜再退天數;`to:` 也是 `endDate`(現在這個
    // 時間點本身),不是隔天午夜。實際效果:因為 `now` 的時分秒通常不是
    // 0 點,這個區間會touch到 `days + 1` 個不同的日曆日期(例如週=7 天,
    // 實際涵蓋 8 個日曆日的部分時段)。這裡照 iOS 實際行為搬,不是先前
    // 版本「精確 N 個完整日曆天」的口徑(那個版本雖然直覺但跟 iOS 對不
    // 起來)。
    //
    // 時分秒沿用 `now` 本身(不 normalize 成午夜),日期部分用
    // `DateTime(y, m, d - days, ...)` 建構子算術而非 `.subtract(Duration
    // (days: days))`——後者在 DST 邊界可能造成時鐘位移;前者是日曆層級的
    // 天數位移,再把當下的時分秒原樣接回去,行為上更貼近 `Calendar.
    // date(byAdding:)` 的語意。
    final rangeStart = DateTime(
      now.year,
      now.month,
      now.day - timeRange.days,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
    final workouts = await workoutRepo.fetchByDateRange(rangeStart, now);
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
