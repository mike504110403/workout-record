// PrListPage widget seam:pump 真實頁面(repositories/provider 一律用真的,
// 只換 appDatabaseProvider 為 in-memory DB、sharedPreferencesProvider 為
// mock prefs),斷言畫面呈現的分組/排序與空狀態文案。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide PersonalRecord;
import 'package:workout_record/data/migration/coredata_importer_result.dart';
import 'package:workout_record/data/models/personal_record.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/personal_record_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/preferences/one_rm_formula_preference.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';
import 'package:workout_record/features/stats/pr/pr_list_page.dart';
import 'package:workout_record/features/stats/pr/widgets/pr_summary_card.dart';

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
  Map<String, Object> extraPrefs = const {},
  WeightUnit? weightUnit,
  OneRmFormula? formula,
}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId, ...extraPrefs});
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

Future<void> _pump(WidgetTester tester, _Harness harness, {bool tall = true}) async {
  // 理由同 powerlifting_tab_test.dart:分組多時預設 800x600 視窗裝不下。
  // 懶建置測試(tall: false)要的就是「裝不下」,用預設小視窗。
  if (tall) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: PrListPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _createPR(
  _Harness harness, {
  required String id,
  required String exerciseId,
  required double oneRepMax,
  DateTime? achievedAt,
}) async {
  final now = DateTime.now();
  await harness.personalRecordRepo.create(
    PersonalRecord(
      id: id,
      userId: testUserId,
      exerciseId: exerciseId,
      weight: oneRepMax,
      reps: 1,
      oneRepMax: oneRepMax,
      achievedAt: achievedAt ?? now,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

void main() {
  group('空狀態', () {
    testWidgets('沒有任何 PR 紀錄時顯示空狀態文案', (tester) async {
      final harness = await _setUpHarness();

      await _pump(tester, harness);

      expect(find.byKey(const Key('prListEmptyState')), findsOneWidget);
      expect(find.text('尚無 PR 記錄'), findsOneWidget);
      expect(find.text('完成訓練後這裡會顯示你的個人最佳記錄'), findsOneWidget);
    });
  });

  group('依動作名稱搜尋', () {
    testWidgets('輸入關鍵字只留下名稱相符的動作卡,空白群組一併消失;清除後恢復;無符合顯示空狀態', (tester) async {
      final harness = await _setUpHarness();
      final systemExercises = await harness.exerciseRepo.fetchSystemExercises();
      final squat = systemExercises.firstWhere((e) => e.name == '深蹲');
      final bench = systemExercises.firstWhere((e) => e.name == '槓鈴臥推');
      await _createPR(harness, id: 'pr-sq', exerciseId: squat.id, oneRepMax: 140);
      await _createPR(harness, id: 'pr-bp', exerciseId: bench.id, oneRepMax: 100);

      await _pump(tester, harness);
      expect(find.byKey(Key('prSummaryCard-${squat.id}')), findsOneWidget);
      expect(find.byKey(Key('prSummaryCard-${bench.id}')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('prListSearchField')), '臥推');
      await tester.pumpAndSettle();
      expect(find.byKey(Key('prSummaryCard-${bench.id}')), findsOneWidget);
      expect(find.byKey(Key('prSummaryCard-${squat.id}')), findsNothing);
      // 深蹲所屬的腿部群組標題也跟著消失(沒有空群組)。
      expect(find.byKey(const Key('prGroupSection-腿部')), findsNothing);

      await tester.enterText(find.byKey(const Key('prListSearchField')), '不存在的動作');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('prListNoMatchState')), findsOneWidget);
      expect(find.byKey(Key('prSummaryCard-${bench.id}')), findsNothing);

      await tester.tap(find.byKey(const Key('prListSearchClearButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('prSummaryCard-${squat.id}')), findsOneWidget);
      expect(find.byKey(Key('prSummaryCard-${bench.id}')), findsOneWidget);
      expect(find.byKey(const Key('prListNoMatchState')), findsNothing);
    });

    testWidgets('沒有任何 PR 時不顯示搜尋欄(只有空狀態)', (tester) async {
      final harness = await _setUpHarness();
      await _pump(tester, harness);
      expect(find.byKey(const Key('prListSearchField')), findsNothing);
    });
  });

  // 波 6:重量單位(lb 模式)。變異:PrSummaryCard 漏接 weightUnitProvider、
  // 恆用 kg 必紅。
  group('重量單位(lb 模式)', () {
    testWidgets('PR 卡片 PR 重量/1RM 換算成 lb 顯示,字尾 lb', (tester) async {
      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
      final systemExercises = await harness.exerciseRepo.fetchSystemExercises();
      final squat = systemExercises.firstWhere((e) => e.name == '深蹲');
      await _createPR(harness, id: 'pr-lb', exerciseId: squat.id, oneRepMax: 140);

      await _pump(tester, harness);

      final squatCard = find.byKey(Key('prSummaryCard-${squat.id}'));
      final expected = '${kgToDisplay(140, WeightUnit.lb).toStringAsFixed(1)} lb';
      // PR 重量與 1RM 估算在此 fixture 同值(reps=1),兩處都應是 lb 字串。
      expect(find.descendant(of: squatCard, matching: find.text(expected)), findsNWidgets(2));
      expect(find.descendant(of: squatCard, matching: find.text('140.0 kg')), findsNothing);
    });
  });

  group('1RM 口徑與詳情頁一致', () {
    testWidgets('卡片 1RM 依偏好公式重算,不顯示儲存值;當前 PR 也依重算值挑', (tester) async {
      final harness = await _setUpHarness(formula: OneRmFormula.brzycki);
      final systemExercises = await harness.exerciseRepo.fetchSystemExercises();
      final squat = systemExercises.firstWhere((e) => e.name == '深蹲');
      final now = DateTime.now();
      PersonalRecord pr(String id, double w, int reps, double stored) => PersonalRecord(
        id: id,
        userId: testUserId,
        exerciseId: squat.id,
        weight: w,
        reps: reps,
        oneRepMax: stored,
        achievedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      // 儲存值(Epley):100x5 → 116.7;112x1 → 112。Brzycki 重算:100x5 → 112.5;112x1 → 112。
      // 儲存值最高的是 100x5,重算後最高仍是 100x5(112.5),但卡片 1RM 應是 112.5 不是 116.7。
      await harness.personalRecordRepo.create(pr('a', 100, 5, 116.7));
      await harness.personalRecordRepo.create(pr('b', 112, 1, 112));

      await _pump(tester, harness);

      final card = find.byKey(Key('prSummaryCard-${squat.id}'));
      expect(find.descendant(of: card, matching: find.text('112.5 kg')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('116.7 kg')), findsNothing);
      expect(find.descendant(of: card, matching: find.text('100.0 kg')), findsOneWidget);
    });
  });

  group('肌群分組與排序', () {
    testWidgets('按肌群分組列出動作,卡片顯示 1RM/重量×次數/達成日', (tester) async {
      final harness = await _setUpHarness();
      final systemExercises = await harness.exerciseRepo.fetchSystemExercises();
      final squat = systemExercises.firstWhere((e) => e.name == '深蹲'); // legs
      final benchPress = systemExercises.firstWhere((e) => e.name == '槓鈴臥推'); // chest

      await _createPR(
        harness,
        id: 'pr-squat',
        exerciseId: squat.id,
        oneRepMax: 140,
        achievedAt: DateTime(2026, 3, 1),
      );
      await _createPR(
        harness,
        id: 'pr-bench',
        exerciseId: benchPress.id,
        oneRepMax: 90,
        achievedAt: DateTime(2026, 2, 1),
      );

      await _pump(tester, harness);

      expect(find.byKey(Key('prSummaryCard-${squat.id}')), findsOneWidget);
      expect(find.byKey(Key('prSummaryCard-${benchPress.id}')), findsOneWidget);

      // 依 PersonalRecordRepository.getPRSummary 的排序(肌群 value 字母序:
      // chest < legs),胸(槓鈴臥推)分組應排在腿(深蹲)分組之前。
      final chestSectionY = tester.getTopLeft(find.byKey(const Key('prGroupSection-胸'))).dy;
      final legsSectionY = tester.getTopLeft(find.byKey(const Key('prGroupSection-腿'))).dy;
      expect(chestSectionY, lessThan(legsSectionY));

      // 手算:140.0 kg、1 次、1RM 140.0 kg 顯示在深蹲卡片內。
      final squatCard = find.byKey(Key('prSummaryCard-${squat.id}'));
      expect(find.descendant(of: squatCard, matching: find.text('140.0 kg')), findsWidgets);
      expect(find.descendant(of: squatCard, matching: find.text('1 次')), findsOneWidget);
      expect(find.descendant(of: squatCard, matching: find.text('2026/3/1')), findsOneWidget);
    });

    testWidgets('非首段標題與上一張卡片的視覺間距是 lg(16),不是 28', (tester) async {
      final harness = await _setUpHarness();
      final systemExercises = await harness.exerciseRepo.fetchSystemExercises();
      final squat = systemExercises.firstWhere((e) => e.name == '深蹲'); // legs
      final benchPress = systemExercises.firstWhere((e) => e.name == '槓鈴臥推'); // chest
      await _createPR(harness, id: 'pr-squat', exerciseId: squat.id, oneRepMax: 140, achievedAt: DateTime(2026, 3, 1));
      await _createPR(harness, id: 'pr-bench', exerciseId: benchPress.id, oneRepMax: 90, achievedAt: DateTime(2026, 2, 1));

      await _pump(tester, harness);

      // 胸(首段)的卡片在前、腿標題在後。Card 的 rect 含自帶 bottom margin 12
      // (視覺底緣在 rect 之上 12),所以「視覺間距」＝ rect 差 + 12。
      final chestCardBottom = tester.getBottomLeft(find.byKey(Key('prSummaryCard-${benchPress.id}'))).dy;
      final legsTitleTop = tester
          .getTopLeft(find.descendant(of: find.byKey(const Key('prGroupSection-腿')), matching: find.text('腿')))
          .dy;
      expect(legsTitleTop - chestCardBottom + 12, closeTo(16.0, 0.01));
    });

    testWidgets('同一動作多筆歷史紀錄時,卡片顯示的是 1RM 最高的那筆(currentPR),不是最新一筆', (tester) async {
      final harness = await _setUpHarness();
      final systemExercises = await harness.exerciseRepo.fetchSystemExercises();
      final squat = systemExercises.firstWhere((e) => e.name == '深蹲');

      await _createPR(
        harness,
        id: 'pr-old',
        exerciseId: squat.id,
        oneRepMax: 140,
        achievedAt: DateTime(2026, 1, 1),
      );
      await _createPR(
        harness,
        id: 'pr-new',
        exerciseId: squat.id,
        oneRepMax: 100,
        achievedAt: DateTime(2026, 3, 1),
      );

      await _pump(tester, harness);

      final squatCard = find.byKey(Key('prSummaryCard-${squat.id}'));
      expect(find.descendant(of: squatCard, matching: find.text('140.0 kg')), findsWidgets);
      expect(find.descendant(of: squatCard, matching: find.text('100.0 kg')), findsNothing);
      // 兩筆歷史紀錄都存在,卡片下方應顯示「2 次記錄」。
      expect(find.descendant(of: squatCard, matching: find.text('2 次記錄')), findsOneWidget);
    });
  });

  group('userId 解析:血緣 fallback', () {
    testWidgets('session 的 appleUserId 查無此人時,退回 CoreData 匯入血緣 id', (tester) async {
      final harness = await _setUpHarness(
        extraPrefs: {
          kAppleUserIdKey: 'stranger-id-not-in-users-table',
          kCoreDataImportedUserIdKey: testUserId,
        },
      );
      final systemExercises = await harness.exerciseRepo.fetchSystemExercises();
      final squat = systemExercises.firstWhere((e) => e.name == '深蹲');
      await _createPR(harness, id: 'pr-squat', exerciseId: squat.id, oneRepMax: 100);

      await _pump(tester, harness);

      expect(find.byKey(Key('prSummaryCard-${squat.id}')), findsOneWidget);
    });
  });

  group('長清單懶建置', () {
    testWidgets('40 個動作的 PR:只建可見範圍的卡片,捲到底才出現最後一張', (tester) async {
      final harness = await _setUpHarness();
      final systemExercises = await harness.exerciseRepo.fetchSystemExercises();
      final targets = systemExercises.take(40).toList();
      expect(targets.length, 40, reason: '種子動作不足 40 個,測試前提不成立');
      for (final (i, e) in targets.indexed) {
        await _createPR(harness, id: 'pr-$i', exerciseId: e.id, oneRepMax: 100.0 + i);
      }

      await _pump(tester, harness, tall: false);

      final built = find.byType(PrSummaryCard).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40), reason: '40 張卡不該全部建置(懶建置)');

      final firstBuiltId = tester.widgetList<PrSummaryCard>(find.byType(PrSummaryCard)).first.summary.exerciseId;

      // 一路捲到底:捲動位置到達 maxScrollExtent(清單可捲到底),最初那張卡已被
      // 回收(只建可見範圍),建置數仍小於總數。
      final scrollable = find.byType(Scrollable).last;
      await tester.fling(scrollable, const Offset(0, -30000), 8000);
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, position.maxScrollExtent);
      expect(find.byKey(Key('prSummaryCard-$firstBuiltId')), findsNothing, reason: '捲到底後最上面的卡應已回收');
      expect(find.byType(PrSummaryCard).evaluate().length, lessThan(40));
    });
  });
}
