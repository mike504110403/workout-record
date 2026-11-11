// 訓練核心流端到端測試:pump 真 `WorkItOutApp`(真 go_router 4-tab 殼 + shell
// 外的全螢幕 `/workout`)——repositories/provider 一律用真的,只換
// appDatabaseProvider(in-memory)與 sharedPreferencesProvider(mock prefs)。
//
// ui-polish(2026-11-11)後的入口是首頁 → 訓練入口契約(workout_launcher.dart)。
// 首頁按鈕怎麼接是首頁切片的事,這裡直接拿首頁的 element 當 context/ref 呼叫
// launcher,等同使用者按下首頁「開始訓練」/模板 chip。覆蓋:
// 1. 首頁開始 → 自動開選動作 → 選完自動開記組 → 記兩組 → 完成 → 結算 → 回首頁,
//    首頁重查(本週次數 +1、最近訓練出現該筆)。
// 2. 模板開始 → 計畫組灰色、DB 0 組 → 打勾兩組 → 完成(0 組動作被丟棄)→ 回首頁。
// 3. 返回(收起)保留草稿、首頁重查顯示有草稿;放棄回首頁。
// 4. launcher 防重複 push:連點兩下、chip 連點、已在訓練頁再呼叫 openCurrentWorkout。
// 5. 啟動時有草稿 → 殼層對話框 → 繼續進訓練頁 / 放棄後首頁顯示「開始訓練」。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/data/db/app_database.dart' hide Workout, WorkoutExercise, WorkoutSet;
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/template_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/dashboard/dashboard_controller.dart';
import 'package:workout_record/features/dashboard/dashboard_page.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/privacy/privacy_consent_controller.dart';
import 'package:workout_record/features/workout/templates/applied_template.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/workout/workout_launcher.dart';
import 'package:workout_record/features/workout/workout_page.dart';

import '../../data/test_helpers.dart';

typedef _Harness = ({AppDatabase db, ProviderContainer container});

Future<_Harness> _setUpLoggedInHarness() async {
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

Future<void> _pumpApp(WidgetTester tester, _Harness harness) async {
  // 選動作器是撐到螢幕高度的 bottom sheet、清單 66 筆——放大視窗,理由同
  // templates_crud_test.dart:ListView 只 mount 進視窗(含 cacheExtent)內的子項。
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const WorkItOutApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// 首頁的 element 同時是 BuildContext 與 WidgetRef(ConsumerWidget),用它呼叫
/// launcher 等同首頁按鈕的接線。
({BuildContext context, WidgetRef ref}) _home(WidgetTester tester) {
  final element = tester.element(find.byType(DashboardPage));
  return (context: element, ref: element as WidgetRef);
}

Future<void> _pickExerciseSingle(WidgetTester tester, String exerciseId) async {
  final row = find.byKey(Key('exercise_row_$exerciseId'));
  await tester.scrollUntilVisible(
    row,
    120,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('exercise_picker_list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _fillAddSetSheet(
  WidgetTester tester, {
  required String weight,
  required String reps,
  bool isWarmup = false,
}) async {
  await tester.enterText(find.byKey(const Key('addSetWeightField')), weight);
  await tester.enterText(find.byKey(const Key('addSetRepsField')), reps);
  if (isWarmup) {
    // 暖身開關在預設收合的「進階選項」內,先展開。
    await tester.tap(find.text('進階選項'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addSetWarmupSwitch')));
  }
  await tester.pump();
  await tester.tap(find.byKey(const Key('addSetSaveButton')));
  await tester.pumpAndSettle();
}

/// 全螢幕訓練頁在最上層、導覽列不可見。
void _expectOnWorkoutPage() {
  expect(find.byType(WorkoutPage), findsOneWidget);
  expect(find.byType(NavigationBar).hitTestable(), findsNothing);
}

/// 回到首頁分頁、導覽列可見、沒有訓練頁殘留在堆疊。
void _expectOnDashboard() {
  expect(find.byType(WorkoutPage, skipOffstage: false), findsNothing);
  expect(find.byType(DashboardPage).hitTestable(), findsOneWidget);
  expect(find.byType(NavigationBar).hitTestable(), findsOneWidget);
}

DashboardState _dashboard(_Harness h) => h.container.read(dashboardControllerProvider).value!;

Future<AppliedTemplate> _systemTemplate(AppDatabase db, String name) async {
  final templates = await DriftTemplateRepository(db, DriftExerciseRepository(db)).fetchSystemTemplates();
  return applyTemplate(templates.firstWhere((t) => t.name == name));
}

void main() {
  testWidgets(
    '首頁開始 → 自動開選動作 → 選完自動開記組 → 記一暖身一正式組 → 完成 → 結算 → 回首頁,首頁重查',
    (tester) async {
      final harness = await _setUpLoggedInHarness();
      final exercises = await DriftExerciseRepository(harness.db).fetchAll();
      final targetExercise = exercises.first;

      await _pumpApp(tester, harness);
      expect(_dashboard(harness).weekWorkoutCount, 0);

      final home = _home(tester);
      // 點擊 1:首頁「開始訓練」。
      await openFreeWorkout(home.context, home.ref);
      await tester.pumpAndSettle();

      // 全螢幕、無導覽列,選動作 sheet 已自動打開(搜尋框置頂、沒有標題列)。
      _expectOnWorkoutPage();
      expect(find.byKey(const Key('exercise_picker_search_field')), findsOneWidget);
      expect(find.byKey(const Key('exercise_picker_cancel_button')), findsNothing);

      // 點擊 2:選動作 → 記組 sheet 自動打開(第一組,沒有歷史 → 空白)。
      await _pickExerciseSingle(tester, targetExercise.id);
      expect(find.byKey(const Key('addSetWeightField')), findsOneWidget);
      expect(find.text('第 1 組'), findsOneWidget);

      // 點擊 3(+ 輸入):第一組暖身組 → 儲存。
      await _fillAddSetSheet(tester, weight: '20', reps: '10', isWarmup: true);
      final workoutRepo = DriftWorkoutRepository(harness.db, DriftExerciseRepository(harness.db));
      final draft = await workoutRepo.fetchDraft(testUserId);
      final workoutExerciseId = draft!.exercises.single.id;
      expect(draft.exercises.single.sets, hasLength(1));
      // 暖身組不啟動休息計時器。
      expect(find.byKey(const Key('restTimerBar')), findsNothing);

      // 第二組:正式組,上一組的重量/次數預填。
      await tester.tap(find.byKey(Key('addSetButton_$workoutExerciseId')));
      await tester.pumpAndSettle();
      expect(find.text('20'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      await _fillAddSetSheet(tester, weight: '100', reps: '5');
      expect(find.byKey(const Key('restTimerBar')), findsOneWidget);

      // 不需要「完成動作」:直接完成訓練,沒有確認框。
      await tester.tap(find.byKey(const Key('completeWorkoutButton')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // 結算:暖身組(20x10=200)排除,只計正式組(100x5=500)。
      expect(
        find.descendant(of: find.byKey(const Key('summaryVolumeValue')), matching: find.text('500 kg')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('summarySetsValue')), matching: find.text('1')),
        findsOneWidget,
      );

      // 結算「完成」→ 回首頁,首頁重新查詢:本週次數 +1、最近訓練出現該筆。
      await tester.tap(find.byKey(const Key('workoutSummaryDoneButton')));
      await tester.pumpAndSettle();
      _expectOnDashboard();
      final dash = _dashboard(harness);
      expect(dash.weekWorkoutCount, 1);
      expect(dash.recentWorkouts.map((w) => w.id), contains(draft.id));
      expect(dash.hasDraftWorkout, isFalse);
      // 首頁版面:這筆訓練由「最近訓練」列呈現,總容量排除暖身組(500 kg)。
      final recentRow = find.byKey(Key('recentWorkoutRow-${draft.id}'));
      expect(recentRow, findsOneWidget);
      expect(find.descendant(of: recentRow, matching: find.text('500 kg')), findsOneWidget);
    },
  );

  testWidgets('模板開始 → 計畫組(DB 0 組)→ 打勾兩組 → 完成(沒組的動作被丟棄)→ 回首頁', (tester) async {
    final harness = await _setUpLoggedInHarness();
    await _pumpApp(tester, harness);
    final template = await _systemTemplate(harness.db, '全身訓練');

    final home = _home(tester);
    await openTemplateWorkout(home.context, home.ref, template);
    await tester.pumpAndSettle();

    _expectOnWorkoutPage();
    // 模板開始不自動開選動作。
    expect(find.byKey(const Key('exercise_picker_search_field')), findsNothing);

    final workoutRepo = DriftWorkoutRepository(harness.db, DriftExerciseRepository(harness.db));
    final draft = (await workoutRepo.fetchDraft(testUserId))!;
    expect(draft.exercises, hasLength(5)); // 全身訓練模板固定 5 個動作
    expect(draft.exercises.every((e) => e.sets.isEmpty), isTrue, reason: '模板的組不寫成真實組');

    final flow = harness.container.read(workoutControllerProvider).value!;
    final squat = draft.exercises.first;
    final planned = flow.plannedSets[squat.id]!;
    expect(planned, hasLength(3));
    for (final p in planned) {
      expect(find.byKey(Key('plannedSetRow_${p.id}')), findsOneWidget);
    }

    // 打勾兩組 → 變成真實組。
    await tester.tap(find.byKey(Key('confirmPlannedSet_${planned[0].id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('confirmPlannedSet_${planned[1].id}')));
    await tester.pumpAndSettle();

    final afterConfirm = (await workoutRepo.fetchById(draft.id))!;
    expect(afterConfirm.exercises.first.sets, hasLength(2));
    expect(find.byKey(Key('plannedSetRow_${planned[0].id}')), findsNothing);
    expect(find.byKey(Key('plannedSetRow_${planned[2].id}')), findsOneWidget);

    await tester.tap(find.byKey(const Key('completeWorkoutButton')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    // 其餘 4 個動作 0 組 → 完成時自動丟棄,結算只剩 1 個動作。
    expect(
      find.descendant(of: find.byKey(const Key('summaryExercisesValue')), matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('workoutSummaryDoneButton')));
    await tester.pumpAndSettle();
    _expectOnDashboard();
    expect(_dashboard(harness).weekWorkoutCount, 1);
  });

  testWidgets('返回(收起)保留草稿回首頁,首頁重查顯示有草稿;再進入後放棄 → 回首頁、草稿清掉', (tester) async {
    final harness = await _setUpLoggedInHarness();
    await _pumpApp(tester, harness);
    expect(_dashboard(harness).hasDraftWorkout, isFalse);

    final home = _home(tester);
    await openFreeWorkout(home.context, home.ref);
    await tester.pumpAndSettle();
    // 關掉自動打開的選動作 sheet(下滑/點外面 = pop)。
    Navigator.of(tester.element(find.byKey(const Key('exercise_picker_search_field')))).pop();
    await tester.pumpAndSettle();
    _expectOnWorkoutPage();

    // 系統返回(iOS 返回手勢/Android 返回鍵走同一條 Navigator pop)。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    _expectOnDashboard();
    expect(_dashboard(harness).hasDraftWorkout, isTrue, reason: '返回後首頁要重查才看得到草稿');
    expect(harness.container.read(workoutControllerProvider).value!.draft, isNotNull);

    // 再進入(繼續訓練)→ 收起鈕也回首頁。
    openCurrentWorkout(_home(tester).context);
    await tester.pumpAndSettle();
    _expectOnWorkoutPage();
    expect(find.byKey(const Key('exercise_picker_search_field')), findsNothing, reason: '繼續訓練不自動開選動作');

    // 放棄 → 回首頁、首頁不再顯示草稿。
    await tester.tap(find.byKey(const Key('workoutMoreMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('abandonWorkoutButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('abandonWorkoutConfirmButton')));
    await tester.pumpAndSettle();
    _expectOnDashboard();
    expect(_dashboard(harness).hasDraftWorkout, isFalse);
  });

  testWidgets('收起鈕:回到原分頁、草稿保留', (tester) async {
    final harness = await _setUpLoggedInHarness();
    await _pumpApp(tester, harness);
    final home = _home(tester);
    await openFreeWorkout(home.context, home.ref);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byKey(const Key('exercise_picker_search_field')))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('workoutMinimizeButton')));
    await tester.pumpAndSettle();

    _expectOnDashboard();
    expect(_dashboard(harness).hasDraftWorkout, isTrue);
  });

  group('launcher 防重複 push(堆疊只能有一層 /workout)', () {
    testWidgets('開始訓練連點兩下 → 一個訓練頁、一筆草稿', (tester) async {
      final harness = await _setUpLoggedInHarness();
      await _pumpApp(tester, harness);
      final home = _home(tester);

      final first = openFreeWorkout(home.context, home.ref);
      final second = openFreeWorkout(home.context, home.ref);
      await tester.pumpAndSettle();
      await Future.wait([first, second]);
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutPage, skipOffstage: false), findsOneWidget);
      expect(await harness.db.select(harness.db.workouts).get(), hasLength(1));
    });

    testWidgets('模板 chip 連點兩下 → 一個訓練頁', (tester) async {
      final harness = await _setUpLoggedInHarness();
      await _pumpApp(tester, harness);
      final template = await _systemTemplate(harness.db, '全身訓練');
      final home = _home(tester);

      final first = openTemplateWorkout(home.context, home.ref, template);
      final second = openTemplateWorkout(home.context, home.ref, template);
      await tester.pumpAndSettle();
      await Future.wait([first, second]);
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutPage, skipOffstage: false), findsOneWidget);
    });

    testWidgets('已在訓練頁再呼叫 openCurrentWorkout → 仍只有一個訓練頁', (tester) async {
      final harness = await _setUpLoggedInHarness();
      await _pumpApp(tester, harness);
      final home = _home(tester);
      await openTemplateWorkout(home.context, home.ref, await _systemTemplate(harness.db, '全身訓練'));
      await tester.pumpAndSettle();
      _expectOnWorkoutPage();

      openCurrentWorkout(tester.element(find.byType(WorkoutPage)));
      await tester.pumpAndSettle();
      openCurrentWorkout(home.context);
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutPage, skipOffstage: false), findsOneWidget);
      // 返回一次就回首頁(沒有第二層訓練頁)。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      _expectOnDashboard();
    });
  });

  group('啟動時有未完成草稿(殼層對話框)', () {
    Future<String> seedDraft(AppDatabase db) async {
      final repo = DriftWorkoutRepository(db, DriftExerciseRepository(db));
      final startedAt = DateTime(2026, 3, 1, 9);
      await repo.create(
        Workout(id: 'recoverable-draft', userId: testUserId, startedAt: startedAt, createdAt: startedAt, updatedAt: startedAt),
      );
      return 'recoverable-draft';
    }

    testWidgets('有草稿 → 對話框 → 繼續 → 進全螢幕訓練頁(接手該草稿)', (tester) async {
      final harness = await _setUpLoggedInHarness();
      await seedDraft(harness.db);
      await _pumpApp(tester, harness);

      expect(find.text('發現未完成的訓練'), findsOneWidget);
      await tester.tap(find.byKey(const Key('resumeDraftContinueButton')));
      await tester.pumpAndSettle();

      _expectOnWorkoutPage();
      expect(harness.container.read(workoutControllerProvider).value!.draft?.id, 'recoverable-draft');
    });

    testWidgets('有草稿 → 對話框 → 放棄 → 草稿刪除,首頁顯示「開始訓練」', (tester) async {
      final harness = await _setUpLoggedInHarness();
      await seedDraft(harness.db);
      await _pumpApp(tester, harness);
      // 對話框出現前首頁已查過一次,當時有草稿。
      expect(_dashboard(harness).hasDraftWorkout, isTrue);

      await tester.tap(find.byKey(const Key('resumeDraftDiscardButton')));
      await tester.pumpAndSettle();

      expect(find.text('發現未完成的訓練'), findsNothing);
      _expectOnDashboard();
      expect(_dashboard(harness).hasDraftWorkout, isFalse);
      expect(find.text('開始訓練'), findsOneWidget);
      expect(find.text('繼續訓練'), findsNothing);
      expect(
        await DriftWorkoutRepository(harness.db, DriftExerciseRepository(harness.db)).fetchById('recoverable-draft'),
        isNull,
      );
    });

    testWidgets('對話框開著時同一筆草稿已被接手使用 → 選「放棄」不刪,改進入該草稿(flow-fix 7)', (tester) async {
      final harness = await _setUpLoggedInHarness();
      await seedDraft(harness.db);
      await _pumpApp(tester, harness);
      expect(find.text('發現未完成的訓練'), findsOneWidget);

      // 對話框等待期間,別的入口(例如直開 /workout 的進頁檢查)接手了這筆草稿。
      await harness.container.read(workoutControllerProvider.notifier).resumeDraft('recoverable-draft');
      await tester.tap(find.byKey(const Key('resumeDraftDiscardButton')));
      await tester.pumpAndSettle();

      _expectOnWorkoutPage();
      expect(harness.container.read(workoutControllerProvider).value!.draft?.id, 'recoverable-draft');
      expect(
        await DriftWorkoutRepository(harness.db, DriftExerciseRepository(harness.db)).fetchById('recoverable-draft'),
        isNotNull,
      );
    });

    testWidgets('沒有草稿 → 不彈對話框', (tester) async {
      final harness = await _setUpLoggedInHarness();
      await _pumpApp(tester, harness);
      expect(find.text('發現未完成的訓練'), findsNothing);
      _expectOnDashboard();
    });
  });

  // mock web 實測重現(integrate 第 3 條):直接 go('/workout')(Web 直開網址、
  // 舊的 go 入口)且沒有草稿 → 訓練頁自己回 /dashboard 後,首頁內容整片空白只剩
  // 導覽列、切分頁才恢復。push 進來的路徑不會壞(殼層沒被拆)。
  testWidgets('沒有草稿時直接 go(/workout) → 彈回首頁,首頁內容正常顯示(不是空白)', (tester) async {
    final harness = await _setUpLoggedInHarness();
    await _pumpApp(tester, harness);
    _expectOnDashboard();

    GoRouter.of(tester.element(find.byType(DashboardPage))).go(kWorkoutRoutePath);
    await tester.pumpAndSettle();

    _expectOnDashboard();
    expect(find.byKey(const Key('quickActionStartWorkout')).hitTestable(), findsOneWidget);
    expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);
  });
}
