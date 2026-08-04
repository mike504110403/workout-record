// 首頁的資料組裝與狀態控制。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/ViewModels/DashboardViewModel.swift`。
//
// 週起算(iOS 用 `Calendar.current.dateComponents([.yearForWeekOfYear,
// .weekOfYear])`,實際值取決於裝置 locale 的一週第一天設定,行為不可預期)
// 這裡刻意改成固定 ISO 8601 規則(週一為一週的開始),換取跨裝置/測試環境
// 一致且可預期的行為——這是與 iOS 裝置相依行為的已知、刻意差異。
//
// userId 解析:對齊 features/onboarding/onboarding_controller.dart 的
// `_ensureUserRow` 已建立的慣例——目前使用者身分來自
// `sessionControllerProvider`(SessionState.appleUserId),真正落地確認則
// 透過 UserRepository.getById 查詢(不新增資料層方法、不碰 auth/session
// 檔案)。Dashboard 可抵達代表 Onboarding 已完成,理論上這筆 id 必定對應到
// 一筆已存在的 Users row;查不到時(理論上不會發生)一律視為「無使用者」,
// 目標區塊回退成空狀態,不拋錯讓整頁掛掉。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/uuid.dart';
import '../../data/models/body_weight.dart';
import '../../data/models/user_goal.dart';
import '../../data/models/workout.dart';
import '../../data/providers.dart';
import '../auth/session_controller.dart';

/// 空狀態 / 尚未設定週目標時的鼓勵文案。
const kNoGoalMessage = '設定目標，追蹤進步！';

class DashboardState {
  const DashboardState({
    this.todayWorkout,
    this.currentWeight,
    this.weekWorkoutCount = 0,
    this.weekTotalVolume = 0,
    this.recentWorkouts = const [],
    this.userGoal,
    this.goalPercentage,
    this.motivationalMessage = kNoGoalMessage,
  });

  final Workout? todayWorkout;
  final double? currentWeight;
  final int weekWorkoutCount;
  final double weekTotalVolume;
  final List<Workout> recentWorkouts;
  final UserGoal? userGoal;

  /// 本週訓練次數 / 目標次數 * 100,未設定目標時為 null(對照 iOS
  /// `viewModel.userGoal == nil` 時不顯示目標進度區塊的內容)。可能超過
  /// 100(對照 iOS `GoalProgress.percentage` 不做上限,顯示層另外把進度條
  /// 畫面本身夾在 0~100%,文字不夾)。
  final double? goalPercentage;
  final String motivationalMessage;
}

class DashboardController extends AsyncNotifier<DashboardState> {
  @override
  Future<DashboardState> build() => _load();

  /// 對外重新整理(對照 iOS `DashboardViewModel.refresh()`)。記錄體重存檔
  /// 之後、或使用者下拉刷新時呼叫。
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  /// 記一筆新體重並重新整理(對照 iOS `AddBodyWeightSheet` 存檔後
  /// Dashboard 收到 `.workoutCompleted`/畫面重新 onAppear 的效果)。
  Future<void> recordBodyWeight(double weight) async {
    final userId = await _resolveUserId();
    if (userId == null) return;

    final now = DateTime.now();
    final bodyWeightRepo = ref.read(bodyWeightRepositoryProvider);
    await bodyWeightRepo.create(
      BodyWeight(
        id: generateUuidV4(),
        userId: userId,
        weight: weight,
        measuredAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refresh();
  }

  Future<DashboardState> _load() async {
    final workoutRepo = ref.read(workoutRepositoryProvider);
    final bodyWeightRepo = ref.read(bodyWeightRepositoryProvider);
    final goalRepo = ref.read(userGoalRepositoryProvider);

    final now = DateTime.now();
    final weekStart = _startOfWeek(now);
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    final latestWeight = await bodyWeightRepo.getLatestWeight();
    final weekWorkoutCount = await workoutRepo.countWorkouts(from: weekStart, to: now);
    final weekTotalVolume = await workoutRepo.calculateTotalVolume(from: weekStart, to: now);
    final todayWorkouts = await workoutRepo.fetchByDateRange(startOfToday, endOfToday);
    final recentWorkouts = await workoutRepo.fetchRecent(5);

    final userId = await _resolveUserId();
    final userGoal = userId == null ? null : await goalRepo.fetchByUser(userId);

    double? goalPercentage;
    String motivationalMessage = kNoGoalMessage;
    if (userGoal != null) {
      goalPercentage = userGoal.weeklyWorkoutGoal > 0
          ? (weekWorkoutCount / userGoal.weeklyWorkoutGoal) * 100
          : 0;
      motivationalMessage = _motivationalMessage(goalPercentage);
    }

    return DashboardState(
      todayWorkout: todayWorkouts.isNotEmpty ? todayWorkouts.first : null,
      currentWeight: latestWeight?.weight,
      weekWorkoutCount: weekWorkoutCount,
      weekTotalVolume: weekTotalVolume,
      recentWorkouts: recentWorkouts,
      userGoal: userGoal,
      goalPercentage: goalPercentage,
      motivationalMessage: motivationalMessage,
    );
  }

  Future<String?> _resolveUserId() async {
    final sessionUserId = ref.read(sessionControllerProvider).appleUserId;
    if (sessionUserId == null || sessionUserId.isEmpty) return null;
    final userRepo = ref.read(userRepositoryProvider);
    final user = await userRepo.getById(sessionUserId);
    return user?.id;
  }

  /// ISO 8601:週一為一週開始。回傳當週週一 00:00:00。
  DateTime _startOfWeek(DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    return startOfToday.subtract(Duration(days: startOfToday.weekday - 1));
  }

  /// 對照 iOS `DashboardViewModel.generateMotivationalMessage`。
  String _motivationalMessage(double percentage) {
    if (percentage <= 0) return '開始本週第一次訓練吧！💪';
    if (percentage < 30) return '不錯的開始！繼續加油💪';
    if (percentage < 50) return '穩定前進中！堅持下去🔥';
    if (percentage < 80) return '快達成目標了！再加把勁🔥';
    if (percentage < 100) return '就差一點點了！衝刺吧🚀';
    if (percentage == 100) return '太棒了！本週目標達成✨';
    return '超越目標！你太強了🏆';
  }
}

final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardState>(DashboardController.new);
