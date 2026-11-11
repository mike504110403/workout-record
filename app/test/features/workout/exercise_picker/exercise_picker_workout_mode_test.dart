// 選動作 sheet 的 workoutMode(ui-polish,只有進行中訓練頁開;預設關閉的舊
// 版面由 exercise_picker_sheet_test.dart 守門):收掉標題列、搜尋框置頂、頂端
// 「最近用過」、「+ 自訂動作」只在搜尋無結果時出現。真 in-memory DB + 真
// repositories;「最近用過」的資料來源 override 成固定清單(查詢邏輯本身測在
// planned_sets_test.dart「歷史預填 best-effort」)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/exercise_history.dart';
import 'package:workout_record/features/workout/exercise_picker/exercise_picker_sheet.dart';

import '../../../data/test_helpers.dart';

Future<({List<Exercise> system, List<Exercise>? Function() result})> _pump(
  WidgetTester tester, {
  List<Exercise> Function(List<Exercise> system)? recentOf,
  Object? recentError,
}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);
  final system = await DriftExerciseRepository(db).fetchSystemExercises();
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  List<Exercise>? picked;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        recentExercisesProvider.overrideWith((ref) async {
          if (recentError != null) throw recentError;
          return recentOf?.call(system) ?? const [];
        }),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => picked = await showExercisePicker(context, workoutMode: true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (system: system, result: () => picked);
}

void main() {
  testWidgets('收掉標題列(無取消鈕/無「選擇動作」標題/無右上 +),搜尋框置頂,有拖曳把手', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('exercise_picker_cancel_button')), findsNothing);
    expect(find.text('選擇動作'), findsNothing);
    expect(find.byKey(const Key('exercise_picker_add_button')), findsNothing);
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle, isTrue);
    final searchY = tester.getTopLeft(find.byKey(const Key('exercise_picker_search_field'))).dy;
    final tabsY = tester.getTopLeft(find.byKey(const Key('category_chip_all'))).dy;
    expect(searchY, lessThan(tabsY));
  });

  testWidgets('最近用過:列在分類上方,點 chip 直接選該動作並關閉', (tester) async {
    final h = await _pump(tester, recentOf: (system) => [system[3], system[1]]);
    final system = h.system;

    final section = find.byKey(const Key('exercise_picker_recent_section'));
    expect(section, findsOneWidget);
    expect(find.text('最近用過'), findsOneWidget);
    expect(tester.getTopLeft(section).dy, lessThan(tester.getTopLeft(find.byKey(const Key('category_chip_all'))).dy));
    final chips = find.descendant(of: section, matching: find.byType(ActionChip));
    expect(chips, findsNWidgets(2));

    await tester.tap(find.byKey(Key('exercise_picker_recent_${system[3].id}')));
    await tester.pumpAndSettle();

    expect(h.result()?.map((e) => e.id), [system[3].id]);
    expect(find.byKey(const Key('exercise_picker_search_field')), findsNothing);
  });

  testWidgets('沒有紀錄或查詢失敗:「最近用過」整區不顯示,選動作照常', (tester) async {
    await _pump(tester, recentError: Exception('離線'));
    expect(find.byKey(const Key('exercise_picker_recent_section')), findsNothing);
    expect(find.byKey(const Key('exercise_picker_list')), findsOneWidget);
  });

  testWidgets('「+ 自訂動作」只在搜尋無結果時出現,點了開快速新增表單', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('exercise_picker_add_custom_from_search')), findsNothing);

    await tester.enterText(find.byKey(const Key('exercise_picker_search_field')), '不存在的動作xyz');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exercise_picker_empty_search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('exercise_picker_add_custom_from_search')));
    await tester.pumpAndSettle();
    expect(find.text('新增自訂動作'), findsWidgets);
  });
}
