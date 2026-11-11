// 「我的模板」管理頁對齊 iOS WorkoutTemplateView.swift 的 TemplateCard 與
// 空狀態:卡片預覽(描述、前 3 個動作「N 組 × M 次」、「還有 N 個動作...」)、
// 空狀態按鈕、「使用此模板」重用 WorkoutController.startFromTemplate 開始訓練
// 並導到訓練 tab(已有進行中訓練時不覆蓋、提示後同樣導過去)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide TemplateExercise;
import 'package:workout_record/data/models/workout_template.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/template_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/templates/templates_list_page.dart';
import 'package:workout_record/features/workout/workout_controller.dart';

import '../../../data/test_helpers.dart';

/// 空狀態專用:系統模板由 DB seed 帶出,無法靠刪除清空,改讓兩個 fetch 都回空。
class _EmptyTemplateRepository extends DriftTemplateRepository {
  _EmptyTemplateRepository(super.db, super.exerciseRepository);

  @override
  Future<List<WorkoutTemplate>> fetchAll(String userId) async => const [];

  @override
  Future<List<WorkoutTemplate>> fetchSystemTemplates() async => const [];
}

class _Harness {
  _Harness(this.db, this.container, this.exercises);
  final AppDatabase db;
  final ProviderContainer container;
  final List<dynamic> exercises; // List<Exercise>,fetchAll 取回
}

Future<_Harness> _setUp({bool emptyTemplates = false}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);
  final exerciseRepo = DriftExerciseRepository(db);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (emptyTemplates)
        templateRepositoryProvider.overrideWithValue(
          _EmptyTemplateRepository(db, exerciseRepo),
        ),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(db, container, await exerciseRepo.fetchAll());
}

Future<void> _bigView(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpPlain(WidgetTester tester, _Harness h) async {
  await _bigView(tester);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: const MaterialApp(home: TemplatesListPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 用 GoRouter 掛:'/' 首頁有按鈕推入模板頁、'/workout' 是訓練頁替身,
/// 驗證「使用此模板」之後 push 到 /workout 且模板頁已被收掉。
Future<GoRouter> _pumpRouted(WidgetTester tester, _Harness h) async {
  await _bigView(tester);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('openTemplates'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TemplatesListPage(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/workout',
        builder: (context, state) => const Scaffold(body: Text('WORKOUT_TAB')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('openTemplates')));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _createTemplate(
  _Harness h, {
  required String id,
  required String name,
  String? description,
  required int exerciseCount,
  int? Function(int index)? sets,
  int? Function(int index)? reps,
}) async {
  final now = DateTime.now();
  await DriftTemplateRepository(h.db, DriftExerciseRepository(h.db)).create(
    WorkoutTemplate(
      id: id,
      userId: testUserId,
      name: name,
      description: description,
      exercises: [
        for (var i = 0; i < exerciseCount; i++)
          TemplateExercise(
            id: '$id-te-$i',
            templateId: id,
            exerciseId: (h.exercises[i] as dynamic).id as String,
            orderIndex: i,
            suggestedSets: sets?.call(i),
            suggestedReps: reps?.call(i),
          ),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );
}

void main() {
  group('卡片預覽', () {
    testWidgets('描述、前 3 個動作各自「N 組 × M 次」、超過 3 個顯示「還有 N 個動作...」', (
      tester,
    ) async {
      final h = await _setUp();
      await _createTemplate(
        h,
        id: 'five',
        name: '五動作模板',
        description: '週一胸肩日',
        exerciseCount: 5,
        sets: (i) => 3 + i,
        reps: (i) => 8 + i,
      );
      await _pumpPlain(tester, h);

      final card = find.byKey(const Key('templateListTile_five'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('週一胸肩日')),
        findsOneWidget,
      );

      // 只預覽前 3 個動作,各自帶「N 組 × M 次」。
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('templateCardExercise_five_$i')), findsOneWidget);
        final name = (h.exercises[i] as dynamic).name as String;
        expect(
          find.descendant(of: card, matching: find.text(name)),
          findsWidgets,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('${3 + i} 組 × ${8 + i} 次'),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const Key('templateCardExercise_five_3')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('還有 2 個動作...')),
        findsOneWidget,
      );
    });

    testWidgets('恰好 3 個動作不顯示「還有」;建議組數/次數缺值時不顯示「N 組 × M 次」;無描述不顯示描述', (
      tester,
    ) async {
      final h = await _setUp();
      await _createTemplate(h, id: 'three', name: '三動作模板', exerciseCount: 3);
      await _pumpPlain(tester, h);

      expect(
        find.byKey(const Key('templateCardExercise_three_2')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('templateCardMore_three')), findsNothing);
      expect(
        find.byKey(const Key('templateCardDescription_three')),
        findsNothing,
      );
      final card = find.byKey(const Key('templateListTile_three'));
      expect(
        find.descendant(of: card, matching: find.textContaining('組 ×')),
        findsNothing,
      );
    });
  });

  group('空狀態', () {
    testWidgets('顯示「尚未建立模板」與「建立第一個模板」,按鈕開啟建立表單', (tester) async {
      final h = await _setUp(emptyTemplates: true);
      await _pumpPlain(tester, h);

      expect(find.text('尚未建立模板'), findsOneWidget);
      expect(find.text('建立訓練模板來快速開始訓練'), findsOneWidget);
      expect(find.text('建立第一個模板'), findsOneWidget);

      await tester.tap(find.byKey(const Key('templateEmptyCreateButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('templateFormNameField')), findsOneWidget);
    });
  });

  group('使用此模板', () {
    testWidgets('開始訓練(草稿依模板建立、組為計畫組)並 push 到 /workout,模板頁被收掉', (tester) async {
      final h = await _setUp();
      await _createTemplate(
        h,
        id: 'use-me',
        name: '要使用的模板',
        exerciseCount: 2,
        sets: (i) => 4,
        reps: (i) => 6,
      );
      await _pumpRouted(tester, h);

      await tester.tap(find.byKey(const Key('templateUseButton_use-me')));
      await tester.pumpAndSettle();

      // push 到訓練頁替身,模板頁已不在;返回會回到原本的 '/' 而不是模板頁。
      expect(find.text('WORKOUT_TAB'), findsOneWidget);
      expect(find.byType(TemplatesListPage, skipOffstage: false), findsNothing);
      final router = GoRouter.of(tester.element(find.text('WORKOUT_TAB')));
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('openTemplates')), findsOneWidget);

      // controller 狀態與獨立 SELECT 都看到依模板建立的草稿。模板的組是
      // 「計畫組」(Mike 2026-11-11 裁示 2):DB 裡沒有任何真實組,計畫組
      // 4 組 × 6 次在 controller state。
      final flow = h.container.read(workoutControllerProvider).value!;
      final draft = flow.draft;
      expect(draft, isNotNull);
      final landed = await DriftWorkoutRepository(
        h.db,
        DriftExerciseRepository(h.db),
      ).fetchDraft(testUserId);
      expect(landed, isNotNull);
      expect(landed!.id, draft!.id);
      expect(landed.exercises, hasLength(2));
      expect(landed.exercises.every((e) => e.sets.isEmpty), isTrue);
      for (final e in landed.exercises) {
        final planned = flow.plannedSets[e.id]!;
        expect(planned, hasLength(4));
        expect(planned.every((p) => p.reps == 6), isTrue);
      }
    });

    testWidgets('已有進行中訓練:不覆蓋既有草稿、提示後仍導到 /workout', (tester) async {
      final h = await _setUp();
      await _createTemplate(h, id: 'use-me', name: '要使用的模板', exerciseCount: 2);
      await h.container
          .read(workoutControllerProvider.notifier)
          .startFreeWorkout();
      final existingId = h.container
          .read(workoutControllerProvider)
          .value!
          .draft!
          .id;
      await _pumpRouted(tester, h);

      await tester.tap(find.byKey(const Key('templateUseButton_use-me')));
      await tester.pumpAndSettle();

      expect(find.text('已有進行中的訓練,未套用此模板'), findsOneWidget);
      expect(find.text('WORKOUT_TAB'), findsOneWidget);
      final draft = h.container.read(workoutControllerProvider).value!.draft!;
      expect(draft.id, existingId);
      expect(draft.exercises, isEmpty);
    });
  });
}
