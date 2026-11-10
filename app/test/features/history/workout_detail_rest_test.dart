// 訓練詳情頁「休息」欄:有值照 iOS formatRestTime(WorkoutDetailView.swift:
// 367-376)格式化(滿 1 分鐘 m:ss、不滿 1 分鐘 Ns),無值顯示「-」。
// 直接 pump WorkoutDetailPage(吃呼叫端組好的 Workout,不查 DB)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/history/history_format.dart';
import 'package:workout_record/features/history/workout_detail_page.dart';

import '../../data/test_helpers.dart';

WorkoutSet _set(String id, int setNumber, {int? restSeconds}) {
  final now = DateTime.now();
  return WorkoutSet(
    id: id,
    workoutExerciseId: 'we-1',
    setNumber: setNumber,
    weight: 60,
    reps: 8,
    restSeconds: restSeconds,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpDetail(WidgetTester tester, List<WorkoutSet> sets) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  final now = DateTime.now();
  final workout = Workout(
    id: 'w-1',
    userId: testUserId,
    startedAt: now,
    endedAt: now.add(const Duration(minutes: 30)),
    duration: 30,
    totalSets: sets.length,
    totalExercises: 1,
    exercises: [
      WorkoutExercise(
        id: 'we-1',
        workoutId: 'w-1',
        exerciseId: 'ex-1',
        exerciseName: '槓鈴臥推',
        orderIndex: 0,
        sets: sets,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(home: WorkoutDetailPage(workout: workout)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('formatRestSeconds 照 iOS:<60 秒 Ns、>=60 秒 m:ss(秒補零)', () {
    expect(formatRestSeconds(0), '0s');
    expect(formatRestSeconds(45), '45s');
    expect(formatRestSeconds(59), '59s');
    expect(formatRestSeconds(60), '1:00');
    expect(formatRestSeconds(90), '1:30');
    expect(formatRestSeconds(125), '2:05');
  });

  testWidgets('每組顯示休息時間:有值格式化、無值顯示「-」,表頭有「休息」', (tester) async {
    await _pumpDetail(tester, [
      _set('s-1', 1, restSeconds: 90),
      _set('s-2', 2, restSeconds: 45),
      _set('s-3', 3),
    ]);

    final list = find.byKey(const Key('workoutDetailExerciseList'));
    expect(
      find.descendant(of: list, matching: find.text('休息')),
      findsOneWidget,
    );

    String restOf(String setId) =>
        tester.widget<Text>(find.byKey(Key('workoutDetailRest_$setId'))).data!;
    expect(restOf('s-1'), '1:30');
    expect(restOf('s-2'), '45s');
    expect(restOf('s-3'), '-');
  });
}
