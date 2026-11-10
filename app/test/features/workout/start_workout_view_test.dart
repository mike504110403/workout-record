// 開始畫面(start_workout_view.dart):上方「自由開始」主按鈕,下方直接列出
// 模板卡,點一下以該模板開始(不再經過「從模板開始」sheet)。
// 真 in-memory DB(建庫即含系統模板)+ 真 repositories。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, Exercise;
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/start_workout_view.dart';
import 'package:workout_record/features/workout/workout_controller.dart';

import '../../data/test_helpers.dart';

Future<({AppDatabase db, ProviderContainer container})> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
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
  await container.read(workoutControllerProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: StartWorkoutView())),
    ),
  );
  await tester.pumpAndSettle();
  return (db: db, container: container);
}

void main() {
  testWidgets('主按鈕「自由開始」在上方;直接列出模板卡;不再有「從模板開始」按鈕', (tester) async {
    final h = await _pump(tester);

    expect(find.widgetWithText(FilledButton, '自由開始'), findsOneWidget);
    expect(find.byKey(const Key('startFromTemplateButton')), findsNothing);
    expect(find.byKey(const Key('manageTemplatesButton')), findsOneWidget);

    final systemTemplates = await h.db.select(h.db.templates).get();
    expect(systemTemplates, isNotEmpty);
    // ListView 為虛擬化:先確認第一張卡,其餘靠捲動——這裡只驗證至少列出系統模板區與首張卡。
    expect(find.text('系統模板'), findsOneWidget);
    expect(find.byKey(Key('startTemplateCard_${systemTemplates.first.id}')), findsOneWidget);

    // 「自由開始」位在模板卡上方。
    final freeY = tester.getTopLeft(find.byKey(const Key('startFreeWorkoutButton'))).dy;
    final cardY = tester.getTopLeft(find.byKey(Key('startTemplateCard_${systemTemplates.first.id}'))).dy;
    expect(freeY, lessThan(cardY));
  });

  testWidgets('點模板卡 → 一鍵以該模板開始(草稿含模板的動作與組數)', (tester) async {
    final h = await _pump(tester);
    final row = await (h.db.select(h.db.templates)..where((t) => t.name.equals('全身訓練'))).getSingle();

    final card = find.byKey(Key('startTemplateCard_${row.id}'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    final draft = h.container.read(workoutControllerProvider).value!.draft;
    expect(draft, isNotNull);
    expect(draft!.exercises, hasLength(5)); // 全身訓練模板固定 5 個動作
    expect(draft.exercises.first.sets, hasLength(3));
  });

  testWidgets('點「自由開始」→ 空草稿', (tester) async {
    final h = await _pump(tester);

    await tester.tap(find.byKey(const Key('startFreeWorkoutButton')));
    await tester.pumpAndSettle();

    final draft = h.container.read(workoutControllerProvider).value!.draft;
    expect(draft, isNotNull);
    expect(draft!.exercises, isEmpty);
  });
}
