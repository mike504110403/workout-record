// PowerliftingTab widget seam:pump 真實頁面(repositories/provider 一律用
// 真的,只換 appDatabaseProvider 為 in-memory DB、sharedPreferencesProvider
// 為 mock prefs),斷言畫面呈現的數字/文案。
//
// 變異清單(見 brief seam 要求,逐規則列,各自要有一顆「變異必紅」的斷言):
// - 最佳成績取錯(非最高 1RM 而誤用最新一筆)→「切換動作改變清單與圖」+
//   「三項最佳成績卡」兩組測試共同把關。
// - 三項總和漏一項 → 見 powerlifting_calculations_test.dart(純函式層,
//   本檔另外用「三項皆有紀錄」情境做整合層交叉驗證)。
// - 系統推估匹配錯動作 → 「系統推估只顯示動作名稱匹配的項目」測試。
// - 趨勢圖排序反轉 → 見 powerlifting_calculations_test.dart(chartRecordsForLift
//   純函式層是這條規則唯一能穩定斷言的層級,fl_chart 內部畫線順序無法從
//   widget tree 讀出座標點順序)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide PowerLiftRecord, PersonalRecord;
import 'package:workout_record/data/migration/coredata_importer_result.dart';
import 'package:workout_record/data/models/personal_record.dart';
import 'package:workout_record/data/models/power_lift_record.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/personal_record_repository.dart';
import 'package:workout_record/data/repositories/power_lift_record_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/stats/powerlifting/powerlifting_tab.dart';

import '../../../data/test_helpers.dart';

/// M1 失敗路徑測試專用:模擬 `PowerLiftRecordRepository.create` 寫入失敗。
class _ThrowingOnCreateRepository extends PowerLiftRecordRepository {
  _ThrowingOnCreateRepository(super.db);

  @override
  Future<PowerLiftRecord> create(PowerLiftRecord record) async {
    throw Exception('模擬三項紀錄寫入失敗(失敗路徑測試用)');
  }
}

/// M2 失敗路徑測試專用:模擬 `PowerLiftRecordRepository.delete` 失敗。
class _ThrowingOnDeleteRepository extends PowerLiftRecordRepository {
  _ThrowingOnDeleteRepository(super.db);

  @override
  Future<void> delete(String id) async {
    throw Exception('模擬三項紀錄刪除失敗(失敗路徑測試用)');
  }
}

class _Harness {
  _Harness(this.db, this.container)
      : powerLiftRepo = PowerLiftRecordRepository(db),
        exerciseRepo = ExerciseRepository(db),
        personalRecordRepo = PersonalRecordRepository(db, ExerciseRepository(db));

  final AppDatabase db;
  final ProviderContainer container;
  final PowerLiftRecordRepository powerLiftRepo;
  final ExerciseRepository exerciseRepo;
  final PersonalRecordRepository personalRecordRepo;
}

Future<_Harness> _setUpHarness({
  Map<String, Object> extraPrefs = const {},
  PowerLiftRecordRepository Function(AppDatabase db)? powerLiftRepoBuilder,
}) async {
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
      if (powerLiftRepoBuilder != null)
        powerLiftRecordRepositoryProvider.overrideWithValue(powerLiftRepoBuilder(db)),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(db, container);
}

/// 點選動作 Picker 裡的分頁——刻意限定在 `liftPicker` 子樹內尋找文字,不用
/// 全域 `find.text(label).first`:三項最佳成績卡(TotalLiftCard)也會顯示
/// 「深蹲」「槓鈴臥推」「硬舉」這幾個字當作各動作的標籤,`.first` 誤中卡片
/// 上不可互動的文字時,tap() 不會有任何效果、也不會報錯,是一個吃過虧的
/// 陷阱寫法。
Future<void> _selectLift(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byKey(const Key('liftPicker')), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, _Harness harness) async {
  // 放大測試視窗——PowerliftingTab 一頁塞總和卡+picker+圖表+多筆手動紀錄+
  // 系統推估區,預設 800x600 的測試視窗裝不下,刪除按鈕等下方元件會落在
  // 視窗外導致 tap() 打不中(理由同 workout_flow_e2e_test.dart 開頭說明)。
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: Scaffold(body: PowerliftingTab())),
    ),
  );
  await tester.pumpAndSettle();
}

PowerLiftRecord _manualRecord({
  required String id,
  required PowerLift lift,
  required double oneRepMax,
  DateTime? achievedAt,
}) {
  final now = DateTime.now();
  return PowerLiftRecord(
    id: id,
    userId: testUserId,
    lift: lift,
    weight: oneRepMax,
    oneRepMax: oneRepMax,
    achievedAt: achievedAt ?? now,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('動作切換', () {
    testWidgets('切換動作分頁改變手動紀錄清單(不同動作各自的資料不互相污染)', (tester) async {
      final harness = await _setUpHarness();
      await harness.powerLiftRepo.create(
        _manualRecord(id: 'sq-1', lift: PowerLift.squat, oneRepMax: 140),
      );
      await harness.powerLiftRepo.create(
        _manualRecord(id: 'bp-1', lift: PowerLift.benchPress, oneRepMax: 85),
      );

      await _pump(tester, harness);

      // 預設選中深蹲(對照 iOS `selectedLift = .squat`)。
      expect(find.byKey(const Key('manualRecordRow-sq-1')), findsOneWidget);
      expect(find.byKey(const Key('manualRecordRow-bp-1')), findsNothing);

      await _selectLift(tester, '槓鈴臥推');

      expect(find.byKey(const Key('manualRecordRow-bp-1')), findsOneWidget);
      expect(find.byKey(const Key('manualRecordRow-sq-1')), findsNothing);
    });
  });

  group('三項最佳成績與總和', () {
    testWidgets('最佳成績取最高 1RM,不是最新一筆;三項總和為三者相加', (tester) async {
      final harness = await _setUpHarness();
      // 深蹲:較新的一筆 1RM 反而較低,驗證「最佳成績」取的是最高 1RM,
      // 不是「清單裡最新的一筆」。
      await harness.powerLiftRepo.create(
        _manualRecord(id: 'sq-old', lift: PowerLift.squat, oneRepMax: 140, achievedAt: DateTime(2026, 1, 1)),
      );
      await harness.powerLiftRepo.create(
        _manualRecord(id: 'sq-new', lift: PowerLift.squat, oneRepMax: 100, achievedAt: DateTime(2026, 2, 1)),
      );
      await harness.powerLiftRepo.create(
        _manualRecord(id: 'bp-1', lift: PowerLift.benchPress, oneRepMax: 80),
      );
      await harness.powerLiftRepo.create(
        _manualRecord(id: 'dl-1', lift: PowerLift.deadlift, oneRepMax: 180),
      );

      await _pump(tester, harness);

      final squatColumn = find.byKey(const Key('bestLiftColumn-squat'));
      expect(find.descendant(of: squatColumn, matching: find.text('140.0')), findsOneWidget);
      expect(find.descendant(of: squatColumn, matching: find.text('100.0')), findsNothing);

      // 手算:140(squat 最佳) + 80(bench) + 180(deadlift) = 400.0。
      // `totalLiftValue` 這個 Key 掛在 Text 本身,不是外層容器,所以直接讀
      // Text.data 比對,不用 find.descendant(找不到自己)。
      final totalText = tester.widget<Text>(find.byKey(const Key('totalLiftValue')));
      expect(totalText.data, '400.0');
    });

    testWidgets('沒有紀錄的動作顯示 "--"', (tester) async {
      final harness = await _setUpHarness();
      await harness.powerLiftRepo.create(
        _manualRecord(id: 'sq-1', lift: PowerLift.squat, oneRepMax: 100),
      );

      await _pump(tester, harness);

      final benchColumn = find.byKey(const Key('bestLiftColumn-benchPress'));
      expect(find.descendant(of: benchColumn, matching: find.text('--')), findsOneWidget);
    });
  });

  group('空狀態', () {
    testWidgets('選取動作沒有手動紀錄時顯示空狀態文案', (tester) async {
      final harness = await _setUpHarness();

      await _pump(tester, harness);

      expect(find.byKey(const Key('powerliftingEmptyState')), findsOneWidget);
      expect(find.text('尚無三項表記錄\n點擊右上角 + 開始記錄'), findsOneWidget);
      expect(find.byKey(const Key('oneRmTrendChart')), findsNothing);
    });
  });

  group('系統推估', () {
    testWidgets('只顯示動作名稱匹配目前選取三項動作的 PersonalRecord(匹配錯動作必紅)', (tester) async {
      final harness = await _setUpHarness();
      final systemExercises = await harness.exerciseRepo.fetchSystemExercises();
      final benchPress = systemExercises.firstWhere((e) => e.name == '槓鈴臥推');
      final shoulderPress = systemExercises.firstWhere((e) => e.name.contains('肩推'));

      final now = DateTime.now();
      await harness.personalRecordRepo.create(
        PersonalRecord(
          id: 'pr-bench',
          userId: testUserId,
          exerciseId: benchPress.id,
          weight: 90,
          reps: 1,
          oneRepMax: 90,
          achievedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.personalRecordRepo.create(
        PersonalRecord(
          id: 'pr-shoulder',
          userId: testUserId,
          exerciseId: shoulderPress.id,
          weight: 50,
          reps: 1,
          oneRepMax: 50,
          achievedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _pump(tester, harness);
      await _selectLift(tester, '槓鈴臥推');

      expect(find.byKey(Key('systemRecordRow-${benchPress.id}')), findsOneWidget);
      expect(find.byKey(Key('systemRecordRow-${shoulderPress.id}')), findsNothing);
      expect(find.byKey(const Key('systemEstimateBadge')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('systemEstimateBadge')), matching: find.text('推估: 90.0 kg')),
        findsOneWidget,
      );
    });

    testWidgets('沒有匹配動作時顯示系統推估空狀態', (tester) async {
      final harness = await _setUpHarness();

      await _pump(tester, harness);

      expect(find.byKey(const Key('systemEstimateEmptyState')), findsOneWidget);
      expect(find.text('尚無訓練數據\n開始訓練後系統會自動計算'), findsOneWidget);
    });
  });

  group('新增紀錄(真實寫入 + 獨立 SELECT 驗證)', () {
    testWidgets('填寫表單存檔後,直接查 repository 確認真的落地(不只信畫面)', (tester) async {
      final harness = await _setUpHarness();

      await _pump(tester, harness);

      await tester.tap(find.byKey(const Key('addPowerLiftRecordButton')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('powerLiftWeightField')), '120');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('powerLiftRepsField')), '3');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('savePowerLiftRecordButton')));
      await tester.pumpAndSettle();

      // 彈窗應已關閉(存檔成功)。
      expect(find.byKey(const Key('savePowerLiftRecordButton')), findsNothing);

      // 獨立 SELECT:不透過畫面斷言,直接呼叫 repository 查真實 DB 內容。
      final rows = await harness.powerLiftRepo.getAll(testUserId);
      expect(rows.length, 1);
      expect(rows.first.lift, PowerLift.squat);
      expect(rows.first.weight, 120);
      expect(rows.first.reps, 3);
      // 手算 Epley:120 * (1 + 3/30) = 132.0。
      expect(rows.first.oneRepMax, 132.0);

      // 畫面也應該同步刷新顯示新紀錄。
      expect(find.byKey(Key('manualRecordRow-${rows.first.id}')), findsOneWidget);
    });

    testWidgets('新增失敗路徑:注入拋錯 repository,顯示錯誤 SnackBar,彈窗不關閉', (tester) async {
      final harness = await _setUpHarness(
        powerLiftRepoBuilder: (db) => _ThrowingOnCreateRepository(db),
      );

      await _pump(tester, harness);

      await tester.tap(find.byKey(const Key('addPowerLiftRecordButton')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('powerLiftWeightField')), '100');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('savePowerLiftRecordButton')));
      await tester.pumpAndSettle();

      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);
      // 彈窗仍開著,存檔按鈕還在。
      expect(find.byKey(const Key('savePowerLiftRecordButton')), findsOneWidget);
    });
  });

  group('刪除紀錄(確認對話框兩分支)', () {
    testWidgets('取消刪除:紀錄仍在畫面上,DB 也沒有真的刪除', (tester) async {
      final harness = await _setUpHarness();
      await harness.powerLiftRepo.create(_manualRecord(id: 'sq-1', lift: PowerLift.squat, oneRepMax: 100));

      await _pump(tester, harness);

      await tester.tap(find.byKey(const Key('deletePowerLiftRecordButton-sq-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelDeletePowerLiftRecordButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('manualRecordRow-sq-1')), findsOneWidget);
      final rows = await harness.powerLiftRepo.getAll(testUserId);
      expect(rows.length, 1);
    });

    testWidgets('確認刪除:紀錄從畫面移除,DB 也真的刪除(獨立 SELECT 驗證)', (tester) async {
      final harness = await _setUpHarness();
      await harness.powerLiftRepo.create(_manualRecord(id: 'sq-1', lift: PowerLift.squat, oneRepMax: 100));

      await _pump(tester, harness);

      await tester.tap(find.byKey(const Key('deletePowerLiftRecordButton-sq-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDeletePowerLiftRecordButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('manualRecordRow-sq-1')), findsNothing);
      final rows = await harness.powerLiftRepo.getAll(testUserId);
      expect(rows, isEmpty);
    });

    testWidgets('刪除失敗路徑:注入拋錯 repository,顯示錯誤 SnackBar,紀錄仍在畫面上', (tester) async {
      final harness = await _setUpHarness(
        powerLiftRepoBuilder: (db) => _ThrowingOnDeleteRepository(db),
      );
      // 種子資料直接用真實 repository 寫入(harness.powerLiftRepo 是真實的,
      // 只有 provider 注入的那份是會拋錯的版本)。
      await PowerLiftRecordRepository(harness.db).create(
        _manualRecord(id: 'sq-1', lift: PowerLift.squat, oneRepMax: 100),
      );

      await _pump(tester, harness);

      await tester.tap(find.byKey(const Key('deletePowerLiftRecordButton-sq-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDeletePowerLiftRecordButton')));
      await tester.pumpAndSettle();

      expect(find.text('刪除失敗，請稍後再試'), findsOneWidget);
      expect(find.byKey(const Key('manualRecordRow-sq-1')), findsOneWidget);
    });
  });

  group('userId 解析:血緣 fallback', () {
    testWidgets('session 的 appleUserId 查無此人時,退回 CoreData 匯入血緣 id', (tester) async {
      // 血緣使用者實際存在於 Users 表,但 session 帶的是一個查無此人的 id。
      final harness = await _setUpHarness(
        extraPrefs: {
          kAppleUserIdKey: 'stranger-id-not-in-users-table',
          kCoreDataImportedUserIdKey: testUserId,
        },
      );
      await harness.powerLiftRepo.create(_manualRecord(id: 'sq-1', lift: PowerLift.squat, oneRepMax: 100));

      await _pump(tester, harness);

      // 若血緣 fallback 沒生效,_resolveUserId 會回傳 null,畫面會落在空狀態
      // 而看不到這筆屬於 testUserId 的紀錄。
      expect(find.byKey(const Key('manualRecordRow-sq-1')), findsOneWidget);
    });
  });
}
