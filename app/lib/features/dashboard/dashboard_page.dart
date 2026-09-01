// 首頁。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Dashboard/DashboardView.swift`。
//
// 差異:iOS 用 NotificationCenter 廣播切換分頁,這裡是 go_router 的
// StatefulShellRoute,直接 `context.go` 對應路徑即可切分頁,不需要通知機制。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../goals/goal_settings_page.dart';
import 'dashboard_controller.dart';
import 'widgets/add_body_weight_sheet.dart';
import 'widgets/goal_progress_section.dart';
import 'widgets/quick_actions_section.dart';
import 'widgets/recent_workouts_section.dart';
import 'widgets/today_overview_section.dart';
import 'widgets/week_stats_section.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('首頁')),
      body: dashboardAsync.when(
        data: (state) => RefreshIndicator(
          onRefresh: () => ref.read(dashboardControllerProvider.notifier).refresh(),
          child: SingleChildScrollView(
            // 內容固定五個區塊、不會無限增長,刻意不用 ListView/ListView.builder
            // 的 lazy 虛擬化——虛擬化會讓捲動範圍外的區塊不進 Element tree,
            // widget test 用 find.byKey 之類的 finder 會找不到還沒被建置的
            // 下方區塊(這裡吃過虧,見開發過程的除錯記錄)。
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TodayOverviewSection(
                  todayWorkout: state.todayWorkout,
                  currentWeight: state.currentWeight,
                ),
                const SizedBox(height: 20),
                QuickActionsSection(
                  onRecordWeight: () => _showBodyWeightSheet(context),
                  onStartWorkout: () => context.go('/workout'),
                  onViewProgress: () => context.go('/stats'),
                ),
                const SizedBox(height: 20),
                GoalProgressSection(
                  userGoal: state.userGoal,
                  weekWorkoutCount: state.weekWorkoutCount,
                  goalPercentage: state.goalPercentage,
                  motivationalMessage: state.motivationalMessage,
                  // 波 5:目標設定頁是 zero-arg const StatelessWidget、自帶
                  // Scaffold(同 pr_list_page.dart 慣例),直接 push 即可,不
                  // 需要外層再包殼、也不掛 route。存檔成功後 Dashboard/
                  // 體重頁的 controller 由 GoalSettingsController.save()
                  // 內部負責 invalidate(見該檔案開頭注解),這裡不需要在
                  // push 返回後額外處理刷新。
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const GoalSettingsPage()),
                  ),
                ),
                const SizedBox(height: 20),
                WeekStatsSection(
                  weekWorkoutCount: state.weekWorkoutCount,
                  weekTotalVolume: state.weekTotalVolume,
                ),
                const SizedBox(height: 20),
                RecentWorkoutsSection(
                  recentWorkouts: state.recentWorkouts,
                  onViewAll: () => context.go('/history'),
                ),
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        // 查詢失敗(例如暫時性的 DB/IO 錯誤)不能讓使用者卡在死路——補一顆
        // 重試按鈕,invalidate provider 重新跑一次 build()/_load(),失敗若是
        // 暫時性的就能自行恢復,不必整個 app 重開。
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 固定文案,不把 exception 內容塞進 UI(對齊 session_controller
              // 的慣例);細節開發時看 console/log。
              const Text('載入失敗，請稍後再試'),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('dashboardErrorRetryButton'),
                onPressed: () => ref.invalidate(dashboardControllerProvider),
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // AddBodyWeightSheet 自己負責寫入 BodyWeightRepository 與觸發 Dashboard
  // 刷新(在彈窗還開著的時候 await 完成才 pop),這裡只需要單純顯示彈窗。
  Future<void> _showBodyWeightSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const AddBodyWeightSheet(),
    );
  }
}
