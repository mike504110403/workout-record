// 完成/放棄成功後 controller 收回 idle,`WorkoutPage` 會把進行中畫面換成空白
// ——若中間畫了一幀,發起完成/放棄的 widget 已被拆掉。真機上
// SharedPreferences.remove 走 platform channel,比一個 frame 慢(code review
// flow-fix 1 的重現:不彈結算、不回首頁)。這裡兩種角度各測一次:
// 1. 慢速 prefs(remove 延遲 0/30ms)+ 每 16ms pump 一幀:真 controller,完成要
//    彈結算、放棄要回首頁。
// 2. controller 在收回 idle 之後還要再等一段才回到 UI(人為製造空窗):UI 端
//    必須用進入時抓好的 navigator/`WorkoutExit`,不能依賴已被拆掉的 context。
// controller 端「清除先於 idle」的順序另見 planned_sets_test.dart。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 慢速 remove 的假 store 要直接實作平台介面;它是 shared_preferences 的傳遞
// 依賴(理由同 exercise_picker_controller_test.dart 的同一行)。
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/dashboard/dashboard_page.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/workout/workout_launcher.dart';
import 'package:workout_record/features/workout/workout_page.dart';

import '../../data/test_helpers.dart';

class _SlowRemoveStore extends InMemorySharedPreferencesStore {
  _SlowRemoveStore(super.data, this.delay) : super.withData();

  final Duration delay;

  @override
  Future<bool> remove(String key) async {
    await Future<void>.delayed(delay);
    return super.remove(key);
  }
}

/// 收回 idle 之後再等 30ms 才把結果交回 UI:這段期間 UI 會畫幀、拆掉進行中畫面。
class _LateReturnController extends WorkoutController {
  @override
  Future<WorkoutCompletionOutcome> completeWorkout() async {
    final outcome = await super.completeWorkout();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return outcome;
  }

  @override
  Future<void> abandonWorkout() async {
    await super.abandonWorkout();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<void> _run(
  WidgetTester tester, {
  required bool abandon,
  Duration removeDelay = Duration.zero,
  bool lateReturn = false,
}) async {
  final values = <String, Object>{
    kAppleUserIdKey: testUserId,
    kAppleUserNameKey: 'Test User',
    kAppleUserEmailKey: 'test@example.com',
    kHasCompletedOnboardingKey: true,
    kHasAgreedToAnalyticsKey: true,
    kHasAgreedToPrivacyKey: true,
    kPrivacyConsentDateKey: DateTime.now().millisecondsSinceEpoch,
  };
  SharedPreferences.setMockInitialValues(values);
  SharedPreferencesStorePlatform.instance = _SlowRemoveStore(
    {for (final e in values.entries) 'flutter.${e.key}': e.value},
    removeDelay,
  );
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (lateReturn) workoutControllerProvider.overrideWith(_LateReturnController.new),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const WorkItOutApp()));
  await tester.pumpAndSettle();

  // 首頁的 element 同時是 BuildContext 與 WidgetRef,等同首頁「開始訓練」。
  final home = tester.element(find.byType(DashboardPage));
  await openFreeWorkout(home, home as WidgetRef);
  await tester.pumpAndSettle();
  // 空白訓練會自動開選動作 sheet;關掉,改直接經 controller 加動作與組。
  Navigator.of(tester.element(find.byKey(const Key('exercise_picker_search_field')))).pop();
  await tester.pumpAndSettle();
  final exercise = (await DriftExerciseRepository(db).fetchAll()).first;
  final notifier = container.read(workoutControllerProvider.notifier);
  await notifier.addExercise(exercise);
  final weId = container.read(workoutControllerProvider).value!.draft!.exercises.single.id;
  await notifier.addSet(workoutExerciseId: weId, weight: 100, reps: 5);
  await tester.pumpAndSettle();

  if (abandon) {
    await tester.tap(find.byKey(const Key('workoutMoreMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('abandonWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('abandonWorkoutConfirmButton')));
  } else {
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
  }
  // 模擬真機:每 16ms 一個 frame(先過時間再畫 frame)。
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

void main() {
  group('慢速 prefs.remove + 每 16ms 一幀', () {
    for (final ms in [0, 30]) {
      testWidgets('完成(remove 延遲 ${ms}ms)→ 彈結算 sheet', (tester) async {
        await _run(tester, abandon: false, removeDelay: Duration(milliseconds: ms));
        expect(find.byKey(const Key('workoutSummaryDoneButton')), findsOneWidget);
      });

      testWidgets('放棄(remove 延遲 ${ms}ms)→ 回首頁', (tester) async {
        await _run(tester, abandon: true, removeDelay: Duration(milliseconds: ms));
        expect(find.byType(WorkoutPage, skipOffstage: false), findsNothing);
        expect(find.byType(DashboardPage).hitTestable(), findsOneWidget);
      });
    }
  });

  group('收回 idle 後畫面已拆掉,UI 仍要完成離開流程', () {
    testWidgets('完成 → 結算 sheet 照彈,關掉後回首頁', (tester) async {
      await _run(tester, abandon: false, lateReturn: true);
      expect(find.byKey(const Key('workoutSummaryDoneButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('workoutSummaryDoneButton')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutPage, skipOffstage: false), findsNothing);
      expect(find.byType(DashboardPage).hitTestable(), findsOneWidget);
    });

    testWidgets('放棄 → 回首頁', (tester) async {
      await _run(tester, abandon: true, lateReturn: true);
      expect(find.byType(WorkoutPage, skipOffstage: false), findsNothing);
      expect(find.byType(DashboardPage).hitTestable(), findsOneWidget);
    });
  });
}
