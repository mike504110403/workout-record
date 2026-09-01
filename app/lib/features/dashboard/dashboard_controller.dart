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
  Future<DashboardState> build() {
    // 建立對「目前登入身分」的 watch 依賴——sessionControllerProvider 不是
    // autoDispose,若只在 `_resolveUserId` 內用 `ref.read` 讀一次,session
    // 換人時 build() 不會重跑,goalRepo.fetchByUser 永遠查前一個帳號的
    // userId,首頁會顯示前帳號的目標進度快取。這裡直接 watch,身分一變
    // Riverpod 會自動重新呼叫 build()、整份 DashboardState 用新 userId
    // 重新組裝。用 `.select` 只精準訂閱 `appleUserId` 欄位,session 裡
    // isLoading/errorMessage 之類的欄位變動不會白白觸發 dashboard 重建。
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    return _load();
  }

  /// 對外重新整理(對照 iOS `DashboardViewModel.refresh()`)。記錄體重存檔
  /// 之後、或使用者下拉刷新時呼叫。
  ///
  /// 刻意不主動先把 state 切成 `AsyncValue.loading()`——那樣會把舊資料
  /// 整個丟掉,下拉刷新那一瞬間畫面會變成整頁 spinner(見
  /// dashboard_page.dart 的 `loading:` 分支是整頁置中轉圈,不是區塊級
  /// skeleton)。這裡讓 `_load()` await 期間 state 維持原本的 AsyncData,
  /// 畫面照舊顯示舊資料;下拉刷新本身已經有 RefreshIndicator 自己的轉圈
  /// 當作進行中提示,不需要再讓整頁跳成 spinner。(`AsyncValue.
  /// copyWithPrevious` 這個版本的 riverpod 標成 `@internal`,不對外開放,
  /// 所以不採用那個寫法。)
  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  /// 記一筆新體重並重新整理(對照 iOS `AddBodyWeightSheet` 存檔後
  /// Dashboard 收到 `.workoutCompleted`/畫面重新 onAppear 的效果)。
  ///
  /// userId 解析不到時(理論上不會發生,見檔案開頭注解)拋例外而非靜默
  /// return——呼叫端(AddBodyWeightSheet._save)的 try/catch 會顯示錯誤、
  /// 解除 loading,不會誤以為寫入成功了照樣 pop 彈窗。這則訊息是給開發者
  /// 看的診斷字串(記到 log/crash report),不會直接送到 UI——UI 顯示的是
  /// AddBodyWeightSheet 固定的「儲存失敗，請稍後再試」文案,不吃這裡的
  /// exception 內容(理論上不會發生的狀態,不值得為它另外設計使用者文案)。
  Future<void> recordBodyWeight(double weight) async {
    final userId = await _resolveUserId();
    if (userId == null) {
      throw StateError(
        'DashboardController.recordBodyWeight: 無法解析 userId'
        '(session 沒有已登入的 appleUserId,或 UserRepository.getById 查無此人)',
      );
    }

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
    // 用 DateTime(y, m, d+1) 的日曆算術,不用 `Duration(days: 1)` 位移——
    // 夏令時切換日當地一天不是 24 小時,`.add(Duration(days: 1))` 可能落在
    // 錯的鐘點(甚至不是隔天 00:00:00),讓「今日」區間算錯。DateTime
    // 建構子的月/日欄位允許超出正常範圍,會自動進位(例如 day: 32 自動變成
    // 下個月的 1 號),沒有 DST 位移的副作用。
    final endOfToday = DateTime(now.year, now.month, now.day + 1);

    final latestWeight = await bodyWeightRepo.getLatestWeight();
    final weekWorkoutCount = await workoutRepo.countWorkouts(from: weekStart, to: now);
    final weekTotalVolume = await workoutRepo.calculateTotalVolume(from: weekStart, to: now);
    final todayWorkouts = await workoutRepo.fetchByDateRange(startOfToday, endOfToday);
    final recentWorkouts = await workoutRepo.fetchRecent(5);

    final userId = await _resolveUserId();
    final userGoal = userId == null ? null : await goalRepo.fetchByUser(userId);

    double? goalPercentage;
    String motivationalMessage = kNoGoalMessage;
    // 波 5 review 打回(MAJOR SP1):weeklyWorkoutGoal == 0 代表「未設定」
    // (見 goal_settings_page.dart 規格:留空欄位存 0),不是「目標剛好是
    // 0 次」。這裡額外守 `weeklyWorkoutGoal > 0` 才進度分支——否則
    // `goalPercentage` 會算成 0(而不是 null),goal_progress_section.dart
    // 判斷 `percentage == null` 才顯示空狀態的條件不成立,畫面會誤顯示
    // 「N/0 次、0% 紅色進度條」而不是真正的空狀態提示。
    if (userGoal != null && userGoal.weeklyWorkoutGoal > 0) {
      goalPercentage = (weekWorkoutCount / userGoal.weeklyWorkoutGoal) * 100;
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
  ///
  /// 用 DateTime(y, m, d - offset) 的日曆算術,不用 `Duration(days: ...)`
  /// 位移——理由同 `endOfToday`,跨 DST 邊界時 `.subtract(Duration(days: n))`
  /// 可能算出偏差一小時的週一,週統計會把邊界那天的訓練算錯邊。
  DateTime _startOfWeek(DateTime now) {
    return DateTime(now.year, now.month, now.day - (now.weekday - 1));
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
