// 模板 CRUD 真組裝測試:建立 -> 列表出現 -> 編輯(動作清單更新落地,獨立
// SELECT 驗證)-> 刪除 -> 消失;系統模板不可編輯/刪除;建立失敗路徑。
//
// 測試視窗放大到能一次容納整份動作挑選清單(exercise_picker_fake.dart
// 列出全部啟用中的動作,66 筆系統動作),理由同
// template_picker_sheet_test.dart 開頭說明:ListView 只 mount 進視窗
// (含 cacheExtent)內的子項,視窗太小會找不到要點的項目,不是程式有 bug。
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
import 'package:workout_record/features/workout/templates/templates_controller.dart';
import 'package:workout_record/features/workout/templates/templates_list_page.dart';

import '../../../data/test_helpers.dart';

/// M1 失敗路徑測試專用:模擬 `TemplateRepository.create` 寫入失敗(例如
/// 磁碟已滿、DB 被鎖)。只覆寫 create,其餘方法沿用真實實作,對照
/// dashboard_page_test.dart 的 `_ThrowingBodyWeightRepository` 既有慣例。
class _ThrowingCreateTemplateRepository extends TemplateRepository {
  _ThrowingCreateTemplateRepository(super.db, super.exerciseRepository);

  @override
  Future<void> create(WorkoutTemplate template) async {
    throw Exception('模擬建立模板失敗(失敗路徑測試用)');
  }
}

class _Harness {
  _Harness(this.db, this.container);
  final AppDatabase db;
  final ProviderContainer container;
}

Future<_Harness> _setUpHarness({
  TemplateRepository Function(AppDatabase db)? templateRepoBuilder,
}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (templateRepoBuilder != null)
        templateRepositoryProvider.overrideWithValue(templateRepoBuilder(db)),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(db, container);
}

Future<void> _pumpList(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: TemplatesListPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 從新增/編輯表單畫面點開動作挑選 fake sheet,勾選指定的動作,確認。
Future<void> _pickExercisesInForm(WidgetTester tester, List<String> exerciseIds) async {
  await tester.tap(find.byKey(const Key('templateFormAddExerciseButton')));
  await tester.pumpAndSettle();

  for (final id in exerciseIds) {
    await tester.tap(find.byKey(Key('exercisePickerFakeItem_$id')));
  }
  await tester.pump();
  await tester.tap(find.byKey(const Key('exercisePickerFakeConfirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('建立模板:填名稱、挑動作、儲存後列表立即出現該模板(獨立 SELECT 驗證落地)', (tester) async {
    final harness = await _setUpHarness();
    final exercises = await ExerciseRepository(harness.db).fetchAll();
    final pickedIds = exercises.take(2).map((e) => e.id).toList();

    await _pumpList(tester, harness);

    await tester.tap(find.byKey(const Key('templateListAddButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('templateFormNameField')), '我的新模板');
    await _pickExercisesInForm(tester, pickedIds);

    await tester.tap(find.byKey(const Key('templateFormSaveButton')));
    await tester.pumpAndSettle();

    // 回到列表頁,新模板應該立即出現(templatesControllerProvider 在
    // createTemplate 成功後呼叫 refresh(),不需要手動下拉刷新)。
    expect(find.text('我的新模板'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('我的新模板'), matching: find.byType(ListTile)),
        matching: find.text('2 個動作'),
      ),
      findsOneWidget,
    );

    // 獨立 SELECT(不透過畫面/controller state,重新查一次 repository)驗證
    // 真的落地,不是畫面上看起來對但資料庫沒寫進去。
    final repo = TemplateRepository(harness.db, ExerciseRepository(harness.db));
    final landed = (await repo.fetchAll(testUserId)).singleWhere((t) => t.name == '我的新模板');
    expect(landed.exercises, hasLength(2));
    expect(landed.exercises.map((e) => e.exerciseId).toSet(), pickedIds.toSet());
  });

  testWidgets('編輯模板:新增一個動作後,列表與資料庫的動作數都反映更新(獨立 SELECT)', (tester) async {
    final harness = await _setUpHarness();
    final exercises = await ExerciseRepository(harness.db).fetchAll();
    final repo = TemplateRepository(harness.db, ExerciseRepository(harness.db));
    final now = DateTime.now();
    await repo.create(
      WorkoutTemplate(
        id: 'editable-template',
        userId: testUserId,
        name: '可編輯的模板',
        exercises: [
          TemplateExercise(
            id: 'editable-template-te-0',
            templateId: 'editable-template',
            exerciseId: exercises[0].id,
            orderIndex: 0,
            suggestedSets: 3,
            suggestedReps: 10,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _pumpList(tester, harness);

    expect(find.text('1 個動作'), findsOneWidget);

    await tester.tap(find.byKey(const Key('templateEditButton_editable-template')));
    await tester.pumpAndSettle();

    // 表單應該預填既有的一個動作。
    expect(find.byKey(Key('templateFormExerciseRow_${exercises[0].id}')), findsOneWidget);

    await _pickExercisesInForm(tester, [exercises[1].id]);
    await tester.tap(find.byKey(const Key('templateFormSaveButton')));
    await tester.pumpAndSettle();

    expect(find.text('2 個動作'), findsOneWidget);

    final landed = await repo.fetchById('editable-template');
    expect(landed, isNotNull);
    expect(landed!.exercises, hasLength(2));
    expect(
      landed.exercises.map((e) => e.exerciseId).toSet(),
      {exercises[0].id, exercises[1].id},
    );
  });

  testWidgets(
      'code-M-A:編輯模板時清空描述 -> 落地為 null(獨立 SELECT),'
      '不是被 copyWith 的 ?? 吃掉、悄悄留著舊描述', (tester) async {
    final harness = await _setUpHarness();
    final exercises = await ExerciseRepository(harness.db).fetchAll();
    final repo = TemplateRepository(harness.db, ExerciseRepository(harness.db));
    final now = DateTime.now();
    await repo.create(
      WorkoutTemplate(
        id: 'template-with-description',
        userId: testUserId,
        name: '有描述的模板',
        description: '這段描述應該要能被清空',
        exercises: [
          TemplateExercise(
            id: 'template-with-description-te-0',
            templateId: 'template-with-description',
            exerciseId: exercises[0].id,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _pumpList(tester, harness);
    await tester.tap(find.byKey(const Key('templateEditButton_template-with-description')));
    await tester.pumpAndSettle();

    // 表單應該預填既有描述。
    expect(find.text('這段描述應該要能被清空'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('templateFormDescriptionField')), '');
    await tester.tap(find.byKey(const Key('templateFormSaveButton')));
    await tester.pumpAndSettle();

    // 獨立 SELECT,不是讀 controller state——真的落地成 null,不是畫面看起來
    // 清空了但 DB 還留著舊值(copyWith 修復前的真實 bug,code-reviewer 實測
    // 重現)。
    final landed = await repo.fetchById('template-with-description');
    expect(landed, isNotNull);
    expect(landed!.description, isNull);
  });

  testWidgets('minor:controller 層直接嘗試更新系統模板一樣會被擋(先前只測了刪除側)', (tester) async {
    final harness = await _setUpHarness();
    await _pumpList(tester, harness);

    final systemTemplate = harness.container
        .read(templatesControllerProvider)
        .value!
        .firstWhere((t) => t.isSystem);

    await expectLater(
      harness.container.read(templatesControllerProvider.notifier).updateTemplate(
            existing: systemTemplate,
            name: '嘗試竄改系統模板名稱',
            exercises: const [],
          ),
      throwsA(isA<StateError>()),
    );

    final repo = TemplateRepository(harness.db, ExerciseRepository(harness.db));
    final unchanged = await repo.fetchById(systemTemplate.id);
    expect(unchanged, isNotNull);
    expect(unchanged!.name, systemTemplate.name);
    expect(unchanged.exercises, isNotEmpty); // 沒有被清成空清單
  });

  testWidgets('刪除個人模板:確認對話框確認後從列表消失,資料庫也真的刪除(獨立 SELECT)', (tester) async {
    final harness = await _setUpHarness();
    final exercises = await ExerciseRepository(harness.db).fetchAll();
    final repo = TemplateRepository(harness.db, ExerciseRepository(harness.db));
    final now = DateTime.now();
    await repo.create(
      WorkoutTemplate(
        id: 'deletable-template',
        userId: testUserId,
        name: '待刪除的模板',
        exercises: [
          TemplateExercise(
            id: 'deletable-template-te-0',
            templateId: 'deletable-template',
            exerciseId: exercises[0].id,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _pumpList(tester, harness);
    expect(find.text('待刪除的模板'), findsOneWidget);

    await tester.tap(find.byKey(const Key('templateDeleteButton_deletable-template')));
    await tester.pumpAndSettle();
    expect(find.text('刪除模板'), findsOneWidget); // 確認對話框標題

    await tester.tap(find.byKey(const Key('templateDeleteConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.text('待刪除的模板'), findsNothing);
    expect(await repo.fetchById('deletable-template'), isNull);
  });

  testWidgets('系統模板不顯示編輯/刪除按鈕;controller 層直接嘗試刪除系統模板會被擋,資料庫仍是 5 筆', (tester) async {
    final harness = await _setUpHarness();

    await _pumpList(tester, harness);

    final systemTemplate = harness.container
        .read(templatesControllerProvider)
        .value!
        .firstWhere((t) => t.isSystem);

    expect(find.byKey(Key('templateEditButton_${systemTemplate.id}')), findsNothing);
    expect(find.byKey(Key('templateDeleteButton_${systemTemplate.id}')), findsNothing);

    // 直接呼叫 controller(繞過 UI,UI 本來就不給按)驗證保護真的在,不是
    // 只靠「畫面沒放按鈕」這種假防護——TemplateRepository.delete 本身的
    // WHERE 子句已經排除 isSystem = true(既有方法,寫入 0 筆、不報錯),
    // 這裡驗證的是 controller 這一層會明確拋錯而不是默默沒反應。
    await expectLater(
      harness.container.read(templatesControllerProvider.notifier).deleteTemplate(systemTemplate),
      throwsA(isA<StateError>()),
    );

    final repo = TemplateRepository(harness.db, ExerciseRepository(harness.db));
    final systemTemplatesAfter = await repo.fetchSystemTemplates();
    expect(systemTemplatesAfter, hasLength(5));
  });

  testWidgets('建立模板失敗時:停留在表單畫面、解除 loading、顯示錯誤 SnackBar', (tester) async {
    final harness = await _setUpHarness(
      templateRepoBuilder: (db) =>
          _ThrowingCreateTemplateRepository(db, ExerciseRepository(db)),
    );
    final exercises = await ExerciseRepository(harness.db).fetchAll();

    await _pumpList(tester, harness);

    await tester.tap(find.byKey(const Key('templateListAddButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('templateFormNameField')), '會失敗的模板');
    await _pickExercisesInForm(tester, [exercises[0].id]);

    await tester.tap(find.byKey(const Key('templateFormSaveButton')));
    await tester.pumpAndSettle();

    // 沒有 pop:還在表單畫面(名稱欄位、儲存按鈕都還在)。
    expect(find.byKey(const Key('templateFormNameField')), findsOneWidget);
    expect(find.byKey(const Key('templateFormSaveButton')), findsOneWidget);
    // loading 已解除:找不到 CircularProgressIndicator。
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 錯誤有明確顯示(SnackBar)。
    expect(find.textContaining('建立模板失敗'), findsOneWidget);
  });

  testWidgets(
      'minor:組數欄位打非數字字元 -> 顯示 inline 錯誤且擋下儲存(不是靜默把值變成 null)',
      (tester) async {
    final harness = await _setUpHarness();
    final exercises = await ExerciseRepository(harness.db).fetchAll();

    await _pumpList(tester, harness);
    await tester.tap(find.byKey(const Key('templateListAddButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('templateFormNameField')), '打錯字的模板');
    await _pickExercisesInForm(tester, [exercises[0].id]);

    final setsFieldKey = Key('templateFormSetsField_${exercises[0].id}');
    await tester.enterText(find.byKey(setsFieldKey), 'abc');
    await tester.pump();

    expect(find.text('請輸入 0 或正整數'), findsOneWidget);

    await tester.tap(find.byKey(const Key('templateFormSaveButton')));
    await tester.pumpAndSettle();

    // 沒有被存進去:還在表單畫面,且資料庫沒有這筆模板。
    expect(find.byKey(const Key('templateFormNameField')), findsOneWidget);
    final repo = TemplateRepository(harness.db, ExerciseRepository(harness.db));
    final landed = await repo.fetchAll(testUserId);
    expect(landed.where((t) => t.name == '打錯字的模板'), isEmpty);
  });
}
