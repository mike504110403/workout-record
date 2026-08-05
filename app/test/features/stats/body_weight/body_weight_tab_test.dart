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
//   - x 軸用陣列索引取代真實時間戳必紅(review 打回 minor 1):「不等距
//     種子」測試比較兩段 x 差值是否對應真實的 measuredAt 毫秒差,若實作
//     退回索引(0.0, 1.0, 2.0),兩段差值會相等,斷言失敗。
//   - 日期/備註路徑六個變異必紅(review 打回 major 1,見「編輯」「新增」
//     兩個 group 底下標註「review 打回 major 1」的測試):
//     1. updateEntry 改回 `original.copyWith(...)`(note 傳 null 語意是
//        「不改」,清空備註測試會失敗)。
//     2. 表單忽略選定日期(儲存時沒把 `_selectedDate` 傳給
//        controller)——「改日期後儲存」「帶自訂日期儲存」兩個測試會失敗。
//     3. addEntry 的 note 寫死 null——「帶自訂日期與備註儲存」測試的
//        note 斷言會失敗。
//     4. 儲存時另外算一個 `DateTime.now()` 取代 `_selectedDate`——同 2,
//        「改日期後儲存」「帶自訂日期儲存」會失敗。
//     5. initState 沒有把 `original.note` 帶進表單——「開表單帶原備註與
//        原時間值」測試的備註斷言會失敗。
//     6. initState 沒有把 `original.measuredAt` 帶進表單——同 5,日期
//        按鈕文字斷言會失敗。
//   - 載入失敗/重試分支零覆蓋必紅(review 打回 major 2):「載入失敗」
//     group 兩個測試,分別守住「查詢拋錯要顯示 error 分支」「按重試按鈕
//     要能從暫時性失敗恢復」,若 retry 按鈕的 onPressed 是 no-op 或壓根
//     沒有 invalidate provider,第二個測試會卡在 error 文案不消失。
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
import 'package:workout_record/features/stats/body_weight/body_weight_format.dart';
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

/// 載入失敗路徑用:`_load()` 第一個 await 的 repository 呼叫就拋錯,讓
/// `bodyWeightTabControllerProvider` 落入 `AsyncError`(仿
/// dashboard_page_test.dart 的 `_ThrowingOnLoadBodyWeightRepository`)。
class _ThrowingOnLoadBodyWeightRepository extends BodyWeightRepository {
  _ThrowingOnLoadBodyWeightRepository(super.db);

  @override
  Future<List<BodyWeight>> fetchAll() async {
    throw Exception('模擬載入體重紀錄失敗(失敗路徑測試用)');
  }
}

/// 重試恢復路徑用:只有第一次呼叫 `fetchAll()` 拋錯,之後恢復正常——模擬
/// 「暫時性失敗,重試就好了」的情境(仿 dashboard_page_test.dart 的
/// `_FlakyBodyWeightRepository`)。
class _FlakyBodyWeightRepository extends BodyWeightRepository {
  _FlakyBodyWeightRepository(super.db);

  var _callCount = 0;

  @override
  Future<List<BodyWeight>> fetchAll() async {
    _callCount += 1;
    if (_callCount == 1) {
      throw Exception('模擬第一次載入失敗,重試後應恢復(失敗路徑測試用)');
    }
    return super.fetchAll();
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

/// [disableAutoRetry] 為 true 時關掉 riverpod 內建的自動重試(理由同
/// dashboard_page_test.dart 的同名參數:build() 拋出 Exception 時框架本身
/// 就會自動重試,不關掉的話 flaky repo 會被框架搶在斷言/按重試按鈕之前就
/// 自動重試成功,測試斷言不到穩定的 error 畫面)。
Future<_Harness> _setUpHarness({
  BodyWeightRepository Function(AppDatabase db)? bodyWeightRepoBuilder,
  bool disableAutoRetry = false,
}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);

  final container = ProviderContainer(
    retry: disableAutoRetry ? (retryCount, error) => null : null,
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

/// 驅動 Flutter 內建的 `showDatePicker`/`showTimePicker`(表單的
/// `_pickDate`,input entry mode,見 body_weight_form_sheet.dart 開頭
/// 註解)選出一個自訂日期時間,證明表單真的把使用者挑選的日期時間帶進
/// `_selectedDate`、而不是儲存當下另外算一個 `DateTime.now()`。
///
/// 呼叫前提:`bodyWeightFormDateButton` 已經在畫面上(表單已開啟)。
/// [mmddyyyy] 對照 input 模式的 `mm/dd/yyyy` 格式;[hour12] 是 1-12 的
/// 12 小時制文字;[isAm] 決定 AM/PM。
Future<void> _pickCustomDateTime(
  WidgetTester tester, {
  required String mmddyyyy,
  required String hour12,
  required String minute,
  required bool isAm,
}) async {
  await tester.tap(find.byKey(const Key('bodyWeightFormDateButton')));
  await tester.pumpAndSettle();

  // 日期對話框:input entry mode 只有一個 TextFormField。
  await tester.enterText(find.byType(TextFormField), mmddyyyy);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  // 時間對話框:input entry mode 有兩個 TextFormField(依序是 Hour、
  // Minute),外加 AM/PM 切換鈕。
  final timeFields = find.byType(TextFormField);
  await tester.enterText(timeFields.at(0), hour12);
  await tester.pumpAndSettle();
  await tester.enterText(timeFields.at(1), minute);
  await tester.pumpAndSettle();
  await tester.tap(find.text(isAm ? 'AM' : 'PM'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
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

    testWidgets('不等距種子:圖表 x 值反映真實時間間隔,不是陣列索引等距(review 打回 minor 1)', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      final t0 = now.subtract(const Duration(days: 20));
      final t1 = t0.add(const Duration(days: 1)); // t0→t1 間隔 1 天
      final t2 = t1.add(const Duration(days: 18)); // t1→t2 間隔 18 天
      await harness.bodyWeightRepo.create(_entry(id: 'gap-0', weight: 70.0, measuredAt: t0));
      await harness.bodyWeightRepo.create(_entry(id: 'gap-1', weight: 71.0, measuredAt: t1));
      await harness.bodyWeightRepo.create(_entry(id: 'gap-2', weight: 72.0, measuredAt: t2));

      await _pump(tester, harness);

      final chart = _findLineChart(tester);
      final spots = chart.data.lineBarsData.single.spots;
      expect(spots.length, 3);

      final gap01 = spots[1].x - spots[0].x;
      final gap12 = spots[2].x - spots[1].x;
      // gap12(18 天)應遠大於 gap01(1 天)——若實作仍用陣列索引當 x
      // (0.0, 1.0, 2.0),兩段間隔會相等,這個比較會失敗。
      expect(gap12, greaterThan(gap01 * 5));
      // 具體數值直接對照 measuredAt 差的毫秒數,證明 x 真的是時間戳,不是
      // 其他單調遞增但跟真實時間無關的數列。
      expect(gap01, t1.difference(t0).inMilliseconds.toDouble());
      expect(gap12, t2.difference(t1).inMilliseconds.toDouble());
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

    // review 打回 minor 2:iOS AddBodyWeightSheet 有「取消」工具列按鈕。
    testWidgets('點取消:表單關閉,不寫入資料', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);
      await _pump(tester, harness);

      await tester.tap(find.byKey(const Key('addBodyWeightButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bodyWeightFormWeightField')), '99.9');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bodyWeightFormCancelButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bodyWeightFormWeightField')), findsNothing);
      final all = await harness.bodyWeightRepo.fetchAll();
      expect(all.length, 3); // 沒有新增第 4 筆。
      expect(all.any((e) => e.weight == 99.9), isFalse);
    });

    // review 打回 major 1(「新增帶自訂日期與備註落地」):守住「addEntry
    // note 寫死 null」「表單忽略選定日期/寫死 DateTime.now()」這兩類變異
    // ——若任一個存活,這裡的獨立 SELECT 斷言會對不上自訂值。
    testWidgets('帶自訂日期與備註儲存,兩者都真的落地(獨立 SELECT 驗證)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);
      await _pump(tester, harness);

      await tester.tap(find.byKey(const Key('addBodyWeightButton')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('bodyWeightFormWeightField')), '65.0');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bodyWeightFormNoteField')), '早上空腹量測');
      await tester.pumpAndSettle();

      await _pickCustomDateTime(
        tester,
        mmddyyyy: '01/10/2023',
        hour12: '11',
        minute: '30',
        isAm: false, // 11:30 PM
      );

      await tester.tap(find.byKey(const Key('bodyWeightFormSaveButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bodyWeightFormWeightField')), findsNothing);

      final all = await harness.bodyWeightRepo.fetchAll();
      final created = all.firstWhere((e) => e.weight == 65.0);
      expect(created.note, '早上空腹量測');
      expect(created.measuredAt, DateTime(2023, 1, 10, 23, 30));
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

    // review 打回 major 1:守住「編輯不帶原備註存活」「編輯不帶原時間存活」
    // 這兩類變異——若 initState 沒有把 `original.note`/`original.measuredAt`
    // 帶進表單初始值,這裡的斷言會落空(備註欄變空字串、日期按鈕顯示現在
    // 時間而不是原本的紀錄時間)。
    testWidgets('開表單帶原備註與原時間值(不是空白/現在時間)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);
      final notedAt = DateTime.now().subtract(const Duration(days: 3, hours: 2));
      await harness.bodyWeightRepo.create(
        _entry(id: 'bw-noted', weight: 73.0, measuredAt: notedAt, note: '早上空腹量測'),
      );
      await _pump(tester, harness);

      await tester.ensureVisible(find.byKey(const Key('editBodyWeightButton-bw-noted')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editBodyWeightButton-bw-noted')));
      await tester.pumpAndSettle();

      final noteField = tester.widget<TextField>(find.byKey(const Key('bodyWeightFormNoteField')));
      expect(noteField.controller?.text, '早上空腹量測');

      // `OutlinedButton.icon` 的 child 是內部組合元件（icon+label），不是
      // 單純的 Text，直接找按鈕子樹裡有沒有原始時間的文字最直接。
      expect(
        find.descendant(
          of: find.byKey(const Key('bodyWeightFormDateButton')),
          matching: find.text(formatBodyWeightDateTime(notedAt)),
        ),
        findsOneWidget,
      );
    });

    // review 打回 major 1:守住「updateEntry 改回 copyWith 存活」——
    // `BodyWeight.copyWith` 對 note 是 `note ?? this.note` 語意,傳 null
    // 代表「不改」,沒辦法把備註改成空字串/清空;若 updateEntry 誤用
    // copyWith,清空備註存檔後 DB 仍會保留舊備註,這裡的獨立 SELECT 斷言
    // 會失敗。
    testWidgets('清空備註後儲存,DB note 變成 null(獨立 SELECT 驗證)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);
      await harness.bodyWeightRepo.create(
        _entry(id: 'bw-noted', weight: 73.0, measuredAt: DateTime.now().subtract(const Duration(days: 3)), note: '早上空腹量測'),
      );
      await _pump(tester, harness);

      await tester.ensureVisible(find.byKey(const Key('editBodyWeightButton-bw-noted')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editBodyWeightButton-bw-noted')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('bodyWeightFormNoteField')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bodyWeightFormSaveButton')));
      await tester.pumpAndSettle();

      final all = await harness.bodyWeightRepo.fetchAll();
      final updated = all.firstWhere((e) => e.id == 'bw-noted');
      expect(updated.note, isNull);
    });

    // review 打回 major 1(「改日期後 measuredAt 跟著變」):守住「表單忽略
    // 選定日期存活」「儲存時寫死 DateTime.now() 存活」——若 `_save()` 沒有
    // 真的把使用者透過 `_pickDate` 選定的 `_selectedDate` 傳給
    // `updateEntry`,或是傳了但被 controller 端某處覆寫成當下的
    // `DateTime.now()`,這裡的獨立 SELECT 斷言(比對到分鐘的精確值)會
    // 對不上。
    testWidgets('改日期後儲存,measuredAt 跟著變(獨立 SELECT 驗證,體重/備註不受影響)', (tester) async {
      final harness = await _setUpHarness();
      await _seedThreeEntries(harness);
      await harness.bodyWeightRepo.create(
        _entry(
          id: 'bw-noted',
          weight: 73.0,
          measuredAt: DateTime.now().subtract(const Duration(days: 3)),
          note: '早上空腹量測',
        ),
      );
      await _pump(tester, harness);

      await tester.ensureVisible(find.byKey(const Key('editBodyWeightButton-bw-noted')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editBodyWeightButton-bw-noted')));
      await tester.pumpAndSettle();

      await _pickCustomDateTime(
        tester,
        mmddyyyy: '03/15/2024',
        hour12: '09',
        minute: '05',
        isAm: true,
      );

      await tester.tap(find.byKey(const Key('bodyWeightFormSaveButton')));
      await tester.pumpAndSettle();

      final all = await harness.bodyWeightRepo.fetchAll();
      final updated = all.firstWhere((e) => e.id == 'bw-noted');
      expect(updated.measuredAt, DateTime(2024, 3, 15, 9, 5));
      // 只改了日期,體重/備註應維持原值(順便驗證「完整重建物件」沒有
      // 誤把其他欄位一起洗掉)。
      expect(updated.weight, 73.0);
      expect(updated.note, '早上空腹量測');
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

  // review 打回 major 2:照 dashboard_page_test.dart:771-804 前例補上——
  // 初始載入(`_load()`)失敗要有 error 分支文案+重試按鈕,按下重試後
  // 暫時性失敗要能自行恢復,不能整頁卡死或永遠停在 error 畫面。
  group('載入失敗', () {
    testWidgets('查詢拋錯時顯示 error 分支文案與重試按鈕', (tester) async {
      final harness = await _setUpHarness(
        bodyWeightRepoBuilder: _ThrowingOnLoadBodyWeightRepository.new,
        disableAutoRetry: true,
      );

      await _pump(tester, harness);

      expect(find.textContaining('載入失敗'), findsOneWidget);
      expect(find.byKey(const Key('bodyWeightErrorRetryButton')), findsOneWidget);
      // 不會被誤判成「查無資料」的空狀態。
      expect(find.byKey(const Key('emptyBodyWeightView')), findsNothing);
    });

    testWidgets('點重試按鈕後,暫時性失敗恢復,畫面回到正常呈現(不卡死在 error 分支)', (tester) async {
      final harness = await _setUpHarness(
        bodyWeightRepoBuilder: _FlakyBodyWeightRepository.new,
        disableAutoRetry: true,
      );
      await _seedThreeEntries(harness);

      await _pump(tester, harness);

      // 第一次載入失敗,停在 error 分支。
      expect(find.textContaining('載入失敗'), findsOneWidget);
      final retryButton = find.byKey(const Key('bodyWeightErrorRetryButton'));
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      // 重試後 _FlakyBodyWeightRepository 第二次呼叫不再拋錯,畫面恢復成
      // 正常的 data 分支,error 文案與重試按鈕都消失,種子資料(非空狀態)
      // 正常顯示。
      expect(find.textContaining('載入失敗'), findsNothing);
      expect(find.byKey(const Key('bodyWeightErrorRetryButton')), findsNothing);
      expect(find.byKey(const Key('bodyWeightStatsGrid')), findsOneWidget);
      expect(find.byKey(const Key('emptyBodyWeightView')), findsNothing);
    });
  });
}
