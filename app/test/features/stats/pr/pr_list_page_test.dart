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
import 'package:workout_record/features/stats/pr/pr_list_page.dart';

import '../../../data/test_helpers.dart';

class _Harness {
  _Harness(this.db, this.container)
      : exerciseRepo = ExerciseRepository(db),
        personalRecordRepo = PersonalRecordRepository(db, ExerciseRepository(db));

  final AppDatabase db;
  final ProviderContainer container;
  final ExerciseRepository exerciseRepo;
  final PersonalRecordRepository personalRecordRepo;
}

Future<_Harness> _setUpHarness({Map<String, Object> extraPrefs = const {}}) async {
  SharedPreferences.setMockInitialValues({
    kAppleUserIdKey: testUserId,
    ...extraPrefs,
  });
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

Future<void> _pump(WidgetTester tester, _Harness harness) async {
  // 理由同 powerlifting_tab_test.dart:分組多時預設 800x600 視窗裝不下。
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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

    testWidgets('同一動作多筆歷史紀錄時,卡片顯示的是 1RM 最高的那筆(currentPR),不是最新一筆', (tester) async {
      final harness = await _setUpHarness();
      final systemExercises = await harness.exerciseRepo.fetchSystemExercises();
      final squat = systemExercises.firstWhere((e) => e.name == '深蹲');

      await _createPR(harness, id: 'pr-old', exerciseId: squat.id, oneRepMax: 140, achievedAt: DateTime(2026, 1, 1));
      await _createPR(harness, id: 'pr-new', exerciseId: squat.id, oneRepMax: 100, achievedAt: DateTime(2026, 3, 1));

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
}
