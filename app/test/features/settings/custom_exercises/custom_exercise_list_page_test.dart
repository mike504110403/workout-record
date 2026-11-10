// 自定義動作列表/表單 widget seam:真實 controller + 真實 Drift repository(in-memory),
// 斷言使用者可見行為與 DB 落地。
//
// 變異清單(各自讓對應測試必紅):
// - 列表改列 fetchAll → 「只列自定義動作」紅
// - confirmDismiss 恆回 true / 對話框「取消」也刪 → 「滑動刪除取消」紅
// - 刪除後不 invalidate 選動作器 / 改成 permanentDelete → 「刪除後選動作器」紅
// - 設定頁入口拿掉 push → settings_page_test 的入口測試紅
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide Exercise;
import 'package:workout_record/data/db/seed_data.dart';
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/custom_exercises/custom_exercise_list_page.dart';
import 'package:workout_record/features/settings/settings_page.dart';
import 'package:workout_record/features/workout/exercise_picker/exercise_picker_sheet.dart';

import '../../../data/test_helpers.dart';

Exercise _custom(
  String id,
  String name, {
  String categoryId = SeedCategoryIds.chest,
  PrimaryMuscleGroup? muscle = PrimaryMuscleGroup.chest,
}) {
  final now = DateTime(2026, 1, 1);
  return Exercise(
    id: id,
    name: name,
    categoryId: categoryId,
    type: ExerciseType.machine,
    primaryMuscleGroup: muscle,
    movementPattern: MovementPattern.push,
    isSystem: false,
    userId: testUserId,
    createdAt: now,
    updatedAt: now,
  );
}

/// 首頁有兩顆按鈕:開自定義動作列表(push 頁面)、開選動作器(bottom sheet),
/// 用來驗證「在列表頁刪除/新增後,回到選動作器看得到變更」。
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            key: const Key('open_list'),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const CustomExerciseListPage())),
            child: const Text('開列表'),
          ),
          ElevatedButton(
            key: const Key('open_picker'),
            onPressed: () => showExercisePicker(context),
            child: const Text('開選動作器'),
          ),
        ],
      ),
    );
  }
}

typedef _Harness = ({AppDatabase db, ExerciseRepository repo});

Future<_Harness> _pump(WidgetTester tester, {Widget home = const _Host()}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);

  // 選動作器列 66+ 筆,視窗開高讓所有列都 mount(理由同 exercise_picker_sheet_test.dart)。
  tester.view.physicalSize = const Size(1080, 9000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
  return (db: db, repo: DriftExerciseRepository(db));
}

Future<void> _openList(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open_list')));
  await tester.pumpAndSettle();
}

Future<void> _swipeToDelete(WidgetTester tester, String id) async {
  await tester.drag(find.byKey(Key('customExerciseTile_$id')), const Offset(-800, 0));
  await tester.pumpAndSettle();
}

Future<void> _openPickerAndClose(WidgetTester tester, void Function() expectations) async {
  await tester.tap(find.byKey(const Key('open_picker')));
  await tester.pumpAndSettle();
  expectations();
  // 點背景關閉 bottom sheet。
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('只列自定義動作:不列 66 筆系統動作;空狀態顯示提示', (tester) async {
    final h = await _pump(tester);
    await _openList(tester);

    expect(find.byKey(const Key('customExerciseEmptyState')), findsOneWidget);
    expect(find.text('槓鈴臥推'), findsNothing);

    // 新增兩筆自定義動作後重進列表(autoDispose,重進即重查)。
    await h.repo.create(_custom('c-1', '史密斯臥推'));
    await h.repo.create(_custom('c-2', '側拉'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openList(tester);

    expect(find.byKey(const Key('customExerciseEmptyState')), findsNothing);
    expect(find.byKey(const Key('customExerciseTile_c-1')), findsOneWidget);
    expect(find.byKey(const Key('customExerciseTile_c-2')), findsOneWidget);
    expect(find.text('史密斯臥推'), findsOneWidget);
    expect(find.text('槓鈴臥推'), findsNothing); // 系統動作不列
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('新增:填表儲存後出現在列表、寫進 DB,且選動作器看得到', (tester) async {
    final h = await _pump(tester);
    await _openList(tester);

    await tester.tap(find.byKey(const Key('customExerciseAddButton')));
    await tester.pumpAndSettle();
    expect(find.text('新增動作'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('customExerciseNameField')), '彈力帶划船');
    await tester.enterText(find.byKey(const Key('customExerciseDescriptionField')), '居家用');
    // 換分類 → 主要肌群自動帶出。
    await tester.tap(find.byKey(const Key('customExerciseCategoryField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('背').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customExerciseSaveButton')));
    await tester.pumpAndSettle();

    // 回到列表,出現新動作。
    expect(find.text('彈力帶划船'), findsOneWidget);
    final rows = await h.repo.getCustomExercises();
    expect(rows, hasLength(1));
    expect(rows.single.categoryId, SeedCategoryIds.back);
    expect(rows.single.primaryMuscleGroup, PrimaryMuscleGroup.back);
    expect(rows.single.description, '居家用');
    expect(rows.single.userId, testUserId);

    // 選動作器看得到。
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openPickerAndClose(tester, () {
      expect(find.text('彈力帶划船'), findsOneWidget);
    });
  });

  testWidgets('新增:名稱空白或與既有自定義動作重名 → 顯示錯誤、不寫入', (tester) async {
    final h = await _pump(tester);
    await h.repo.create(_custom('c-1', '史密斯臥推'));
    await _openList(tester);

    await tester.tap(find.byKey(const Key('customExerciseAddButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customExerciseSaveButton')));
    await tester.pumpAndSettle();
    expect(find.text('動作名稱不能為空'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('customExerciseNameField')), '史密斯臥推');
    await tester.tap(find.byKey(const Key('customExerciseSaveButton')));
    await tester.pumpAndSettle();
    expect(find.text('此動作名稱已存在'), findsOneWidget);
    expect(await h.repo.getCustomExercises(), hasLength(1));
  });

  testWidgets('編輯:改名稱與分類存檔後列表與 DB 都更新;選動作器看到新名稱', (tester) async {
    final h = await _pump(tester);
    await h.repo.create(_custom('c-1', '舊名稱動作'));
    await _openList(tester);

    await tester.tap(find.byKey(const Key('customExerciseEditButton_c-1')));
    await tester.pumpAndSettle();
    expect(find.text('編輯動作'), findsOneWidget);
    // 表單預填既有名稱。
    expect(find.widgetWithText(TextFormField, '舊名稱動作'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('customExerciseNameField')), '新名稱動作');
    await tester.tap(find.byKey(const Key('customExerciseCategoryField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('腿').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customExerciseSaveButton')));
    await tester.pumpAndSettle();

    expect(find.text('新名稱動作'), findsOneWidget);
    expect(find.text('舊名稱動作'), findsNothing);
    final row = (await h.repo.fetchById('c-1'))!;
    expect(row.name, '新名稱動作');
    expect(row.categoryId, SeedCategoryIds.legs);
    expect(row.primaryMuscleGroup, PrimaryMuscleGroup.legs);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openPickerAndClose(tester, () {
      expect(find.text('新名稱動作'), findsOneWidget);
      expect(find.text('舊名稱動作'), findsNothing);
    });
  });

  testWidgets('滑動刪除 → 取消:對話框出現、動作還在、DB 仍 active', (tester) async {
    final h = await _pump(tester);
    await h.repo.create(_custom('c-1', '史密斯臥推'));
    await _openList(tester);

    await _swipeToDelete(tester, 'c-1');
    expect(find.text('刪除動作'), findsOneWidget); // 確認對話框
    await tester.tap(find.byKey(const Key('customExerciseDeleteCancelButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customExerciseTile_c-1')), findsOneWidget);
    expect((await h.repo.fetchById('c-1'))!.isActive, isTrue);
    expect(await h.repo.getCustomExercises(), hasLength(1));
  });

  testWidgets('滑動刪除 → 確認:列表消失、DB 軟刪除(列保留 isActive=false)、選動作器看不到', (tester) async {
    final h = await _pump(tester);
    await h.repo.create(_custom('c-1', '史密斯臥推'));
    await _openList(tester);
    // 刪除前選動作器看得到(排除「本來就沒顯示」的假陽性)。
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openPickerAndClose(tester, () {
      expect(find.text('史密斯臥推'), findsOneWidget);
    });
    await _openList(tester);

    await _swipeToDelete(tester, 'c-1');
    await tester.tap(find.byKey(const Key('customExerciseDeleteConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customExerciseTile_c-1')), findsNothing);
    expect(find.byKey(const Key('customExerciseEmptyState')), findsOneWidget);
    final row = await h.repo.fetchById('c-1');
    expect(row, isNotNull); // 軟刪除:列還在(歷史/模板引用不壞)
    expect(row!.isActive, isFalse);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openPickerAndClose(tester, () {
      expect(find.text('史密斯臥推'), findsNothing);
    });
  });

  testWidgets('編輯頁「刪除動作」按鈕:取消不刪;確認才刪並回到列表', (tester) async {
    final h = await _pump(tester);
    await h.repo.create(_custom('c-1', '史密斯臥推'));
    await _openList(tester);

    await tester.tap(find.byKey(const Key('customExerciseEditButton_c-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('customExerciseDeleteButton')));
    await tester.tap(find.byKey(const Key('customExerciseDeleteButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customExerciseDeleteCancelButton')));
    await tester.pumpAndSettle();
    expect(find.text('編輯動作'), findsOneWidget); // 還在表單
    expect((await h.repo.fetchById('c-1'))!.isActive, isTrue);

    await tester.tap(find.byKey(const Key('customExerciseDeleteButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('customExerciseDeleteConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.text('編輯動作'), findsNothing);
    expect(find.byKey(const Key('customExerciseTile_c-1')), findsNothing);
    expect((await h.repo.fetchById('c-1'))!.isActive, isFalse);
  });

  testWidgets('設定頁入口:「自定義動作」→ 導到列表頁', (tester) async {
    await _pump(tester, home: const SettingsPage());
    await tester.tap(find.byKey(const Key('settingsCustomExercisesEntry')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '自定義動作'), findsOneWidget);
  });
}
