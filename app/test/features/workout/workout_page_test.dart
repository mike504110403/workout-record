// 全螢幕訓練頁(workout_page.dart)進入時的草稿解析。原本這裡測「訓練分頁
// 首次進入跳繼續/放棄對話框」;ui-polish 後對話框搬到 App 殼層(測在
// workout_flow_e2e_test.dart「啟動時有未完成草稿」),舊開始畫面
// (StartWorkoutView)刪除。這裡改測取代它的行為:直接 `go('/workout')`
// (Web 直開、首頁標籤過期、換帳號)時 controller 是 idle——
// DB 有草稿 → 直接接手進入;沒有 → 回首頁。不彈對話框。
//
// 真 in-memory DB + 真 repositories,只 override DB/prefs;路由用最小 GoRouter
// (/dashboard 替身 + 真 WorkoutPage)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, Exercise;
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/workout/workout_page.dart';

import '../../data/test_helpers.dart';

typedef _Harness = ({AppDatabase db, ProviderContainer container});

/// 進頁檢查查草稿時拋錯(雲端模式離線、DB 讀取失敗)。
class _ThrowingFetchDraftRepository extends DriftWorkoutRepository {
  _ThrowingFetchDraftRepository(super.db, super.exerciseRepository);

  @override
  Future<Workout?> fetchDraft(String userId) async => throw Exception('模擬查詢草稿失敗');
}

Future<_Harness> _setUpHarness({bool throwOnFetchDraft = false}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (throwOnFetchDraft)
        workoutRepositoryProvider.overrideWithValue(
          _ThrowingFetchDraftRepository(db, DriftExerciseRepository(db)),
        ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (db: db, container: container);
}

Future<String> _seedDraft(AppDatabase db) async {
  final repo = DriftWorkoutRepository(db, DriftExerciseRepository(db));
  final startedAt = DateTime(2026, 3, 1, 9, 0);
  await repo.create(Workout(
    id: 'recoverable-draft-1',
    userId: testUserId,
    startedAt: startedAt,
    createdAt: startedAt,
    updatedAt: startedAt,
  ));
  return 'recoverable-draft-1';
}

/// 直開 `/workout`(initialLocation),沒有可 pop 的上一頁。
Future<void> _pumpDirect(WidgetTester tester, _Harness harness) async {
  final router = GoRouter(
    initialLocation: '/workout',
    routes: [
      GoRoute(path: '/dashboard', builder: (context, state) => const Scaffold(body: Text('DASHBOARD'))),
      GoRoute(path: '/workout', builder: (context, state) => const WorkoutPage()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('直接 go(/workout),controller 是 idle', () {
    testWidgets('DB 有草稿 → 不彈對話框,直接接手並顯示進行中畫面', (tester) async {
      final harness = await _setUpHarness();
      await _seedDraft(harness.db);

      await _pumpDirect(tester, harness);

      expect(find.text('發現未完成的訓練'), findsNothing);
      expect(find.text('DASHBOARD'), findsNothing);
      expect(find.byKey(const Key('completeWorkoutButton')), findsOneWidget);
      final draft = harness.container.read(workoutControllerProvider).value!.draft!;
      expect(draft.id, 'recoverable-draft-1');
      expect(draft.startedAt, DateTime(2026, 3, 1, 9, 0));
    });

    testWidgets('DB 沒有草稿 → 回首頁', (tester) async {
      final harness = await _setUpHarness();

      await _pumpDirect(tester, harness);

      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.byType(WorkoutPage), findsNothing);
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);
    });

    testWidgets('進頁檢查拋錯 → 回首頁並提示,不留空白頁(flow-fix 6)', (tester) async {
      final harness = await _setUpHarness(throwOnFetchDraft: true);

      await _pumpDirect(tester, harness);

      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.byType(WorkoutPage), findsNothing);
      expect(find.textContaining('載入訓練失敗'), findsOneWidget);
    });

    testWidgets('直開時收起鈕沒有上一頁可回 → 改回首頁,草稿保留', (tester) async {
      final harness = await _setUpHarness();
      await _seedDraft(harness.db);
      await _pumpDirect(tester, harness);

      await tester.tap(find.byKey(const Key('workoutMinimizeButton')));
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(harness.container.read(workoutControllerProvider).value!.draft?.id, 'recoverable-draft-1');
    });
  });
}
