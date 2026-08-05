import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/login_page.dart';
import 'features/auth/session_controller.dart';
import 'features/dashboard/dashboard_controller.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/history/history_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/onboarding/onboarding_status.dart';
import 'features/settings/settings_page.dart';
import 'features/stats/stats_page.dart';
import 'features/stats/workout_stats/workout_stats_controller.dart';
import 'features/workout/workout_page.dart';

/// 5-tab 導航殼的路由。分頁對應現行 iOS 版 `MainTabView`:
/// 首頁 / 訓練 / 數據 / 歷史 / 設定。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 入口流程守衛(對等 iOS `WorkoutRecordApp.body` 的三段式 if/else):
/// 未登入 -> /login;已登入未完成 Onboarding -> /onboarding;都完成 ->
/// /dashboard。純函式,不吃 BuildContext / GoRouterState,方便單獨單元測試。
String? resolveAuthRedirect({
  required bool isLoggedIn,
  required bool hasCompletedOnboarding,
  required String location,
}) {
  if (!isLoggedIn) {
    return location == '/login' ? null : '/login';
  }
  if (!hasCompletedOnboarding) {
    return location == '/onboarding' ? null : '/onboarding';
  }
  if (location == '/login' || location == '/onboarding') {
    return '/dashboard';
  }
  return null;
}

/// 首頁在 5-tab shell 裡的 branch index——與下方 `branches:` 陣列順序一致。
const _dashboardBranchIndex = 0;

/// `StatefulShellRoute.indexedStack` 讓分頁切換不會 dispose 頁面,
/// `DashboardController.build()` 只會在 provider 第一次建立時跑一次,使用者
/// 切去別的分頁再切回首頁不會重新查詢——跨午夜「今日概覽」停在昨天、波 3
/// 記完訓練切回首頁數字不更新都是同一個根因。這裡在切到首頁分頁時強制
/// invalidate 一次 dashboardControllerProvider,對照 iOS
/// `DashboardView.onAppear { viewModel.refresh() }`。
///
/// 只涵蓋目前唯一的回訪路徑(bottom nav bar 切分頁);之後如果新增其他能
/// 抵達 /dashboard 的路徑(例如從詳情頁 push 回來、程式化 `context.go`),
/// 那些路徑不會經過這裡,必須另外一併處理。
///
/// 純函式,不吃 BuildContext/WidgetRef,方便單獨單元測試(見
/// test/router/router_redirect_test.dart;實際「切分頁真的觸發 invalidate」
/// 這條線的行為測在 test/features/dashboard/dashboard_shell_revisit_test.dart
/// ——純函式測試只守「index 對應」,守不住接線本身有沒有真的呼叫)。
bool shouldRefreshDashboardOnBranchSwitch(int targetIndex) => targetIndex == _dashboardBranchIndex;

/// 「數據」在 5-tab shell 裡的 branch index——與下方 `branches:` 陣列順序
/// 一致(首頁 0 / 訓練 1 / 數據 2 / 歷史 3 / 設定 4)。
const _statsBranchIndex = 2;

/// 波 4 補上的第二個「回訪同一分頁需要 invalidate」案例,同一個理由:
/// `StatefulShellRoute.indexedStack` 不 dispose 頁面,
/// `WorkoutStatsController.build()` 只在 provider 第一次建立時跑一次,使用者
/// 切去別的分頁記完一筆訓練再切回數據分頁,訓練統計子頁的容量趨勢/本週
/// 統計/最近訓練不會自動反映新資料。純函式,理由與測試慣例同
/// [shouldRefreshDashboardOnBranchSwitch]。
bool shouldRefreshStatsOnBranchSwitch(int targetIndex) => targetIndex == _statsBranchIndex;

/// session / onboarding 狀態改變時通知 GoRouter 重新評估 redirect(例如
/// 登入、登出、完成 Onboarding)。
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(sessionControllerProvider, (previous, next) => notifyListeners());
    ref.listen(onboardingStatusProvider, (previous, next) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final isLoggedIn = ref.read(sessionControllerProvider).isLoggedIn;
      final hasCompletedOnboarding = ref.read(onboardingStatusProvider);
      return resolveAuthRedirect(
        isLoggedIn: isLoggedIn,
        hasCompletedOnboarding: hasCompletedOnboarding,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return _AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/workout',
                builder: (context, state) => const WorkoutPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _AppShell extends ConsumerWidget {
  const _AppShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: '首頁',
    ),
    NavigationDestination(
      icon: Icon(Icons.fitness_center_outlined),
      selectedIcon: Icon(Icons.fitness_center),
      label: '訓練',
    ),
    NavigationDestination(
      icon: Icon(Icons.show_chart_outlined),
      selectedIcon: Icon(Icons.show_chart),
      label: '數據',
    ),
    NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month),
      label: '歷史',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: '設定',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
          if (shouldRefreshDashboardOnBranchSwitch(index)) {
            ref.invalidate(dashboardControllerProvider);
          }
          if (shouldRefreshStatsOnBranchSwitch(index)) {
            ref.invalidate(workoutStatsControllerProvider);
          }
        },
        destinations: _destinations,
      ),
    );
  }
}
