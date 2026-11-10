// workout 區所有 modal bottom sheet 都要用 root navigator 開(蓋住底部導航列)。
// 作法:把觸發按鈕放進「巢狀 Navigator」(模擬 StatefulShellRoute 的分支
// navigator),開 sheet 後檢查 sheet route 是推在 root navigator 而不是
// 巢狀 navigator。變異:把任一 sheet 的 `useRootNavigator: true` 拿掉,
// 對應測試會紅(sheet 變推到巢狀 navigator → nestedKey.canPop() 為 true)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/add_set_sheet.dart';
import 'package:workout_record/features/workout/exercise_picker/exercise_picker_sheet.dart';
import 'package:workout_record/features/workout/templates/template_picker_sheet.dart';
import 'package:workout_record/features/workout/workout_summary_sheet.dart';

import '../../data/test_helpers.dart';

Future<void> _openFromNestedNavigator(
  WidgetTester tester, {
  required GlobalKey<NavigatorState> rootKey,
  required GlobalKey<NavigatorState> nestedKey,
  required void Function(BuildContext context) opener,
}) async {
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

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: rootKey,
        home: Scaffold(
          body: Navigator(
            key: nestedKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => opener(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Workout _workout() {
  final now = DateTime.now();
  return Workout(
    id: 'w',
    userId: 'u',
    startedAt: now,
    endedAt: now,
    duration: 10,
    createdAt: now,
    updatedAt: now,
  );
}

void _expectOnRoot(GlobalKey<NavigatorState> rootKey, GlobalKey<NavigatorState> nestedKey) {
  expect(nestedKey.currentState!.canPop(), isFalse, reason: 'sheet 不該推在巢狀 navigator');
  expect(rootKey.currentState!.canPop(), isTrue, reason: 'sheet 應推在 root navigator');
}

void main() {
  late GlobalKey<NavigatorState> rootKey;
  late GlobalKey<NavigatorState> nestedKey;
  setUp(() {
    rootKey = GlobalKey<NavigatorState>();
    nestedKey = GlobalKey<NavigatorState>();
  });

  testWidgets('記組 sheet', (tester) async {
    await _openFromNestedNavigator(
      tester,
      rootKey: rootKey,
      nestedKey: nestedKey,
      opener: (c) => showAddSetSheet(c, exerciseName: '深蹲', setNumber: 1),
    );
    _expectOnRoot(rootKey, nestedKey);
  });

  testWidgets('完成摘要 sheet', (tester) async {
    await _openFromNestedNavigator(
      tester,
      rootKey: rootKey,
      nestedKey: nestedKey,
      opener: (c) => showWorkoutSummarySheet(c, _workout(), 0),
    );
    _expectOnRoot(rootKey, nestedKey);
  });

  testWidgets('動作選擇器 sheet 與疊在其上的快速新增 sheet', (tester) async {
    await _openFromNestedNavigator(
      tester,
      rootKey: rootKey,
      nestedKey: nestedKey,
      opener: (c) => showExercisePicker(c),
    );
    _expectOnRoot(rootKey, nestedKey);

    await tester.tap(find.byKey(const Key('exercise_picker_add_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick_add_name_field')), findsOneWidget);
    _expectOnRoot(rootKey, nestedKey);
  });

  testWidgets('模板選擇 sheet', (tester) async {
    await _openFromNestedNavigator(
      tester,
      rootKey: rootKey,
      nestedKey: nestedKey,
      opener: (c) => showTemplatePicker(c),
    );
    _expectOnRoot(rootKey, nestedKey);
  });
}
