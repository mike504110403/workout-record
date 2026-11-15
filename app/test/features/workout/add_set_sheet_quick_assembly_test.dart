// 記組 sheet 快捷鈕的真實組裝路徑:真 WorkItOutApp(go_router 殼 + 全螢幕訓練頁)
// + 真 Drift repository(in-memory)。首頁開始訓練 → 選動作 → 記組 sheet 自動開 →
// 點 +10 / +20 快捷鈕 → 存檔 → 斷言 DB 寫入的組重量(kg)與休息計時列出現。
// harness 複製自 workout_flow_e2e_test.dart(該檔不動)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/db/app_database.dart' hide Workout, WorkoutExercise, WorkoutSet;
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/dashboard/dashboard_page.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';
import 'package:workout_record/features/workout/workout_launcher.dart';

import '../../data/test_helpers.dart';

Future<({AppDatabase db, ProviderContainer container})> _setUp({String? weightUnit}) async {
  SharedPreferences.setMockInitialValues({
    kAppleUserIdKey: testUserId,
    kAppleUserNameKey: 'Test User',
    kAppleUserEmailKey: 'test@example.com',
    kHasCompletedOnboardingKey: true,
    kHasAgreedToAnalyticsKey: true,
    kHasAgreedToPrivacyKey: true,
    kPrivacyConsentDateKey: DateTime.now().millisecondsSinceEpoch,
    kWeightUnitPrefsKey: ?weightUnit,
  });
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (db: db, container: container);
}

Future<void> _pumpAndStart(
  WidgetTester tester,
  ({AppDatabase db, ProviderContainer container}) h,
) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: h.container, child: const WorkItOutApp()),
  );
  await tester.pumpAndSettle();

  final home = tester.element(find.byType(DashboardPage));
  await openFreeWorkout(home, home as WidgetRef);
  await tester.pumpAndSettle();

  final exercises = await DriftExerciseRepository(h.db).fetchAll();
  // 進行中頁選動作器是多選:勾 1 個再按確認(仍自動開記組視窗)。
  final row = find.byKey(Key('exercise_checkbox_${exercises.first.id}'));
  await tester.scrollUntilVisible(
    row,
    120,
    scrollable: find
        .descendant(of: find.byKey(const Key('exercise_picker_list')), matching: find.byType(Scrollable))
        .first,
  );
  await tester.tap(row);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('exercise_picker_confirm_button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('addSetWeightField')), findsOneWidget);
}

/// 收尾:完成訓練 → 結算 → 回首頁(休息計時器隨之取消,測試結束無 pending timer)。
Future<void> _finish(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('completeWorkoutButton')));
  await tester.pump();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('workoutSummaryDoneButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('進行中訓練頁記組:空欄點 +10、+20 快捷鈕 → 存檔 → DB 組重量 30 kg', (tester) async {
    final h = await _setUp();
    await _pumpAndStart(tester, h);

    await tester.tap(find.byKey(const Key('addSetWeightQuick_10')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSetWeightQuick_20')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('addSetWeightField'))).controller!.text, '30');
    await tester.enterText(find.byKey(const Key('addSetRepsField')), '5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSetSaveButton')));
    await tester.pumpAndSettle();

    final draft = await DriftWorkoutRepository(h.db, DriftExerciseRepository(h.db)).fetchDraft(testUserId);
    final sets = draft!.exercises.single.sets;
    expect(sets, hasLength(1));
    expect(sets.single.weight, 30);
    expect(sets.single.reps, 5);
    await _finish(tester);
  });

  testWidgets('lb 偏好:點 +10 → 輸入框 10 lb,存檔寫入 kg 換算值', (tester) async {
    final h = await _setUp(weightUnit: 'lb');
    await _pumpAndStart(tester, h);
    expect(find.text('重量 (lb)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('addSetWeightQuick_10')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addSetRepsField')), '8');
    await tester.pump();
    await tester.tap(find.byKey(const Key('addSetSaveButton')));
    await tester.pumpAndSettle();

    final draft = await DriftWorkoutRepository(h.db, DriftExerciseRepository(h.db)).fetchDraft(testUserId);
    expect(draft!.exercises.single.sets.single.weight, closeTo(10 / kLbPerKg, 1e-6));
    await _finish(tester);
  });
}
