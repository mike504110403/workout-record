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
  bool multiSelect = false,
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
              onPressed: () async => picked = await showExercisePicker(context, workoutMode: true, multiSelect: multiSelect),
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

  testWidgets('workoutMode+多選:點「最近用過」chip 是切換勾選、不關閉選單,已選 chip 呈勾選態', (tester) async {
    final h = await _pump(tester, multiSelect: true, recentOf: (system) => [system[3], system[1]]);
    final chip3 = find.byKey(Key('exercise_picker_recent_${h.system[3].id}'));

    await tester.tap(chip3);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exercise_picker_search_field')), findsOneWidget, reason: '選單未關閉');
    expect(h.result(), isNull);
    expect(tester.widget<FilterChip>(chip3).selected, isTrue);
    expect(tester.widget<FilterChip>(find.byKey(Key('exercise_picker_recent_${h.system[1].id}'))).selected, isFalse);
    expect(find.text('確認 (1)'), findsOneWidget);

    // 再點一次 = 取消勾選
    await tester.tap(chip3);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(chip3).selected, isFalse);
    expect(find.text('確認 (0)'), findsOneWidget);
  });

  testWidgets('多選回傳依勾選順序:最近 chip 與清單列混選,取消再勾排到最後', (tester) async {
    final h = await _pump(tester, multiSelect: true, recentOf: (system) => [system[3]]);
    final s = h.system;
    // 清單查詢順序(依名稱)與勾選順序刻意不同:先勾 chip(s[3]),再勾列 s[0]、s[2]。
    await tester.tap(find.byKey(Key('exercise_picker_recent_${s[3].id}')));
    for (final e in [s[0], s[2]]) {
      final row = find.byKey(Key('exercise_checkbox_${e.id}'));
      await tester.scrollUntilVisible(row, 200, scrollable: find.descendant(of: find.byKey(const Key('exercise_picker_list')), matching: find.byType(Scrollable)).first);
      await tester.tap(row);
      await tester.pumpAndSettle();
    }
    // 取消 s[0] 後再勾 → 排到最後
    final row0 = find.byKey(Key('exercise_checkbox_${s[0].id}'));
    await tester.scrollUntilVisible(row0, -200, scrollable: find.descendant(of: find.byKey(const Key('exercise_picker_list')), matching: find.byType(Scrollable)).first);
    await tester.tap(row0);
    await tester.pumpAndSettle();
    await tester.tap(row0);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('exercise_picker_confirm_button')));
    await tester.pumpAndSettle();

    expect(h.result()?.map((e) => e.id).toList(), [s[3].id, s[2].id, s[0].id]);
  });

  /// 清單目前由上而下前兩列的動作 id(= 查詢順序的前兩個)。
  List<String> topTwoIds(WidgetTester tester) => [
    for (final t in tester.widgetList<ListTile>(find.descendant(of: find.byKey(const Key('exercise_picker_list')), matching: find.byType(ListTile))).take(2))
      (t.key! as ValueKey<String>).value.substring('exercise_row_'.length),
  ];

  Future<void> toggle(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('exercise_checkbox_$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('多選順序:先勾查詢順序較後者再勾較前者 → 回傳依勾選順序(非查詢順序)', (tester) async {
    final h = await _pump(tester, multiSelect: true);
    final [earlier, later] = topTwoIds(tester);
    await toggle(tester, later);
    await toggle(tester, earlier);
    await tester.tap(find.byKey(const Key('exercise_picker_confirm_button')));
    await tester.pumpAndSettle();
    expect(h.result()?.map((e) => e.id).toList(), [later, earlier]);
  });

  testWidgets('多選順序:勾 A→勾 B→取消 A→再勾 A → [B, A]', (tester) async {
    final h = await _pump(tester, multiSelect: true);
    final [a, b] = topTwoIds(tester);
    await toggle(tester, a);
    await toggle(tester, b);
    await toggle(tester, a); // 取消 A
    await toggle(tester, a); // 再勾 A → 排到最後
    await tester.tap(find.byKey(const Key('exercise_picker_confirm_button')));
    await tester.pumpAndSettle();
    expect(h.result()?.map((e) => e.id).toList(), [b, a]);
  });
}
