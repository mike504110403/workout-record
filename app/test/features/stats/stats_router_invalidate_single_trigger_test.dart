// r2 review 打回記錄(major 2,「不得雙重觸發」的要求):把 invalidate 邏輯
// 從 `onDestinationSelected` 搬到 `_AppShellState.didUpdateWidget` 後,同一
// 次切分頁只會經過一個掛點——這裡直接數 `fetchByDateRange` 被呼叫的次數,
// 證明單次切進數據分頁只觸發一次完整的重新查詢(每次 `_load()` 恰好呼叫
// 一次 `fetchByDateRange`),不是兩次(例如不小心兩處掛點都保留、各自
// invalidate 一次疊加成雙重查詢)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';

import '../../data/test_helpers.dart';

class _CountingWorkoutRepository extends WorkoutRepository {
  _CountingWorkoutRepository(super.db, super.exerciseRepository);

  var fetchByDateRangeCallCount = 0;

  @override
  Future<List<Workout>> fetchByDateRange(DateTime from, DateTime to) {
    fetchByDateRangeCallCount += 1;
    return super.fetchByDateRange(from, to);
  }
}

void main() {
  testWidgets('單次切進數據分頁只觸發一次 fetchByDateRange,不是兩次', (tester) async {
    SharedPreferences.setMockInitialValues({
      kAppleUserIdKey: testUserId,
      kAppleUserNameKey: 'Test User',
      kAppleUserEmailKey: 'test@example.com',
      kHasCompletedOnboardingKey: true,
      kHasAgreedToAnalyticsKey: true,
      kHasAgreedToPrivacyKey: true,
      kPrivacyConsentDateKey: DateTime.now().millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    final db = openTestDatabase();
    addTearDown(db.close);
    await seedTestUser(db);
    final repo = _CountingWorkoutRepository(db, ExerciseRepository(db));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          workoutRepositoryProvider.overrideWithValue(repo),
        ],
        child: const WorkItOutApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 第一次切進數據分頁(bottom nav):provider 第一次 build()。首次造訪
    // 牽涉 provider 初始建立時機,不是本測試要驗證的「revisit」場景
    // (那才是 router.dart invalidate 邏輯實際起作用的地方)——這裡只是先
    // 讓它發生、把當時的呼叫數記下來當基準,不斷言它的絕對值。
    await tester.tap(find.widgetWithText(NavigationDestination, '數據'));
    await tester.pumpAndSettle();
    final countAfterFirstVisit = repo.fetchByDateRangeCallCount;

    // 切走再切回——這是本測試要驗證的「單次 revisit 只觸發一次查詢」場景。
    await tester.tap(find.widgetWithText(NavigationDestination, '訓練'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '數據'));
    await tester.pumpAndSettle();

    expect(
      repo.fetchByDateRangeCallCount,
      countAfterFirstVisit + 1,
      reason: '單次切回數據分頁應該恰好多觸發一次查詢,不是兩次(雙重掛點的話會是 +2)',
    );
  });
}
