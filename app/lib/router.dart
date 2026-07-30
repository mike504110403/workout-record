import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/login_page.dart';
import 'features/auth/session_controller.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/history/history_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/onboarding/onboarding_status.dart';
import 'features/settings/settings_page.dart';
import 'features/stats/stats_page.dart';
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

class _AppShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: _destinations,
      ),
    );
  }
}
