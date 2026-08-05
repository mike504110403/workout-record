// BodyWeightTab widget seam:pump 真實 widget(repositories/provider 一律用
// 真的,只換 appDatabaseProvider 為 in-memory DB、sharedPreferencesProvider
// 為 mock prefs),斷言畫面呈現的圖表資料/統計數字/文案——不測 controller
// 內部欄位。CRUD 一律走真實 repository 寫入,額外用獨立 SELECT
// (harness.bodyWeightRepo.fetchAll())驗證是真的落地,不是單純的本地畫面
// 狀態(同 dashboard_page_test.dart 的既有慣例)。
//
// 變異清單(逐規則列,每條都有對應斷言守住):
//   - 排序反轉必紅:圖表資料點必須是 measuredAt 由舊到新(x=0 是最舊那筆),
//     若實作漏掉 sortBodyWeightsAscending、直接用 entriesDesc(新到舊)畫圖,
//     spots.first/spots.last 的 y 值斷言會失敗。
//   - 變化幅度算錯(取錯兩筆)必紅:種子資料的變化幅度用手算值斷言
//     (見「多筆紀錄」測試),若實作誤用 max-min 或首尾相減之類的算法,
//     斷言的具體數字會對不上。
//   - 目標線在無目標時畫出必紅:分別測「有目標」與「無目標」兩種情境,
//     斷言 `extraLinesData.horizontalLines` 的長度,若實作忘記判斷
//     targetWeight == null、一律畫線,「無目標」情境的斷言會失敗。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide BodyWeight, UserGoal;
import 'package:workout_record/data/models/body_weight.dart';
import 'package:workout_record/data/models/user_goal.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/body_weight_repository.dart';
import 'package:workout_record/data/repositories/user_goal_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/stats/body_weight/body_weight_tab.dart';

import '../../../data/test_helpers.dart';

// MARK: - 失敗路徑用的 throwing repository(仿 dashboard_page_test.dart 的
// _ThrowingBodyWeightRepository 慣例:只覆寫要測的那個方法,其餘沿用真實
// 實作)。

class _ThrowingCreateBodyWeightRepository extends BodyWeightRepository {
  _ThrowingCreateBodyWeightRepository(super.db);

  @override
  Future<void> create(BodyWeight bodyWeight) async {
    throw Exception('模擬新增體重失敗(失敗路徑測試用)');
  }
}

class _ThrowingUpdateBodyWeightRepository extends BodyWeightRepository {
  _ThrowingUpdateBodyWeightRepository(super.db);

  @override
  Future<void> update(BodyWeight bodyWeight) async {
    throw Exception('模擬更新體重失敗(失敗路徑測試用)');
  }
}

class _ThrowingDeleteBodyWeightRepository extends BodyWeightRepository {
  _ThrowingDeleteBodyWeightRepository(super.db);

  @override
  Future<void> delete(String id) async {
    throw Exception('模擬刪除體重失敗(失敗路徑測試用)');
  }
}

class _Harness {
  _Harness(this.db, this.container)
      : bodyWeightRepo = BodyWeightRepository(db),
        userGoalRepo = UserGoalRepository(db);

  final AppDatabase db;
  final ProviderContainer container;
  final BodyWeightRepository bodyWeightRepo;
  final UserGoalRepository userGoalRepo;
}

Future<_Harness> _setUpHarness({
  BodyWeightRepository Function(AppDatabase db)? bodyWeightRepoBuilder,
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
      if (bodyWeightRepoBuilder != null)
        bodyWeightRepositoryProvider.overrideWithValue(bodyWeightRepoBuilder(db)),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(db, container);
}

Future<void> _pump(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: Scaffold(body: BodyWeightTab())),
    ),
  );
  await tester.pumpAndSettle();
}

BodyWeight _entry({
  required String id,
  required double weight,
  required DateTime measuredAt,
  String? note,
}) {
  final now = DateTime.now();
  return BodyWeight(
    id: id,
    userId: testUserId,
    weight: weight,
    measuredAt: measuredAt,
    note: note,
    createdAt: now,
    updatedAt: now,
  );
}

/// 種三筆體重紀錄:newest(78.0)/middle(76.0)/oldest(74.0),刻意用非插入
/// 順序的 measuredAt(newest 先插入),驗證畫面呈現不依賴插入順序、只依賴
/// measuredAt。
Future<void> _seedThreeEntries(_Harness harness) async {
  final now = DateTime.now();
  // 「newest」刻意跟「現在」錯開至少 2 分鐘,不用 `now` 本身——Drift 的
  // dateTime() 欄位預設用整數秒精度存欄位(不是毫秒),「新增」測試會緊接著
  // 用真實的 `DateTime.now()`(表單預設的 measuredAt)寫入一筆新紀錄,若
  // 這裡的種子跟那筆新寫入落在同一秒,兩者 measuredAt 會並列,
  // `getLatestWeight`/`fetchAll` 的排序在並列情況下由 SQLite 決定順序,不
  // 保證新寫入的那筆排到最前面,測試會間歇性 flaky(同
  // dashboard_page_test.dart 「最新體重」測試吃過的同一個虧,見該檔案
  // 開頭註解)。這是資料層既有的秒級精度限制,不在本波「不碰 data/」的
  // 範圍內修,測試端刻意拉開時間差避開它。
  await harness.bodyWeightRepo.create(
    _entry(id: 'bw-newest', weight: 78.0, measuredAt: now.subtract(const Duration(minutes: 2))),
  );
  await harness.bodyWeightRepo.create(
    _entry(id: 'bw-oldest', weight: 74.0, measuredAt: now.subtract(const Duration(days: 10))),
  );
  await harness.bodyWeightRepo.create(
    _entry(id: 'bw-middle', weight: 76.0, measuredAt: now.subtract(const Duration(days: 5))),
  );
}

LineChart _findLineChart(WidgetTester tester) {
  return tester.widget<LineChart>(
    find.descendant(of: find.byKey(const Key('bodyWeightChart')), matching: find.byType(LineChart)),
  );
}

void main() {
  group('空狀態', () {
    testWidgets('尚未有任何體重紀錄時顯示空狀態,不顯示圖表/統計/列表', (tester) async {
      final harness = await _setUpHarness();

      await _pump(tester, harness);

      expect(find.byKey(const Key('emptyBodyWeightView')), findsOneWidget);
      expect(find.text('尚未記錄體重'), findsOneWidget);
      expect(find.byKey(const Key('bodyWeightChart')), findsNothing);
      expect(find.byKey(const Key('bodyWeightStatsGrid')), findsNothing);
    });

    testWidgets('空狀態按下新增按鈕,開啟表單', (tester) async {
      final harness = await _setUpHarness();
      await _pump(tester, harness);

      await tester.tap(find.byKey(const Key('emptyBodyWeightAddButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bodyWeightFormWeightField')), findsOneWidget);
    });
  });

  group('趨勢圖', () {
    testWidgets('資料點數與種子一致,且依 measuredAt 由舊到新排序(排序反轉必紅)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);

      await _pump(tester, harness);

      final chart = _findLineChart(tester);
      final spots = chart.data.lineBarsData.single.spots;

      expect(spots.length, 3);
      // x=0 必須是最舊的一筆(74.0kg),x=2 必須是最新的一筆(78.0kg)——若
      // 實作直接拿 entriesDesc(新到舊)畫圖而漏掉反轉,這裡會變成
      // spots.first.y == 78.0,斷言失敗。
      expect(spots.first.y, 74.0);
      expect(spots[1].y, 76.0);
      expect(spots.last.y, 78.0);
    });

    testWidgets('有設定目標體重時畫出目標線(目標線在無目標時畫出必紅,正例)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(id: 'goal-1', userId: testUserId, targetWeight: 70.0, createdAt: now, updatedAt: now),
      );

      await _pump(tester, harness);

      final chart = _findLineChart(tester);
      expect(chart.data.extraLinesData.horizontalLines.length, 1);
      expect(chart.data.extraLinesData.horizontalLines.single.y, 70.0);
    });

    testWidgets('未設定目標體重時不畫目標線(目標線在無目標時畫出必紅,反例)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);

      await _pump(tester, harness);

      final chart = _findLineChart(tester);
      expect(chart.data.extraLinesData.horizontalLines, isEmpty);
    });
  });

  group('統計資訊卡', () {
    testWidgets('當前/目標/平均/最高/最低/變化幅度依手算參照值顯示', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(id: 'goal-1', userId: testUserId, targetWeight: 70.0, createdAt: now, updatedAt: now),
      );

      await _pump(tester, harness);

      // 手算:current=78.0(最新), average=(78+76+74)/3=76.0, max=78.0,
      // min=74.0, change=78.0-76.0=2.0(最新減次新,不是 max-min=4.0)。
      expect(
        find.descendant(
          of: find.byKey(const Key('bodyWeightStatCard-current')),
          matching: find.text('78.0 kg'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('bodyWeightStatCard-target')),
          matching: find.text('70.0 kg'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('bodyWeightStatCard-average')),
          matching: find.text('76.0 kg'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('bodyWeightStatCard-max')),
          matching: find.text('78.0 kg'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('bodyWeightStatCard-min')),
          matching: find.text('74.0 kg'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('bodyWeightStatCard-change')),
          matching: find.text('+2.0 kg'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('未設定目標體重時,目標卡顯示佔位符「—」', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);

      await _pump(tester, harness);

      expect(
        find.descendant(of: find.byKey(const Key('bodyWeightStatCard-target')), matching: find.text('—')),
        findsOneWidget,
      );
    });
  });

  group('紀錄列表', () {
    testWidgets('依 measuredAt 由新到舊排序', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);

      await _pump(tester, harness);

      final newestY = tester.getCenter(find.byKey(const Key('bodyWeightRow-bw-newest'))).dy;
      final middleY = tester.getCenter(find.byKey(const Key('bodyWeightRow-bw-middle'))).dy;
      final oldestY = tester.getCenter(find.byKey(const Key('bodyWeightRow-bw-oldest'))).dy;

      expect(newestY, lessThan(middleY));
      expect(middleY, lessThan(oldestY));
    });
  });

  group('新增', () {
    testWidgets('填寫體重後儲存:表單關閉、列表與圖表刷新、真的寫入 DB(獨立 SELECT 驗證)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);

      await _pump(tester, harness);

      await tester.tap(find.byKey(const Key('addBodyWeightButton')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('bodyWeightFormWeightField')), '82.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bodyWeightFormSaveButton')));
      await tester.pumpAndSettle();

      // 表單已關閉。
      expect(find.byKey(const Key('bodyWeightFormWeightField')), findsNothing);

      // 畫面刷新:新的當前體重卡變成 82.5(比 78.0 新,measuredAt 預設為
      // 儲存當下的 DateTime.now(),晚於種子的三筆)。
      expect(
        find.descendant(
          of: find.byKey(const Key('bodyWeightStatCard-current')),
          matching: find.text('82.5 kg'),
        ),
        findsOneWidget,
      );

      // 獨立 SELECT 驗證:真的寫進 DB,不是單純的本地畫面狀態。
      final all = await harness.bodyWeightRepo.fetchAll();
      expect(all.length, 4);
      expect(all.any((e) => e.weight == 82.5), isTrue);
    });
  });

  group('編輯', () {
    testWidgets('開表單帶原值,改體重後儲存落地(獨立 SELECT 驗證,id 不變)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);

      await _pump(tester, harness);

      // 圖表/統計卡把列表推出視窗外,tap 前先捲動讓目標按鈕進入可視範圍
      // (同 dashboard_page_test.dart「查看全部」測試的既有慣例)。
      await tester.ensureVisible(find.byKey(const Key('editBodyWeightButton-bw-middle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editBodyWeightButton-bw-middle')));
      await tester.pumpAndSettle();

      // 表單帶原值:middle 是 76.0 → 顯示成 "76"(_stripTrailingZero)。
      final weightField = tester.widget<TextField>(find.byKey(const Key('bodyWeightFormWeightField')));
      expect(weightField.controller?.text, '76');

      await tester.enterText(find.byKey(const Key('bodyWeightFormWeightField')), '77.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bodyWeightFormSaveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bodyWeightFormWeightField')), findsNothing);

      final all = await harness.bodyWeightRepo.fetchAll();
      expect(all.length, 3); // 編輯不新增筆數。
      final updated = all.firstWhere((e) => e.id == 'bw-middle');
      expect(updated.weight, 77.5);
    });
  });

  group('刪除', () {
    testWidgets('取消:對話框關閉,紀錄仍在(DB 未變動)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);
      await _pump(tester, harness);

      await tester.ensureVisible(find.byKey(const Key('deleteBodyWeightButton-bw-middle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteBodyWeightButton-bw-middle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteBodyWeightDialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('deleteBodyWeightCancelButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bodyWeightRow-bw-middle')), findsOneWidget);
      final all = await harness.bodyWeightRepo.fetchAll();
      expect(all.length, 3);
    });

    testWidgets('確認:對話框關閉,紀錄從列表與 DB 移除(獨立 SELECT 驗證)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);
      await _pump(tester, harness);

      await tester.ensureVisible(find.byKey(const Key('deleteBodyWeightButton-bw-middle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteBodyWeightButton-bw-middle')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('deleteBodyWeightConfirmButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bodyWeightRow-bw-middle')), findsNothing);
      final all = await harness.bodyWeightRepo.fetchAll();
      expect(all.length, 2);
      expect(all.any((e) => e.id == 'bw-middle'), isFalse);
    });
  });

  group('失敗路徑', () {
    testWidgets('新增失敗:顯示錯誤 SnackBar,表單未被誤 pop,欄位/按鈕解除 disable', (tester) async {
      final harness = await _setUpHarness(bodyWeightRepoBuilder: _ThrowingCreateBodyWeightRepository.new);
      await _seedThreeEntries(harness);
      await _pump(tester, harness);

      await tester.tap(find.byKey(const Key('addBodyWeightButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bodyWeightFormWeightField')), '82.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bodyWeightFormSaveButton')));
      await tester.pumpAndSettle();

      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);
      // 表單沒有被誤 pop。
      expect(find.byKey(const Key('bodyWeightFormWeightField')), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(const Key('bodyWeightFormWeightField')));
      expect(field.enabled, isTrue);
      final button = tester.widget<FilledButton>(find.byKey(const Key('bodyWeightFormSaveButton')));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('更新失敗:顯示錯誤 SnackBar,表單未被誤 pop', (tester) async {
      final harness = await _setUpHarness(bodyWeightRepoBuilder: _ThrowingUpdateBodyWeightRepository.new);
      await _seedThreeEntries(harness);
      await _pump(tester, harness);

      await tester.ensureVisible(find.byKey(const Key('editBodyWeightButton-bw-middle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editBodyWeightButton-bw-middle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bodyWeightFormWeightField')), '77.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bodyWeightFormSaveButton')));
      await tester.pumpAndSettle();

      expect(find.text('更新失敗，請稍後再試'), findsOneWidget);
      expect(find.byKey(const Key('bodyWeightFormWeightField')), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(const Key('bodyWeightFormWeightField')));
      expect(field.enabled, isTrue);
    });

    testWidgets('刪除失敗:顯示錯誤 SnackBar,紀錄仍在列表(不卡死、可重試)', (tester) async {
      final harness = await _setUpHarness(bodyWeightRepoBuilder: _ThrowingDeleteBodyWeightRepository.new);
      await _seedThreeEntries(harness);
      await _pump(tester, harness);

      await tester.ensureVisible(find.byKey(const Key('deleteBodyWeightButton-bw-middle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteBodyWeightButton-bw-middle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteBodyWeightConfirmButton')));
      await tester.pumpAndSettle();

      expect(find.text('刪除失敗，請稍後再試'), findsOneWidget);
      expect(find.byKey(const Key('bodyWeightRow-bw-middle')), findsOneWidget);
      // 可以立刻再次嘗試:刪除按鈕仍然可點。
      expect(find.byKey(const Key('deleteBodyWeightButton-bw-middle')), findsOneWidget);
    });
  });
}
