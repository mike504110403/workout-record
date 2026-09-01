import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/login_page.dart';
import 'features/auth/session_controller.dart';
import 'features/dashboard/dashboard_controller.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/history/history_calendar_controller.dart';
import 'features/history/history_list_controller.dart';
import 'features/history/history_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/onboarding/onboarding_status.dart';
import 'features/settings/settings_page.dart';
import 'features/stats/body_weight/body_weight_controller.dart';
import 'features/stats/powerlifting/powerlifting_controller.dart';
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
/// 純函式,不吃 BuildContext/WidgetRef,方便單獨單元測試(見
/// test/router/router_redirect_test.dart;實際「切分頁真的觸發 invalidate」
/// 這條線的行為測在 test/features/dashboard/dashboard_shell_revisit_test.dart
/// ——純函式測試只守「index 對應」,守不住接線本身有沒有真的呼叫)。
///
/// r2 review 打回記錄(major 2):這個判斷式原本只掛在 `_AppShell` 的
/// `NavigationBar.onDestinationSelected` callback 裡——只有「點 bottom nav
/// 分頁圖示」這條路徑會觸發。Dashboard 的「查看進度」快速操作走
/// `context.go('/stats')` 直接改變路由,不經過 `onDestinationSelected`,
/// reviewer 實測發現這條路徑切到數據分頁後畫面停在舊資料。改法見
/// `_AppShellState.didUpdateWidget`:改成觀察 `navigationShell.currentIndex`
/// 本身的變化(不管是哪條路徑造成的),這個判斷式現在被兩處共用,依然是
/// 純函式,行為不變。
bool shouldRefreshDashboardOnBranchSwitch(int targetIndex) => targetIndex == _dashboardBranchIndex;

/// 「數據」在 5-tab shell 裡的 branch index——與下方 `branches:` 陣列順序
/// 一致(首頁 0 / 訓練 1 / 數據 2 / 歷史 3 / 設定 4)。
const _statsBranchIndex = 2;

/// 波 4 補上的第二個「回訪同一分頁需要 invalidate」案例,同一個理由:
/// `StatefulShellRoute.indexedStack` 不 dispose 頁面,
/// `WorkoutStatsController.build()` 只在 provider 第一次建立時跑一次,使用者
/// 切去別的分頁記完一筆訓練再切回數據分頁,訓練統計子頁的容量趨勢/本週
/// 統計/最近訓練不會自動反映新資料。純函式,理由與測試慣例同
/// [shouldRefreshDashboardOnBranchSwitch](含上面那則 major 2 打回記錄)。
bool shouldRefreshStatsOnBranchSwitch(int targetIndex) => targetIndex == _statsBranchIndex;

/// 「歷史」在 5-tab shell 裡的 branch index——與下方 `branches:` 陣列順序
/// 一致(首頁 0 / 訓練 1 / 數據 2 / 歷史 3 / 設定 4)。
const _historyBranchIndex = 3;

/// 波 5 補上的第三個「回訪同一分頁需要 invalidate」案例,理由同上兩支:
/// `StatefulShellRoute.indexedStack` 不 dispose 頁面,歷史列表/日曆的
/// controller 皆非 autoDispose,使用者在訓練分頁完成一筆訓練再切到歷史
/// 分頁,列表與日曆不會自動反映新資料。純函式,理由與測試慣例同
/// [shouldRefreshDashboardOnBranchSwitch]。
bool shouldRefreshHistoryOnBranchSwitch(int targetIndex) => targetIndex == _historyBranchIndex;

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

/// r2 review 打回記錄(major 2):原本是 `ConsumerWidget`,失效邏輯掛在
/// `NavigationBar.onDestinationSelected` 這一條路徑上。改成
/// `ConsumerStatefulWidget` 是為了拿到 `didUpdateWidget`——GoRouter 的
/// `StatefulShellRoute.indexedStack` 不管分頁切換是透過 bottom nav 點擊
/// (`goBranch`)還是程式化導航(例如 Dashboard 快速操作的
/// `context.go('/stats')`)造成,只要 `navigationShell.currentIndex` 真的
/// 變了,這個 builder 就會用新的 `navigationShell` 重新呼叫,連帶讓
/// `_AppShell` 的 `didUpdateWidget` 觸發——比掛在單一按鈕的 callback 上更
/// 底層,涵蓋所有能改變分頁 index 的路徑,不用每加一條新路徑就要多補一處
/// invalidate。
class _AppShell extends ConsumerStatefulWidget {
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
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  @override
  void didUpdateWidget(covariant _AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = oldWidget.navigationShell.currentIndex;
    final newIndex = widget.navigationShell.currentIndex;
    if (oldIndex == newIndex) return;
    _refreshForBranch(newIndex);
  }

  /// 「切進某個分頁」的統一失效點——不管是 bottom nav 點擊還是程式化
  /// `context.go` 導致的切換,都會經過這裡剛好一次(見類別文件註解)。
  /// `onDestinationSelected` 不再重複呼叫 `ref.invalidate`,避免同一次切換
  /// 觸發兩次查詢(選擇:單一掛點,不是「兩處都掛、各自防重入」——後者要
  /// 多維護一份去重狀態,沒有必要)。
  void _refreshForBranch(int index) {
    if (shouldRefreshDashboardOnBranchSwitch(index)) {
      ref.invalidate(dashboardControllerProvider);
    }
    if (shouldRefreshStatsOnBranchSwitch(index)) {
      // 三個子頁 provider 一起失效(IndexedStack 不 dispose、皆非
      // autoDispose,切回「數據」分頁要主動重新查詢;WAVE4 merge 時由大腦
      // 接線)。PR 排行頁(prListControllerProvider)不掛這裡——它是
      // Navigator.push 的獨立頁,每次進入由 PrListPage 自行取得最新狀態。
      ref.invalidate(workoutStatsControllerProvider);
      ref.invalidate(bodyWeightTabControllerProvider);
      ref.invalidate(powerliftingControllerProvider);
    }
    if (shouldRefreshHistoryOnBranchSwitch(index)) {
      // 歷史列表/日曆一起失效(同上:IndexedStack 不 dispose、皆非
      // autoDispose;WAVE5 merge 時由大腦接線)。訓練詳情/編輯頁不掛這裡
      // ——它們是 Navigator.push 的獨立頁,編輯返回的刷新由
      // WorkoutDetailPage 自行處理。
      ref.invalidate(historyListControllerProvider);
      ref.invalidate(historyCalendarControllerProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: (index) {
          widget.navigationShell.goBranch(
            index,
            initialLocation: index == widget.navigationShell.currentIndex,
          );
        },
        destinations: _AppShell._destinations,
      ),
    );
  }
}
