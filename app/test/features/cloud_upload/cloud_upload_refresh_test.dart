// 登入後舊紀錄上傳成功時,已經查過一次的分頁要重新查詢(畢業總審 M2)。
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
import 'package:workout_record/features/cloud_upload/cloud_upload_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';
import 'package:workout_record/features/workout/exercise_history.dart';

import '../../data/test_helpers.dart';

class _FakeUploadController extends CloudUploadController {
  void emit(CloudUploadStatus status) => state = status;
}

void main() {
  testWidgets('舊紀錄上傳成功 → 已顯示的歷史分頁重新查詢,並提示同步完成', (tester) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          cloudUploadControllerProvider.overrideWith(_FakeUploadController.new),
        ],
        child: const WorkItOutApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NavigationDestination, '歷史'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('historyEmptyState')), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(WorkItOutApp)));
    final upload = container.read(cloudUploadControllerProvider.notifier) as _FakeUploadController;
    upload.emit(const CloudUploadStatus(CloudUploadPhase.uploading));
    await tester.pump();
    expect(find.text('正在把舊紀錄同步到雲端…'), findsOneWidget);

    // 上傳期間資料落地(雲端模式下即「雲端多了這批舊紀錄」),不切分頁。
    final now = DateTime.now();
    await DriftWorkoutRepository(db, DriftExerciseRepository(db)).create(
      Workout(
        id: 'uploaded-legacy',
        userId: testUserId,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 20)),
        duration: 20,
        totalVolume: 321,
        totalSets: 3,
        totalExercises: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    upload.emit(const CloudUploadStatus(CloudUploadPhase.succeeded, uploadedRows: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('historyEmptyState')), findsNothing);
    expect(find.byKey(const Key('historyWorkoutCard-uploaded-legacy')), findsOneWidget);
    expect(find.text('舊紀錄已同步完成'), findsOneWidget);
  });

  testWidgets('舊紀錄上傳成功 → 訓練用的「最近用過/上次數字」快照也重查(flow-fix 8)', (tester) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          cloudUploadControllerProvider.overrideWith(_FakeUploadController.new),
        ],
        child: const WorkItOutApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(WorkItOutApp)));
    // 上傳前已查過一次(空的),成功結果會一直留著。
    final before = await tester.runAsync(() => container.read(exerciseHistoryProvider.future));
    expect(before!.recentExerciseIds, isEmpty);

    final exercise = (await tester.runAsync(() => DriftExerciseRepository(db).fetchSystemExercises()))!.first;
    final at = DateTime(2026, 11, 1, 9);
    await tester.runAsync(
      () => DriftWorkoutRepository(db, DriftExerciseRepository(db)).create(
        Workout(
          id: 'uploaded-legacy',
          userId: testUserId,
          startedAt: at,
          endedAt: at.add(const Duration(minutes: 20)),
          createdAt: at,
          updatedAt: at,
          exercises: [
            WorkoutExercise(
              id: 'uploaded-we',
              workoutId: 'uploaded-legacy',
              exerciseId: exercise.id,
              exerciseName: exercise.name,
              createdAt: at,
              updatedAt: at,
              sets: [
                WorkoutSet(
                  id: 'uploaded-s1',
                  workoutExerciseId: 'uploaded-we',
                  setNumber: 1,
                  weight: 55,
                  reps: 5,
                  createdAt: at,
                  updatedAt: at,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final upload = container.read(cloudUploadControllerProvider.notifier) as _FakeUploadController;
    upload.emit(const CloudUploadStatus(CloudUploadPhase.uploading));
    await tester.pump();
    upload.emit(const CloudUploadStatus(CloudUploadPhase.succeeded, uploadedRows: 1));
    await tester.pumpAndSettle();

    final after = await tester.runAsync(() => container.read(exerciseHistoryProvider.future));
    expect(after!.lastSetFor(exercise.id)?.weight, 55);
  });
}
