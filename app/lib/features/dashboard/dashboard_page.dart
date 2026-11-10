// 首頁。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Dashboard/DashboardView.swift`。
//
// 差異:iOS 用 NotificationCenter 廣播切換分頁,這裡是 go_router 的
// StatefulShellRoute,直接 `context.go` 對應路徑即可切分頁,不需要通知機制。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_tokens.dart';
import '../goals/goal_settings_page.dart';
import 'dashboard_controller.dart';
import 'widgets/add_body_weight_sheet.dart';
import 'widgets/body_weight_card.dart';
import 'widgets/recent_workouts_section.dart';
import 'widgets/start_workout_cta.dart';
import 'widgets/week_summary_card.dart';

/// 首頁。由上而下:唯一主 CTA(開始/繼續訓練)→ 本週卡(次數、容量、目標進度、
/// 今日狀態)→ 體重卡 → 最近訓練。頂部用 M3 large title(`SliverAppBar.large`),
/// 不佔一條只重複分頁名稱的 AppBar。
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardControllerProvider);

    return Scaffold(
      body: dashboardAsync.when(
        data: (state) => RefreshIndicator(
          onRefresh: () => ref.read(dashboardControllerProvider.notifier).refresh(),
          child: _scrollView(
            // 內容區塊數量固定、不會無限增長,刻意包在單一 SliverToBoxAdapter
            // (整段一次建置),不用 SliverList 的 lazy 虛擬化——虛擬化會讓
            // 捲動範圍外的區塊不進 Element tree,widget test 用 find.byKey
            // 之類的 finder 會找不到還沒被建置的下方區塊(這裡吃過虧,見
            // 開發過程的除錯記錄)。
            SliverToBoxAdapter(child: _content(context, state)),
          ),
        ),
        loading: () => _scrollView(
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
        // 查詢失敗(例如暫時性的 DB/IO 錯誤)不能讓使用者卡在死路——補一顆
        // 重試按鈕,invalidate provider 重新跑一次 build()/_load(),失敗若是
        // 暫時性的就能自行恢復,不必整個 app 重開。
        error: (error, stackTrace) => _scrollView(
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 固定文案,不把 exception 內容塞進 UI(對齊 session_controller
                  // 的慣例);細節開發時看 console/log。
                  const Text('載入失敗，請稍後再試'),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    key: const Key('dashboardErrorRetryButton'),
                    onPressed: () => ref.invalidate(dashboardControllerProvider),
                    child: const Text('重試'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scrollView(Widget bodySliver) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverAppBar.large(title: Text('首頁')),
        bodySliver,
      ],
    );
  }

  Widget _content(BuildContext context, DashboardState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        AppSpacing.sm,
        AppSpacing.pageHorizontal,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StartWorkoutCta(
            hasDraftWorkout: state.hasDraftWorkout,
            onPressed: () => context.go('/workout'),
          ),
          const SizedBox(height: AppSpacing.lg),
          WeekSummaryCard(
            weekWorkoutCount: state.weekWorkoutCount,
            weekTotalVolume: state.weekTotalVolume,
            userGoal: state.userGoal,
            goalPercentage: state.goalPercentage,
            motivationalMessage: state.motivationalMessage,
            todayWorkout: state.todayWorkout,
            onViewProgress: () => context.go('/stats'),
            // 波 5:目標設定頁是 zero-arg const StatelessWidget、自帶
            // Scaffold(同 pr_list_page.dart 慣例),直接 push 即可,不
            // 需要外層再包殼、也不掛 route。存檔成功後 Dashboard/
            // 體重頁的 controller 由 GoalSettingsController.save()
            // 內部負責 invalidate(見該檔案開頭注解),這裡不需要在
            // push 返回後額外處理刷新。
            onOpenGoal: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GoalSettingsPage()),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          BodyWeightCard(
            currentWeight: state.currentWeight,
            weekChange: state.weightWeekChange,
            onRecord: () => _showBodyWeightSheet(context),
          ),
          const SizedBox(height: AppSpacing.xl),
          RecentWorkoutsSection(
            recentWorkouts: state.recentWorkouts,
            onViewAll: () => context.go('/history'),
          ),
        ],
      ),
    );
  }

  // AddBodyWeightSheet 自己負責寫入 BodyWeightRepository 與觸發 Dashboard
  // 刷新(在彈窗還開著的時候 await 完成才 pop),這裡只需要單純顯示彈窗。
  Future<void> _showBodyWeightSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // 首頁在 StatefulShellRoute 的分頁 Navigator 內:彈窗掛在 root navigator,
      // 才能蓋住底部導覽列、不被分頁 Navigator 裁切。
      useRootNavigator: true,
      builder: (context) => const AddBodyWeightSheet(),
    );
  }
}
