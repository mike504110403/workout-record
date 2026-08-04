// resolveAuthRedirect 是純函式(見 app/lib/router.dart),不吃 BuildContext /
// GoRouterState,直接窮舉(登入狀態 × Onboarding 狀態 × 目前路徑)矩陣。
//
// shouldRefreshDashboardOnBranchSwitch 同樣是純函式(見 app/lib/router.dart)
// ——決定「切到哪個分頁 index 時該重新整理首頁」的判斷邏輯,獨立於 _AppShell
// 的 ref.invalidate 呼叫本身(那一半的行為由
// test/features/dashboard/dashboard_shell_revisit_test.dart 驗證:pump 真
// App、點真 nav bar,斷言切回首頁後重新查詢)。

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/router.dart';

void main() {
  group('resolveAuthRedirect', () {
    test('未登入時,不論目前在哪個路徑,一律導去 /login', () {
      expect(
        resolveAuthRedirect(
          isLoggedIn: false,
          hasCompletedOnboarding: false,
          location: '/dashboard',
        ),
        '/login',
      );
      expect(
        resolveAuthRedirect(
          isLoggedIn: false,
          hasCompletedOnboarding: true,
          location: '/onboarding',
        ),
        '/login',
      );
    });

    test('未登入且已經在 /login 時,不重導向(避免無窮迴圈)', () {
      expect(
        resolveAuthRedirect(
          isLoggedIn: false,
          hasCompletedOnboarding: false,
          location: '/login',
        ),
        isNull,
      );
    });

    test('已登入但未完成 Onboarding 時,導去 /onboarding', () {
      expect(
        resolveAuthRedirect(
          isLoggedIn: true,
          hasCompletedOnboarding: false,
          location: '/dashboard',
        ),
        '/onboarding',
      );
      expect(
        resolveAuthRedirect(
          isLoggedIn: true,
          hasCompletedOnboarding: false,
          location: '/login',
        ),
        '/onboarding',
      );
    });

    test('已登入且未完成 Onboarding、已經在 /onboarding 時,不重導向', () {
      expect(
        resolveAuthRedirect(
          isLoggedIn: true,
          hasCompletedOnboarding: false,
          location: '/onboarding',
        ),
        isNull,
      );
    });

    test('已登入且已完成 Onboarding、停在 /login 或 /onboarding 時,導去 /dashboard', () {
      expect(
        resolveAuthRedirect(
          isLoggedIn: true,
          hasCompletedOnboarding: true,
          location: '/login',
        ),
        '/dashboard',
      );
      expect(
        resolveAuthRedirect(
          isLoggedIn: true,
          hasCompletedOnboarding: true,
          location: '/onboarding',
        ),
        '/dashboard',
      );
    });

    test('都完成時,停在一般分頁不重導向', () {
      for (final location in ['/dashboard', '/workout', '/stats', '/history', '/settings']) {
        expect(
          resolveAuthRedirect(
            isLoggedIn: true,
            hasCompletedOnboarding: true,
            location: location,
          ),
          isNull,
          reason: 'location=$location 不應被重導向',
        );
      }
    });
  });

  group('shouldRefreshDashboardOnBranchSwitch', () {
    test('切到首頁分頁(index 0)時回傳 true', () {
      expect(shouldRefreshDashboardOnBranchSwitch(0), isTrue);
    });

    test('切到其他分頁(訓練/數據/歷史/設定)時回傳 false', () {
      for (final index in [1, 2, 3, 4]) {
        expect(
          shouldRefreshDashboardOnBranchSwitch(index),
          isFalse,
          reason: 'index=$index 不應觸發首頁重新整理',
        );
      }
    });
  });
}
