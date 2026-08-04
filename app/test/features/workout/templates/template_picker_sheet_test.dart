// showTemplatePicker widget 測試:真 in-memory DB(建庫即含 5 個系統模板
// 種子),斷言系統/個人分區、預覽前 3 個動作、選定回傳 AppliedTemplate、
// 取消回傳 null。
//
// 測試視窗刻意放大(見 [_pumpPicker]):sheet 內容是 ListView,預設測試
// 視窗(800x600)裝不下 5 個系統模板 + 1 個個人模板卡片,ListView 只會
// mount 進可視範圍(含 cacheExtent)內的子項——不放大視窗的話,後面幾張
// 卡片/整個「我的模板」分區根本不會出現在 element tree 裡,`find` 找不到
// 不代表程式有 bug,而是測試本身沒讓內容進視窗。放大視窗讓全部內容一次
// 攤開,斷言才會對應到「畫面上真的看得到什麼」。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide TemplateExercise;
import 'package:workout_record/data/models/workout_template.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/template_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/templates/applied_template.dart';
import 'package:workout_record/features/workout/templates/template_picker_sheet.dart';

import '../../../data/test_helpers.dart';

class _Harness {
  _Harness(this.db, this.container);
  final AppDatabase db;
  final ProviderContainer container;
}

Future<_Harness> _setUpHarness() async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(db, container);
}

Future<void> _createPersonalTemplate(
  _Harness harness, {
  required String id,
  required String name,
  required List<String> exerciseIds,
}) async {
  final repo = TemplateRepository(harness.db, ExerciseRepository(harness.db));
  final now = DateTime.now();
  await repo.create(
    WorkoutTemplate(
      id: id,
      userId: testUserId,
      name: name,
      exercises: [
        for (var i = 0; i < exerciseIds.length; i++)
          TemplateExercise(
            id: '$id-te-$i',
            templateId: id,
            exerciseId: exerciseIds[i],
            orderIndex: i,
            suggestedSets: 3,
            suggestedReps: 10,
          ),
      ],
      createdAt: now,
      updatedAt: now,
    ),
  );
}

/// 開啟 showTemplatePicker sheet,回傳一個讓測試自己 await 的 Future
/// (使用者選定/取消時才會 resolve)。放大測試視窗讓 sheet 內全部內容
/// (5 個系統模板 + 個人模板)一次攤開,不需要額外 scroll——見檔案開頭
/// 說明。
Future<Future<AppliedTemplate?>> _pumpPicker(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  late Future<AppliedTemplate?> resultFuture;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                resultFuture = showTemplatePicker(context);
              },
              child: const Text('open-picker'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-picker'));
  await tester.pumpAndSettle();
  return resultFuture;
}

void main() {
  testWidgets('分區顯示系統模板與個人模板,每個模板預覽前 3 個動作', (tester) async {
    final harness = await _setUpHarness();
    final exercises = await ExerciseRepository(harness.db).fetchAll();
    await _createPersonalTemplate(
      harness,
      id: 'personal-template-1',
      name: '我的自訂模板',
      exerciseIds: exercises.take(2).map((e) => e.id).toList(),
    );

    await _pumpPicker(tester, harness);

    expect(find.text('系統模板'), findsOneWidget);
    expect(find.text('我的模板'), findsOneWidget);
    expect(find.text('我的自訂模板'), findsOneWidget);
    expect(find.text('PPL - Push (推)'), findsOneWidget);
    expect(find.text('上肢訓練'), findsOneWidget);
    // 用精準比對(不是 textContaining):模板描述「適合初學者的全身訓練」
    // 本身就包含「全身訓練」子字串,textContaining 會連描述文字一起算進去。
    expect(find.text('全身訓練'), findsOneWidget);

    // 5 個系統模板都恰好 5 個動作,預覽只顯示前 3 個,剩下 2 個用
    // 「還有 2 個...」提示——5 張系統模板 card 都應該出現這行文字。
    expect(find.textContaining('還有 2 個'), findsNWidgets(5));
    // 個人模板只有 2 個動作,3 個以內全部顯示,不會出現「還有」提示。
    expect(
      find.descendant(
        of: find.byKey(const Key('templatePickerCard_personal-template-1')),
        matching: find.textContaining('還有'),
      ),
      findsNothing,
    );
  });

  testWidgets('點選個人模板卡片後,onSelect 回傳的 AppliedTemplate 動作數與模板一致', (tester) async {
    final harness = await _setUpHarness();
    final exercises = await ExerciseRepository(harness.db).fetchAll();
    await _createPersonalTemplate(
      harness,
      id: 'personal-template-2',
      name: '另一個自訂模板',
      exerciseIds: exercises.take(2).map((e) => e.id).toList(),
    );

    final resultFuture = await _pumpPicker(tester, harness);

    await tester.tap(find.byKey(const Key('templatePickerCardTap_personal-template-2')));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result, isNotNull);
    expect(result!.templateId, 'personal-template-2');
    expect(result.exercises, hasLength(2));
    expect(result.exercises.every((e) => e.sets.every((s) => s.weight == 0)), isTrue);
  });

  testWidgets('取消回傳 null', (tester) async {
    final harness = await _setUpHarness();

    final resultFuture = await _pumpPicker(tester, harness);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final result = await resultFuture;
    expect(result, isNull);
  });
}
