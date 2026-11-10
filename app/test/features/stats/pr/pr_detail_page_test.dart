// PrDetailPage widget seam:pump 真實頁面(repositories/provider 用真的,只換
// appDatabaseProvider 為 in-memory DB、sharedPreferencesProvider 為 mock prefs),
// 斷言當前 PR 卡、歷史排序、單位/公式偏好、單筆與空狀態,以及從 PR 列表點進詳情。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide PersonalRecord;
import 'package:workout_record/data/models/personal_record.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/personal_record_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/preferences/one_rm_formula_preference.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';
import 'package:workout_record/features/stats/pr/pr_detail_page.dart';
import 'package:workout_record/features/stats/pr/pr_list_page.dart';
import 'package:workout_record/features/stats/pr/widgets/pr_progress_chart.dart';
import 'package:workout_record/features/stats/pr/pr_detail_calculations.dart';

import '../../../data/test_helpers.dart';

class _Harness {
  _Harness(this.db, this.container)
      : exerciseRepo = DriftExerciseRepository(db),
        personalRecordRepo = DriftPersonalRecordRepository(db, DriftExerciseRepository(db));

  final AppDatabase db;
  final ProviderContainer container;
  final ExerciseRepository exerciseRepo;
  final PersonalRecordRepository personalRecordRepo;
}

Future<_Harness> _setUpHarness({
  WeightUnit? weightUnit,
  OneRmFormula? formula,
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
      if (weightUnit != null) weightUnitProvider.overrideWithValue(weightUnit),
      if (formula != null) oneRmFormulaProvider.overrideWithValue(formula),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(db, container);
}

Future<void> _pumpApp(WidgetTester tester, _Harness harness, Widget home) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _createPR(
  _Harness harness, {
  required String id,
  required String exerciseId,
  required double weight,
  int reps = 1,
  required double oneRepMax,
  required DateTime achievedAt,
}) async {
  final now = DateTime.now();
  await harness.personalRecordRepo.create(
    PersonalRecord(
      id: id,
      userId: testUserId,
      exerciseId: exerciseId,
      weight: weight,
      reps: reps,
      oneRepMax: oneRepMax,
      achievedAt: achievedAt,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Future<String> _squatId(_Harness harness) async {
  final exercises = await harness.exerciseRepo.fetchSystemExercises();
  return exercises.firstWhere((e) => e.name == '深蹲').id;
}

Finder _historyRows() => find.byWidgetPredicate((w) => w.key.toString().contains('prDetailHistoryRow-'));

void main() {
  testWidgets('從 PR 列表點某動作卡片進入該動作的詳情頁', (tester) async {
    final harness = await _setUpHarness();
    final squatId = await _squatId(harness);
    await _createPR(harness,
        id: 'pr-1', exerciseId: squatId, weight: 140, oneRepMax: 140, achievedAt: DateTime(2026, 3, 1));

    await _pumpApp(tester, harness, const PrListPage());
    expect(find.byType(PrDetailPage), findsNothing);

    await tester.tap(find.byKey(Key('prSummaryCard-$squatId')));
    await tester.pumpAndSettle();

    expect(find.byType(PrDetailPage), findsOneWidget);
    // AppBar 標題是動作名稱。
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('深蹲')), findsOneWidget);
    expect(find.byKey(const Key('prDetailCurrentCard')), findsOneWidget);
  });

  testWidgets('當前 PR 卡是 1RM 最高那筆(不是最新一筆),顯示重量/次數/1RM/日期', (tester) async {
    final harness = await _setUpHarness();
    final squatId = await _squatId(harness);
    await _createPR(harness,
        id: 'pr-best', exerciseId: squatId, weight: 140, oneRepMax: 140, achievedAt: DateTime(2026, 1, 5));
    await _createPR(harness,
        id: 'pr-latest', exerciseId: squatId, weight: 100, oneRepMax: 100, achievedAt: DateTime(2026, 3, 1));

    await _pumpApp(tester, harness, PrDetailPage(exerciseId: squatId, exerciseName: '深蹲'));

    expect(tester.widget<Text>(find.byKey(const Key('prDetailCurrentWeight'))).data, '140.0');
    expect(tester.widget<Text>(find.byKey(const Key('prDetailCurrentReps'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const Key('prDetailCurrentOneRm'))).data, '140.0');
    expect(tester.widget<Text>(find.byKey(const Key('prDetailCurrentDate'))).data, '2026/1/5');
    // 歷史列表中只有最佳那筆有「當前 PR」標記(卡片標題另有一個同文字)。
    expect(
      find.descendant(of: find.byKey(const Key('prDetailHistoryRow-pr-best')), matching: find.text('當前 PR')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const Key('prDetailHistoryRow-pr-latest')), matching: find.text('當前 PR')),
      findsNothing,
    );
  });

  testWidgets('歷史列表依達成日新到舊排序(與寫入順序無關)', (tester) async {
    final harness = await _setUpHarness();
    final squatId = await _squatId(harness);
    await _createPR(harness,
        id: 'pr-mid', exerciseId: squatId, weight: 110, oneRepMax: 110, achievedAt: DateTime(2026, 2, 1));
    await _createPR(harness,
        id: 'pr-old', exerciseId: squatId, weight: 100, oneRepMax: 100, achievedAt: DateTime(2026, 1, 1));
    await _createPR(harness,
        id: 'pr-new', exerciseId: squatId, weight: 120, oneRepMax: 120, achievedAt: DateTime(2026, 3, 1));

    await _pumpApp(tester, harness, PrDetailPage(exerciseId: squatId, exerciseName: '深蹲'));

    final rows = _historyRows();
    expect(rows, findsNWidgets(3));
    final ys = [
      for (final id in ['pr-new', 'pr-mid', 'pr-old'])
        tester.getTopLeft(find.byKey(Key('prDetailHistoryRow-$id'))).dy,
    ];
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));
  });

  testWidgets('不同動作的 PR 不會混進詳情頁', (tester) async {
    final harness = await _setUpHarness();
    final exercises = await harness.exerciseRepo.fetchSystemExercises();
    final squat = exercises.firstWhere((e) => e.name == '深蹲');
    final bench = exercises.firstWhere((e) => e.name == '槓鈴臥推');
    await _createPR(harness,
        id: 'pr-squat', exerciseId: squat.id, weight: 140, oneRepMax: 140, achievedAt: DateTime(2026, 3, 1));
    await _createPR(harness,
        id: 'pr-bench', exerciseId: bench.id, weight: 90, oneRepMax: 90, achievedAt: DateTime(2026, 3, 2));

    await _pumpApp(tester, harness, PrDetailPage(exerciseId: squat.id, exerciseName: '深蹲'));

    expect(find.byKey(const Key('prDetailHistoryRow-pr-squat')), findsOneWidget);
    expect(find.byKey(const Key('prDetailHistoryRow-pr-bench')), findsNothing);
  });

  testWidgets('lb 模式:當前 PR 卡、歷史列、進步文字皆換算成 lb', (tester) async {
    final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
    final squatId = await _squatId(harness);
    await _createPR(harness,
        id: 'pr-a', exerciseId: squatId, weight: 100, oneRepMax: 100, achievedAt: DateTime(2026, 1, 1));
    await _createPR(harness,
        id: 'pr-b', exerciseId: squatId, weight: 140, oneRepMax: 140, achievedAt: DateTime(2026, 2, 1));

    await _pumpApp(tester, harness, PrDetailPage(exerciseId: squatId, exerciseName: '深蹲'));

    String lb(double kg) => kgToDisplay(kg, WeightUnit.lb).toStringAsFixed(1);
    expect(tester.widget<Text>(find.byKey(const Key('prDetailCurrentWeight'))).data, lb(140));
    expect(tester.widget<Text>(find.byKey(const Key('prDetailCurrentOneRm'))).data, lb(140));
    // 歷史列:140 kg -> 308.6 lb、100 kg -> 220.5 lb,字尾 lb,畫面不應出現 kg 字串。
    final rowB = find.byKey(const Key('prDetailHistoryRow-pr-b'));
    expect(find.descendant(of: rowB, matching: find.text('${lb(140)} lb')), findsNWidgets(2));
    final rowA = find.byKey(const Key('prDetailHistoryRow-pr-a'));
    expect(find.descendant(of: rowA, matching: find.text('${lb(100)} lb')), findsNWidgets(2));
    expect(find.textContaining(' kg'), findsNothing);
    // 總進步 = 40 kg -> 88.2 lb,+40.0%。
    expect(
      tester.widget<Text>(find.byKey(const Key('prDetailProgressText'))).data,
      '+${lb(40)} lb (+40.0%)',
    );
  });

  testWidgets('kg 模式進步文字:+40.0 kg (+40.0%)', (tester) async {
    final harness = await _setUpHarness();
    final squatId = await _squatId(harness);
    await _createPR(harness,
        id: 'pr-a', exerciseId: squatId, weight: 100, oneRepMax: 100, achievedAt: DateTime(2026, 1, 1));
    await _createPR(harness,
        id: 'pr-b', exerciseId: squatId, weight: 140, oneRepMax: 140, achievedAt: DateTime(2026, 2, 1));

    await _pumpApp(tester, harness, PrDetailPage(exerciseId: squatId, exerciseName: '深蹲'));

    expect(tester.widget<Text>(find.byKey(const Key('prDetailProgressText'))).data, '+40.0 kg (+40.0%)');
    expect(find.byKey(const Key('prProgressChart')), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
  });

  // 變異:頁面直接顯示儲存的 oneRepMax(忽略偏好公式)必紅。
  // 100 kg x 10:儲存值故意寫 1,Epley 重算 133.3。
  testWidgets('1RM 依 oneRmFormulaProvider 重算,不顯示儲存值', (tester) async {
    final harness = await _setUpHarness(formula: OneRmFormula.epley);
    final squatId = await _squatId(harness);
    await _createPR(harness,
        id: 'pr-a', exerciseId: squatId, weight: 100, reps: 10, oneRepMax: 1, achievedAt: DateTime(2026, 1, 1));

    await _pumpApp(tester, harness, PrDetailPage(exerciseId: squatId, exerciseName: '深蹲'));

    expect(tester.widget<Text>(find.byKey(const Key('prDetailCurrentOneRm'))).data, '133.3');
  });

  testWidgets('切換 Lander 公式時 1RM 數字不同於 Epley', (tester) async {
    final harness = await _setUpHarness(formula: OneRmFormula.lander);
    final squatId = await _squatId(harness);
    await _createPR(harness,
        id: 'pr-a', exerciseId: squatId, weight: 100, reps: 10, oneRepMax: 1, achievedAt: DateTime(2026, 1, 1));

    await _pumpApp(tester, harness, PrDetailPage(exerciseId: squatId, exerciseName: '深蹲'));

    // 100 * 100 / (101.3 - 26.7123) = 134.07...
    expect(tester.widget<Text>(find.byKey(const Key('prDetailCurrentOneRm'))).data, '134.1');
  });

  testWidgets('只有一筆紀錄:不崩潰、顯示卡片與一列歷史、不顯示趨勢圖(對照 iOS >1 筆才顯示)', (tester) async {
    final harness = await _setUpHarness();
    final squatId = await _squatId(harness);
    await _createPR(harness,
        id: 'pr-only', exerciseId: squatId, weight: 100, oneRepMax: 100, achievedAt: DateTime(2026, 1, 1));

    await _pumpApp(tester, harness, PrDetailPage(exerciseId: squatId, exerciseName: '深蹲'));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('prDetailCurrentCard')), findsOneWidget);
    expect(_historyRows(), findsOneWidget);
    expect(find.byKey(const Key('prProgressChart')), findsNothing);
    expect(find.byKey(const Key('prDetailProgressText')), findsNothing);
  });

  testWidgets('趨勢圖元件本身單點資料也不崩(minX == maxX 的防護)', (tester) async {
    final harness = await _setUpHarness();
    final now = DateTime(2026, 1, 1);
    final entry = PrDetailEntry(
      record: PersonalRecord(
        id: 'p',
        userId: testUserId,
        exerciseId: 'e',
        weight: 100,
        reps: 1,
        oneRepMax: 100,
        achievedAt: now,
        createdAt: now,
        updatedAt: now,
      ),
      oneRepMax: 100,
    );

    await _pumpApp(tester, harness, Scaffold(body: PrProgressChart(entriesAsc: [entry])));

    expect(tester.takeException(), isNull);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.spots, hasLength(1));
    expect(chart.data.maxX, greaterThan(chart.data.minX));
  });

  testWidgets('趨勢圖資料點:時間由舊到新、y 為 1RM', (tester) async {
    final harness = await _setUpHarness();
    final squatId = await _squatId(harness);
    await _createPR(harness,
        id: 'pr-new', exerciseId: squatId, weight: 120, oneRepMax: 120, achievedAt: DateTime(2026, 3, 1));
    await _createPR(harness,
        id: 'pr-old', exerciseId: squatId, weight: 100, oneRepMax: 100, achievedAt: DateTime(2026, 1, 1));

    await _pumpApp(tester, harness, PrDetailPage(exerciseId: squatId, exerciseName: '深蹲'));

    final spots = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData.single.spots;
    expect(spots.map((s) => s.y).toList(), [100, 120]);
    expect(spots.first.x, lessThan(spots.last.x));
  });

  testWidgets('該動作沒有任何 PR:顯示空狀態,不顯示卡片/圖表/歷史', (tester) async {
    final harness = await _setUpHarness();
    final squatId = await _squatId(harness);

    await _pumpApp(tester, harness, PrDetailPage(exerciseId: squatId, exerciseName: '深蹲'));

    expect(find.byKey(const Key('prDetailEmptyState')), findsOneWidget);
    expect(find.text('尚無 PR 記錄'), findsOneWidget);
    expect(find.byKey(const Key('prDetailCurrentCard')), findsNothing);
    expect(find.byKey(const Key('prProgressChart')), findsNothing);
    expect(_historyRows(), findsNothing);
  });
}
