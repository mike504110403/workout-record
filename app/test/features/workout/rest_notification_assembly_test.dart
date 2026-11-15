// 真實組裝:掛真的 WorkoutInProgressView(真 in-memory DB + 真 repositories),
// 只把 RestNotificationScheduler 換成假的記錄呼叫。
// 記一組 → 休息計時啟動、scheduler 收到 schedule;放棄/完成訓練 → 收到 cancel。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/rest_notification_scheduler.dart';
import 'package:workout_record/features/workout/rest_timer_controller.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/workout/workout_in_progress_view.dart';

import '../../data/test_helpers.dart';
import 'fake_rest_notification_scheduler.dart';

Future<({FakeRestNotificationScheduler scheduler, ProviderContainer container, String exerciseName})>
_pumpWorkoutWithOneSet(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);
  final scheduler = FakeRestNotificationScheduler();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      restNotificationSchedulerProvider.overrideWithValue(scheduler),
      restTimerFinishedFeedbackProvider.overrideWithValue(() {}),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  final exercise = (await DriftExerciseRepository(db).fetchSystemExercises()).first;
  await container.read(workoutControllerProvider.future);
  await container.read(workoutControllerProvider.notifier).startFreeWorkout();

  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: WorkoutInProgressView())),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('addExerciseButtonEmptyState')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('exercise_picker_search_field')), exercise.name);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('exercise_checkbox_${exercise.id}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('exercise_picker_confirm_button')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('addSetWeightField')), '30');
  await tester.enterText(find.byKey(const Key('addSetRepsField')), '12');
  await tester.pump();
  await tester.tap(find.byKey(const Key('addSetSaveButton')));
  await tester.pumpAndSettle();
  return (scheduler: scheduler, container: container, exerciseName: exercise.name);
}

void main() {
  testWidgets('記一組 → scheduler 先 cancel 再 schedule(帶動作名);放棄訓練 → cancel', (tester) async {
    final h = await _pumpWorkoutWithOneSet(tester);
    expect(h.container.read(restTimerControllerProvider).isRunning, isTrue);
    expect(find.byKey(const Key('restTimerBar')), findsOneWidget);
    expect(h.scheduler.calls.first, 'cancel');
    expect(h.scheduler.calls.last, startsWith('schedule('));
    expect(h.scheduler.calls.last, endsWith(',${h.exerciseName})'));
    expect(h.scheduler.calls.where((c) => c.startsWith('schedule(')), hasLength(1));

    h.scheduler.calls.clear();
    await tester.tap(find.byKey(const Key('workoutMoreMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('abandonWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('abandonWorkoutConfirmButton')));
    await tester.pumpAndSettle();

    expect(h.scheduler.calls, contains('cancel'));
    expect(h.scheduler.calls.where((c) => c.startsWith('schedule(')), isEmpty);
    expect(h.container.read(restTimerControllerProvider).isRunning, isFalse);
  });

  testWidgets('記一組 → 完成訓練 → scheduler 收到 cancel', (tester) async {
    final h = await _pumpWorkoutWithOneSet(tester);
    expect(h.scheduler.calls.last, startsWith('schedule('));

    h.scheduler.calls.clear();
    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    // 完成改為延遲 4 秒可復原(workout_pending_actions.dart):推過復原期才真的結算。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(h.scheduler.calls, contains('cancel'));
    expect(h.scheduler.calls.where((c) => c.startsWith('schedule(')), isEmpty);
    expect(h.container.read(restTimerControllerProvider).isRunning, isFalse);
  });
}
