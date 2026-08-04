// ExercisePickerSheet widget seam:pump 一個真實頁面(repositories/provider 一律
// 用真的,只換 appDatabaseProvider 為 in-memory DB、sharedPreferencesProvider
// 為 mock prefs),透過 [showExercisePicker] 觸發 sheet,斷言使用者可見行為
// ——不測 controller 內部欄位(controller 的計算邏輯獨立在
// exercise_picker_state_test.dart 用純 Dart unit test 驗證)。
//
// 每個 test 用全新的 in-memory DB(`openTestDatabase()` 觸發 onCreate ->
// createAll + seedIfEmpty,已內建 66 筆系統動作)+ mock SharedPreferences,
// 彼此互不干擾。

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
import 'package:workout_record/features/workout/exercise_picker/exercise_picker_controller.dart';
import 'package:workout_record/features/workout/exercise_picker/exercise_picker_sheet.dart';

import '../../../data/test_helpers.dart';

/// 建立自訂動作寫入失敗的 `create()`,其餘方法沿用真實實作——用來驗證
/// quick add 表單的失敗路徑真的會浮出錯誤、解除 loading,而不是
/// fire-and-forget(brief 常備紀律)。
class _ThrowingCreateExerciseRepository extends ExerciseRepository {
  _ThrowingCreateExerciseRepository(super.db);

  @override
  Future<void> create(Exercise exercise) async {
    throw Exception('模擬自訂動作寫入失敗(失敗路徑測試用)');
  }
}

/// 觸發選動作器的最小 host 頁面:一顆按鈕開 sheet,回傳結果(含「尚未有
/// 結果」與「明確回傳 null」兩種狀態的區分)顯示在畫面上供斷言。
class _PickerHostPage extends StatefulWidget {
  const _PickerHostPage({this.multiSelect = false});

  final bool multiSelect;

  @override
  State<_PickerHostPage> createState() => _PickerHostPageState();
}

class _PickerHostPageState extends State<_PickerHostPage> {
  bool _hasResult = false;
  List<Exercise>? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            key: const Key('open_picker_button'),
            onPressed: () async {
              final result = await showExercisePicker(context, multiSelect: widget.multiSelect);
              setState(() {
                _hasResult = true;
                _result = result;
              });
            },
            child: const Text('開啟選動作器'),
          ),
          if (_hasResult)
            Text(
              _result == null
                  ? 'picker-result:null'
                  : 'picker-result:${_result!.map((e) => e.id).join(',')}',
            ),
        ],
      ),
    );
  }
}

typedef _Harness = ({AppDatabase db, SharedPreferences prefs, ExerciseRepository exerciseRepo});

Future<_Harness> _setUpHarness({
  Map<String, Object> extraPrefs = const {},
  ExerciseRepository Function(AppDatabase db)? exerciseRepoBuilder,
}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId, ...extraPrefs});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);
  final exerciseRepo = exerciseRepoBuilder?.call(db) ?? ExerciseRepository(db);
  return (db: db, prefs: prefs, exerciseRepo: exerciseRepo);
}

Future<void> _pumpHost(
  WidgetTester tester,
  _Harness harness, {
  bool multiSelect = false,
}) async {
  // 視窗刻意開得很高(遠超實際裝置尺寸):選動作器的清單最多 66 + 1 筆
  // (含測試新增的自訂動作),`ListView` 只會 build 落在可視範圍內的項目,
  // 撐一個容得下全部列的視窗高度,測試就能直接用 key/text 找到任何一列,
  // 不需要另外處理捲動(捲動到剛好「勉強可視」的邊界時,tester.tap 算出的
  // 中心點座標偶爾會落在視窗外緣,造成假性 hit-test 失敗,見這個 commit
  // 修掉的那版用 scrollUntilVisible 的 flaky 寫法)。
  tester.view.physicalSize = const Size(1080, 9000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(harness.prefs),
        appDatabaseProvider.overrideWithValue(harness.db),
        exerciseRepositoryProvider.overrideWithValue(harness.exerciseRepo),
      ],
      child: MaterialApp(home: _PickerHostPage(multiSelect: multiSelect)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open_picker_button')));
  await tester.pumpAndSettle();
}

void main() {
  group('分類瀏覽', () {
    testWidgets('點背部分類看得到硬舉;點腿部分類也看得到硬舉(刻意跨分類重複)', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      await tester.tap(find.byKey(Key('category_chip_${SeedCategoryIds.back}')));
      await tester.pumpAndSettle();
      expect(find.text('硬舉'), findsOneWidget);
      expect(find.text('槓鈴划船'), findsOneWidget);
      // 胸部動作不該出現在背部分類清單。
      expect(find.text('伏地挺身'), findsNothing);

      await tester.tap(find.byKey(Key('category_chip_${SeedCategoryIds.legs}')));
      await tester.pumpAndSettle();
      expect(find.text('硬舉'), findsOneWidget);
      expect(find.text('深蹲'), findsOneWidget);
      expect(find.text('槓鈴划船'), findsNothing);
    });

    testWidgets('「全部」分類顯示全部種子動作(66 筆內含兩筆刻意重複命名)', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      expect(find.byKey(const Key('category_chip_all')), findsOneWidget);

      // 兩筆分別位於清單前段/後段(依字典序排序)的動作都看得到,確認
      // 「全部」視圖真的涵蓋整份種子清單,不是只看首屏。
      final exercises = await harness.exerciseRepo.fetchAll();
      final sortedByName = [...exercises]..sort((a, b) => a.name.compareTo(b.name));
      final first = sortedByName.first;
      final last = sortedByName.last;

      expect(find.byKey(Key('exercise_row_${first.id}')), findsOneWidget);
      expect(find.byKey(Key('exercise_row_${last.id}')), findsOneWidget);
    });
  });

  group('即時搜尋', () {
    testWidgets('中文關鍵字「臥推」過濾出對應動作,搜尋框清空後恢復分類視圖', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      await tester.enterText(find.byKey(const Key('exercise_picker_search_field')), '臥推');
      await tester.pumpAndSettle();

      expect(find.text('槓鈴臥推'), findsOneWidget);
      expect(find.text('啞鈴臥推'), findsOneWidget);
      // 不含「臥推」關鍵字、也非胸部主要肌群顯示名稱包含它的動作不該出現。
      expect(find.text('深蹲'), findsNothing);
      // 搜尋中不顯示分類 tab。
      expect(find.byKey(const Key('category_chip_all')), findsNothing);

      await tester.tap(find.byKey(const Key('exercise_picker_clear_search_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category_chip_all')), findsOneWidget);
    });

    testWidgets('英文關鍵字「Squat」過濾出深蹲(nameEn 比對)', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      await tester.enterText(find.byKey(const Key('exercise_picker_search_field')), 'Squat');
      await tester.pumpAndSettle();

      expect(find.text('深蹲'), findsOneWidget);
      expect(find.text('前蹲'), findsOneWidget);
      expect(find.text('槓鈴臥推'), findsNothing);
    });

    testWidgets('搜尋不到的關鍵字顯示空狀態文案', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      await tester.enterText(
        find.byKey(const Key('exercise_picker_search_field')),
        '不存在的動作關鍵字xyz',
      );
      await tester.pumpAndSettle();

      final emptyState = find.byKey(const Key('exercise_picker_empty_search'));
      expect(emptyState, findsOneWidget);
      // 限定在空狀態容器內找文字——搜尋框自己目前的輸入值也字面上包含同一個
      // 字串,不限定範圍的話 find.textContaining 會連搜尋框的 EditableText
      // 一起撞到,變成「找到兩個」。
      expect(
        find.descendant(of: emptyState, matching: find.textContaining('不存在的動作關鍵字xyz')),
        findsOneWidget,
      );
    });
  });

  group('回傳值契約', () {
    testWidgets('單選模式:點動作即回傳 [exercise] 並關閉', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      final exercises = await harness.exerciseRepo.fetchAll();
      final target = exercises.firstWhere((e) => e.name == '深蹲');

      await tester.tap(find.byKey(Key('exercise_row_${target.id}')));
      await tester.pumpAndSettle();

      expect(find.text('picker-result:${target.id}'), findsOneWidget);
      // sheet 已關閉。
      expect(find.byKey(const Key('exercise_picker_search_field')), findsNothing);
    });

    testWidgets('多選模式:勾多個後按確認,回傳所有勾選的清單', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness, multiSelect: true);
      await _openPicker(tester);

      final exercises = await harness.exerciseRepo.fetchAll();
      final first = exercises.firstWhere((e) => e.name == '深蹲');
      final second = exercises.firstWhere((e) => e.name == '前蹲');

      await tester.tap(find.byKey(Key('exercise_row_${first.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('exercise_row_${second.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exercise_picker_confirm_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('exercise_picker_confirm_button')));
      await tester.pumpAndSettle();

      final resultFinder = find.textContaining('picker-result:');
      expect(resultFinder, findsOneWidget);
      final resultText = (tester.widget<Text>(resultFinder)).data!;
      final ids = resultText.substring('picker-result:'.length).split(',');
      expect(ids, containsAll([first.id, second.id]));
      expect(ids.length, 2);
    });

    testWidgets('取消(左上角按鈕)回傳 null', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      await tester.tap(find.byKey(const Key('exercise_picker_cancel_button')));
      await tester.pumpAndSettle();

      expect(find.text('picker-result:null'), findsOneWidget);
    });

    testWidgets('滑掉(點背景關閉)回傳 null', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      // 點 sheet 之外的區域(scrim)觸發預設的 modal barrier dismiss。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('picker-result:null'), findsOneWidget);
    });
  });

  group('自訂動作快速新增', () {
    testWidgets('成功:立即出現在列表、可搜尋、可選,且獨立 SELECT 驗證 isSystem=false 已落地', (
      tester,
    ) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      await tester.tap(find.byKey(const Key('exercise_picker_add_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('quick_add_name_field')), '測試自訂動作A');
      await tester.tap(find.byKey(const Key('quick_add_submit_button')));
      await tester.pumpAndSettle();

      // 單選模式對等 iOS:新增即選取、直接關閉整個選動作器。
      final rows = await (harness.db.select(
        harness.db.exercises,
      )..where((t) => t.isSystem.equals(false))).get();
      expect(rows, hasLength(1));
      expect(rows.single.name, '測試自訂動作A');
      expect(rows.single.isSystem, isFalse);

      expect(find.text('picker-result:${rows.single.id}'), findsOneWidget);
    });

    testWidgets('新增後(多選模式)不關閉主 sheet,新動作立即可搜得到、選得到', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness, multiSelect: true);
      await _openPicker(tester);

      await tester.tap(find.byKey(const Key('exercise_picker_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('quick_add_name_field')), '測試自訂動作B');
      await tester.tap(find.byKey(const Key('quick_add_submit_button')));
      await tester.pumpAndSettle();

      // 主 sheet 仍開著(搜尋框還在)。
      expect(find.byKey(const Key('exercise_picker_search_field')), findsOneWidget);

      final rows = await (harness.db.select(
        harness.db.exercises,
      )..where((t) => t.name.equals('測試自訂動作B'))).get();
      final createdId = rows.single.id;

      // 新動作立即可搜尋得到——用 exercise_row key 而非 find.text 比對,
      // 避免跟搜尋框自己目前的輸入值(同一個字串)撞在一起被判定成「找到
      // 兩個」。
      await tester.enterText(
        find.byKey(const Key('exercise_picker_search_field')),
        '測試自訂動作B',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(Key('exercise_row_$createdId')), findsOneWidget);

      // 不用再手動點一次那一列——多選模式下 `_openQuickAdd` 新增成功已經
      // 自動把新動作勾選起來了(見 exercise_picker_sheet.dart 的
      // `_openQuickAdd` 說明),這裡「選得到」驗證的是它已經在勾選清單裡,
      // 不是重新勾一次(重新點一下反而會把它取消勾選)。
      await tester.tap(find.byKey(const Key('exercise_picker_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.text('picker-result:$createdId'), findsOneWidget);
    });

    testWidgets('名稱空白時 submit 被表單驗證擋下,不會打 DB', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      await tester.tap(find.byKey(const Key('exercise_picker_add_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick_add_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('請輸入動作名稱'), findsOneWidget);
      // 表單還在(沒有 pop)。
      expect(find.byKey(const Key('quick_add_name_field')), findsOneWidget);
    });

    testWidgets('失敗:解除 loading、浮出 SnackBar 錯誤訊息,表單不關閉(不 fire-and-forget)', (
      tester,
    ) async {
      final harness = await _setUpHarness(
        exerciseRepoBuilder: (db) => _ThrowingCreateExerciseRepository(db),
      );
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      await tester.tap(find.byKey(const Key('exercise_picker_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('quick_add_name_field')), '會失敗的動作');
      await tester.tap(find.byKey(const Key('quick_add_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('新增動作失敗,請稍後再試'), findsOneWidget);
      // 表單仍在畫面上,可以修改後重試(沒有被 pop)。
      expect(find.byKey(const Key('quick_add_name_field')), findsOneWidget);
      // loading 已解除:送出按鈕文案恢復成「新增」而不是轉圈。
      expect(find.text('新增'), findsOneWidget);

      // 沒有任何自訂動作被寫入。
      final rows = await (harness.db.select(
        harness.db.exercises,
      )..where((t) => t.isSystem.equals(false))).get();
      expect(rows, isEmpty);
    });
  });

  group('最愛(常用動作)持久化', () {
    testWidgets('切換最愛後寫入 SharedPreferences,重開 sheet 後該動作排在清單最前面', (
      tester,
    ) async {
      final harness = await _setUpHarness();
      await _pumpHost(tester, harness);
      await _openPicker(tester);

      final exercises = await harness.exerciseRepo.fetchAll();
      final target = exercises.firstWhere((e) => e.name == '棒式'); // 核心分類,字母序不會排最前

      await tester.tap(find.byKey(Key('exercise_favorite_star_${target.id}')));
      await tester.pumpAndSettle();

      // 參照值:直讀 prefs,獨立於被測 widget 之外驗證持久化真的落地。
      expect(
        harness.prefs.getStringList(kFavoriteExerciseIdsKey),
        containsAll([target.id]),
      );

      // 關閉 sheet 再重新開啟(provider 是 autoDispose,重開會重新 build)。
      await tester.tap(find.byKey(const Key('exercise_picker_cancel_button')));
      await tester.pumpAndSettle();
      await _openPicker(tester);

      // 明確指到動作清單本身(`exercise_picker_list`)——畫面上另外還有分類
      // tab 那個橫向 ListView,`find.byType(ListView).first` 依 widget 樹
      // 深度優先順序撿到的其實是分類 tab,不是動作清單。
      final exerciseListView = find.byKey(const Key('exercise_picker_list'));
      final firstRowFinder = find.descendant(
        of: exerciseListView,
        matching: find.byKey(Key('exercise_row_${target.id}')),
      );
      expect(firstRowFinder, findsOneWidget);

      // 置頂驗證:清單裡第一列就是這個動作(用畫面上第一個 ListTile 的
      // key 比對,不是重新算一次排序邏輯抄同一份公式)。
      final firstTileKey = tester
          .widgetList<ListTile>(find.descendant(of: exerciseListView, matching: find.byType(ListTile)))
          .first
          .key;
      expect(firstTileKey, equals(Key('exercise_row_${target.id}')));

      // 星星圖示仍是已收藏狀態。
      final starIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(Key('exercise_favorite_star_${target.id}')),
          matching: find.byType(Icon),
        ),
      );
      expect(starIcon.icon, Icons.star);
    });
  });
}
