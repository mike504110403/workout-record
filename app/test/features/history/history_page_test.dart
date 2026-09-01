// HistoryPage widget seam:pump 真實頁面(repositories/provider 一律用真的,
// 只換 appDatabaseProvider 為 in-memory DB、sharedPreferencesProvider 為
// mock prefs、必要時把 workoutRepositoryProvider 換成注入失敗行為的
// fake),斷言畫面呈現的內容——不測 controller 內部欄位。harness 慣例照抄
// test/features/dashboard/dashboard_page_test.dart(openTestDatabase +
// seedTestUser + ProviderContainer overrides + UncontrolledProviderScope
// pump 真 widget)。
//
// 月份相依的固定測試日期一律取「當月 10 號/11 號」(不用 DateTime.now() 的
// 相對天數,例如「昨天」)——每個月至少有 28 天,10/11 號保證不會跨月,
// 避免測試在月初幾天執行時 flaky(對照
// dashboard_page_test.dart `_referenceWeekStart` 開頭同樣「避開邊界時間點
// 造成的 flaky」考量)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide Workout, WorkoutExercise, WorkoutSet;
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/history/history_format.dart';
import 'package:workout_record/features/history/edit/workout_edit_page.dart';
import 'package:workout_record/features/history/history_page.dart';

import '../../data/test_helpers.dart';

/// [isDraft] = true 時 `endedAt` 明確落 null(草稿的定義),不是「沒傳就
/// 給預設值」——`DateTime? endedAt` 這種可選具名參數沒辦法用 `??` 分辨
/// 「呼叫端明確傳 null」跟「沒傳」,兩者在 Dart 裡看起來一樣,所以改用
/// 布林旗標明確表達意圖,避免草稿 fixture 意外被塞進一個非 null 的
/// endedAt(這裡曾經吃過虧:一開始用 `endedAt ?? startedAt.add(...)` 這種
/// 寫法,傳 `endedAt: null` 完全沒用,草稿會被靜默轉成已完成訓練,測試
/// 的兩種形狀 fixture 其實只有一種形狀,見 flutter test 實跑抓到的
/// 誤判)。
Workout _buildWorkout({
  required String id,
  required DateTime startedAt,
  bool isDraft = false,
  int duration = 60,
  double totalVolume = 1000,
  int totalSets = 10,
  int totalExercises = 3,
  List<WorkoutExercise> exercises = const [],
}) {
  final now = DateTime.now();
  return Workout(
    id: id,
    userId: testUserId,
    startedAt: startedAt,
    endedAt: isDraft ? null : startedAt.add(Duration(minutes: duration)),
    duration: duration,
    totalVolume: totalVolume,
    totalSets: totalSets,
    totalExercises: totalExercises,
    exercises: exercises,
    createdAt: now,
    updatedAt: now,
  );
}

WorkoutExercise _buildExercise({
  required String id,
  required String workoutId,
  required String exerciseId,
  int orderIndex = 0,
  List<WorkoutSet> sets = const [],
}) {
  final now = DateTime.now();
  return WorkoutExercise(
    id: id,
    workoutId: workoutId,
    exerciseId: exerciseId,
    orderIndex: orderIndex,
    sets: sets,
    createdAt: now,
    updatedAt: now,
  );
}

WorkoutSet _buildSet({
  required String id,
  required String workoutExerciseId,
  required int setNumber,
  required double weight,
  required int reps,
  bool isWarmup = false,
}) {
  final now = DateTime.now();
  return WorkoutSet(
    id: id,
    workoutExerciseId: workoutExerciseId,
    setNumber: setNumber,
    weight: weight,
    reps: reps,
    isWarmup: isWarmup,
    createdAt: now,
    updatedAt: now,
  );
}

/// M4/失敗路徑測試專用:模擬 `WorkoutRepository.delete` 拋錯(例如 DB 被
/// 鎖)。只覆寫 delete,其餘方法(fetchAll/fetchByDateRange/fetchById)沿用
/// 真實實作,指向同一個 db。
class _ThrowingDeleteWorkoutRepository extends WorkoutRepository {
  _ThrowingDeleteWorkoutRepository(super.db, super.exerciseRepository);

  @override
  Future<void> delete(String id) async {
    throw Exception('模擬刪除失敗(delete 失敗路徑測試用)');
  }
}

class _HistoryHarness {
  _HistoryHarness(this.db, this.container)
    : workoutRepo = WorkoutRepository(db, ExerciseRepository(db)),
      exerciseRepo = ExerciseRepository(db);

  final AppDatabase db;
  final ProviderContainer container;
  final WorkoutRepository workoutRepo;
  final ExerciseRepository exerciseRepo;
}

/// [workoutRepoBuilder] 給定時,把 `workoutRepositoryProvider` 換成它建出的
/// fake(用於刪除失敗路徑測試)。[disableAutoRetry] 關掉 riverpod 內建的自動
/// 重試(理由/用法同 dashboard_page_test.dart:140-151 注釋)——這裡的刪除
/// 失敗路徑設計上不會讓 provider state 落入 AsyncError(見
/// history_list_controller.dart `deleteWorkout` 文件注解),但仍照專案既有
/// 慣例帶上,避免任何一次重新查詢意外撞上自動重試造成的時序不確定性。
Future<_HistoryHarness> _setUpHarness({
  WorkoutRepository Function(AppDatabase db)? workoutRepoBuilder,
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
      if (workoutRepoBuilder != null)
        workoutRepositoryProvider.overrideWithValue(workoutRepoBuilder(db)),
    ],
  );
  addTearDown(container.dispose);
  return _HistoryHarness(db, container);
}

Future<void> _pumpHistory(WidgetTester tester, _HistoryHarness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: HistoryPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _switchToCalendar(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('historyViewModeSegment-calendar')));
  await tester.pumpAndSettle();
}

void main() {
  group('列表檢視', () {
    testWidgets('顯示已完成訓練,日期降冪排序', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'oldest',
          startedAt: now.subtract(const Duration(days: 4)),
          totalVolume: 100,
        ),
      );
      await harness.workoutRepo.create(
        _buildWorkout(id: 'newest', startedAt: now, totalVolume: 300),
      );
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'middle',
          startedAt: now.subtract(const Duration(days: 2)),
          totalVolume: 200,
        ),
      );

      await _pumpHistory(tester, harness);

      expect(find.byKey(const Key('historyWorkoutCard-newest')), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-middle')), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-oldest')), findsOneWidget);

      // 降冪:newest 應該畫在 middle 之上,middle 應該畫在 oldest 之上——
      // 拔掉/反轉排序方向這條測試必紅。
      final newestY = tester.getCenter(find.byKey(const Key('historyWorkoutCard-newest'))).dy;
      final middleY = tester.getCenter(find.byKey(const Key('historyWorkoutCard-middle'))).dy;
      final oldestY = tester.getCenter(find.byKey(const Key('historyWorkoutCard-oldest'))).dy;
      expect(newestY, lessThan(middleY));
      expect(middleY, lessThan(oldestY));
    });

    testWidgets('草稿(endedAt 為 null)不出現在列表,只有已完成訓練出現', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.workoutRepo.create(
        _buildWorkout(id: 'completed-1', startedAt: now, totalVolume: 500),
      );
      // 草稿:endedAt 明確傳 null,不吃預設值(fixture 必須兩種形狀都有)。
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'draft-1',
          startedAt: now.subtract(const Duration(hours: 1)),
          isDraft: true,
        ),
      );

      await _pumpHistory(tester, harness);

      expect(find.byKey(const Key('historyWorkoutCard-completed-1')), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-draft-1')), findsNothing);
      expect(find.byKey(const Key('historyEmptyState')), findsNothing);
    });

    testWidgets('無訓練紀錄時顯示空狀態文案', (tester) async {
      final harness = await _setUpHarness();

      await _pumpHistory(tester, harness);

      expect(find.byKey(const Key('historyEmptyState')), findsOneWidget);
      expect(find.text('尚無訓練記錄'), findsOneWidget);
    });
  });

  group('刪除流程(列表滑動)', () {
    testWidgets('滑動 → 確認對話框 → 取消則不刪除', (tester) async {
      final harness = await _setUpHarness();
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);

      await tester.drag(
        find.byKey(const Key('historyWorkoutDismissible-w-1')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteWorkoutDialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('deleteWorkoutCancelButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historyWorkoutCard-w-1')), findsOneWidget);
      final stillThere = await harness.workoutRepo.fetchById('w-1');
      expect(stillThere, isNotNull);
    });

    testWidgets('滑動 → 確認對話框 → 確認後該筆從列表消失、DB 查不到', (tester) async {
      final harness = await _setUpHarness();
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);

      await tester.drag(
        find.byKey(const Key('historyWorkoutDismissible-w-1')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteWorkoutConfirmButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historyWorkoutCard-w-1')), findsNothing);
      expect(find.byKey(const Key('historyEmptyState')), findsOneWidget);
      final deleted = await harness.workoutRepo.fetchById('w-1');
      expect(deleted, isNull);
    });

    testWidgets('刪除失敗:UI 解除 loading、浮出錯誤、該筆仍在列表與 DB 內', (tester) async {
      final harness = await _setUpHarness(
        workoutRepoBuilder: (db) => _ThrowingDeleteWorkoutRepository(db, ExerciseRepository(db)),
        disableAutoRetry: true,
      );
      // 種子資料透過 harness.workoutRepo(真實 repository,同一個 db)寫入,
      // 覆寫的是 provider 讀到的 repository,不影響種子寫入路徑。
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);

      await tester.drag(
        find.byKey(const Key('historyWorkoutDismissible-w-1')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteWorkoutConfirmButton')));
      await tester.pumpAndSettle();

      // 浮出錯誤。
      expect(find.text('刪除失敗，請稍後再試'), findsOneWidget);
      // 該筆仍在列表(刪除失敗不該讓卡片消失)。
      expect(find.byKey(const Key('historyWorkoutCard-w-1')), findsOneWidget);
      // loading 遮罩已解除,不是卡死——拔掉 catch 分支裡移除 deletingIds
      // 那行,這裡必紅(遮罩會一直卡著)。
      expect(find.byKey(const Key('historyWorkoutDeletingIndicator-w-1')), findsNothing);
      // DB 真的沒被刪掉。
      final stillThere = await harness.workoutRepo.fetchById('w-1');
      expect(stillThere, isNotNull);
    });
  });

  group('日曆檢視', () {
    testWidgets('有訓練的日子顯示標記,沒有的不顯示', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      final dayWithWorkout = DateTime(now.year, now.month, 10, 9);
      await harness.workoutRepo.create(_buildWorkout(id: 'w-day10', startedAt: dayWithWorkout));

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      expect(find.byKey(Key('historyCalendarMarker-${now.year}-${now.month}-10')), findsOneWidget);
      expect(find.byKey(Key('historyCalendarMarker-${now.year}-${now.month}-11')), findsNothing);
    });

    testWidgets('草稿不會在日曆產生標記,只有已完成訓練會', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.workoutRepo.create(
        _buildWorkout(id: 'completed-10', startedAt: DateTime(now.year, now.month, 10, 9)),
      );
      // 草稿放在同月第 11 天。
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'draft-11',
          startedAt: DateTime(now.year, now.month, 11, 9),
          isDraft: true,
        ),
      );

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      expect(find.byKey(Key('historyCalendarMarker-${now.year}-${now.month}-10')), findsOneWidget);
      expect(find.byKey(Key('historyCalendarMarker-${now.year}-${now.month}-11')), findsNothing);
    });

    testWidgets('點選有訓練的日期,下方顯示當天訓練清單,可點進詳情頁', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, 10, 9);
      await harness.workoutRepo.create(
        _buildWorkout(id: 'w-day10', startedAt: day, totalVolume: 777),
      );

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      await tester.tap(find.byKey(Key('historyCalendarDay-${now.year}-${now.month}-10')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historyCalendarSelectedDateSection')), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-w-day10')), findsOneWidget);

      // 月曆格線 + 當天訓練清單可能超出測試視窗高度,先捲動讓卡片進入
      // 可視範圍才能被 tap() 命中(對照 dashboard_page_test.dart「查看全部」
      // 按鈕同樣需要 ensureVisible 的理由)。
      await tester.ensureVisible(find.byKey(const Key('historyWorkoutCard-w-day10')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('historyWorkoutCard-w-day10')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('workoutDetailSummaryCard')), findsOneWidget);
    });
  });

  group('詳情頁', () {
    testWidgets('summary 欄位正確呈現(日期/總容量/時長/總組數/動作數,全部欄位皆填)', (tester) async {
      final harness = await _setUpHarness();
      final exercises = await harness.exerciseRepo.fetchAll();
      final exerciseA = exercises[0];
      final exerciseB = exercises[1];
      final startedAt = DateTime.now();

      final exerciseFixtures = [
        _buildExercise(
          id: 'we-1',
          workoutId: 'w-detail',
          exerciseId: exerciseA.id,
          orderIndex: 0,
          sets: [
            _buildSet(id: 'set-1', workoutExerciseId: 'we-1', setNumber: 1, weight: 60, reps: 8),
            _buildSet(id: 'set-2', workoutExerciseId: 'we-1', setNumber: 2, weight: 65, reps: 6),
          ],
        ),
        _buildExercise(
          id: 'we-2',
          workoutId: 'w-detail',
          exerciseId: exerciseB.id,
          orderIndex: 1,
          sets: [
            _buildSet(id: 'set-3', workoutExerciseId: 'we-2', setNumber: 1, weight: 40, reps: 10),
          ],
        ),
      ];
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'w-detail',
          startedAt: startedAt,
          duration: 45,
          totalVolume: 1234,
          totalSets: 7,
          totalExercises: 2,
          exercises: exerciseFixtures,
        ),
      );

      await _pumpHistory(tester, harness);
      await tester.tap(find.byKey(const Key('historyWorkoutCard-w-detail')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('workoutDetailSummaryCard')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('workoutDetailSummaryCard')),
          matching: find.text(formatHistoryDate(startedAt)),
        ),
        findsOneWidget,
      );
      expect(find.text(formatVolumeKg(1234)), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const Key('workoutDetailDuration')),
          matching: find.text('45 分鐘'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('workoutDetailTotalSets')),
          matching: find.text('7 組'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('workoutDetailTotalExercises')),
          matching: find.text('2 個'),
        ),
        findsOneWidget,
      );

      // 編輯按鈕已接線(WAVE5 merge):按下推入編輯頁。
      expect(find.byKey(const Key('workoutDetailEditButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('workoutDetailEditButton')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutEditPage), findsOneWidget);
    });

    testWidgets('編輯返回後詳情頁重讀:編輯頁改組重量 → 返回 → summary 顯示新值', (tester) async {
      final harness = await _setUpHarness();
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);
      await tester.tap(find.byKey(const Key('historyWorkoutCard-w-1')));
      await tester.pumpAndSettle();

      // 進編輯頁前的總容量快照存在。
      expect(find.byKey(const Key('workoutDetailSummaryCard')), findsOneWidget);

      await tester.tap(find.byKey(const Key('workoutDetailEditButton')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutEditPage), findsOneWidget);

      // 不透過 UI 操作編輯頁(那是編輯頁自己的測試守備),直接對 DB 跑
      // recomputeSummary 模擬「編輯頁改了資料」的效果——fixture 無任何
      // 組數,重算後 totalVolume 從 1000 變 0,與舊快照可區分。焦點放在
      // 「返回後詳情頁有沒有重讀」。
      await harness.workoutRepo.recomputeSummary('w-1');
      final after = await harness.workoutRepo.fetchById('w-1');
      expect(after!.totalVolume, isNot(1000)); // 前提:重算後值真的變了。

      // 返回詳情頁 → _openEdit 的 refetch 生效,顯示重算後的新總容量。
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workoutDetailSummaryCard')), findsOneWidget);
      // key 掛在 Text 自身(workout_detail_page.dart:142-143),直接讀 data。
      expect(
        tester.widget<Text>(find.byKey(const Key('workoutDetailTotalVolume'))).data,
        formatVolumeKg(after.totalVolume),
      );
    });

    testWidgets('刪除按鈕:確認後 pop 回列表,該筆從列表消失', (tester) async {
      final harness = await _setUpHarness();
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);
      await tester.tap(find.byKey(const Key('historyWorkoutCard-w-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('workoutDetailDeleteButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteWorkoutDialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('deleteWorkoutConfirmButton')));
      await tester.pumpAndSettle();

      // 已 pop 回列表頁,該筆消失。
      expect(find.byKey(const Key('workoutDetailSummaryCard')), findsNothing);
      expect(find.byKey(const Key('historyWorkoutCard-w-1')), findsNothing);
      final deleted = await harness.workoutRepo.fetchById('w-1');
      expect(deleted, isNull);
    });

    // 補測(驗收退回):列表滑動路徑的取消分支有測過,但詳情頁刪除按鈕是
    // 各自獨立的一份 `_confirmAndDelete`(workout_detail_page.dart:78 的
    // `if (confirmed != true) return;`),兩處入口沒有共用同一段判斷式,
    // 各自都要顧到「取消不刪」——這條補上詳情頁那一份。
    testWidgets('刪除按鈕:對話框取消 → 不刪除,停留在詳情頁,該筆仍在列表與 DB', (tester) async {
      final harness = await _setUpHarness();
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);
      await tester.tap(find.byKey(const Key('historyWorkoutCard-w-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('workoutDetailDeleteButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteWorkoutDialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('deleteWorkoutCancelButton')));
      await tester.pumpAndSettle();

      // 仍停留在詳情頁,沒有被誤 pop。
      expect(find.byKey(const Key('workoutDetailSummaryCard')), findsOneWidget);

      // 回到列表頁確認該筆仍在。
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historyWorkoutCard-w-1')), findsOneWidget);

      final stillThere = await harness.workoutRepo.fetchById('w-1');
      expect(stillThere, isNotNull);
    });

    // 補測(驗收退回 review 打回指派項 (b)):列表滑動路徑的刪除失敗已測過
    // (見上面「刪除流程(列表滑動)」群組),但詳情頁刪除按鈕的
    // `_confirmAndDelete`(workout_detail_page.dart)是獨立一份非同步失敗
    // 處理(`_isDeleting` 旗標 + try/catch),沒有測試守著。
    testWidgets('刪除按鈕:刪除失敗 → 解除 loading(按鈕恢復可按)、浮出錯誤、停留在詳情頁,該筆仍在列表與 DB', (tester) async {
      final harness = await _setUpHarness(
        workoutRepoBuilder: (db) => _ThrowingDeleteWorkoutRepository(db, ExerciseRepository(db)),
        disableAutoRetry: true,
      );
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);
      await tester.tap(find.byKey(const Key('historyWorkoutCard-w-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('workoutDetailDeleteButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deleteWorkoutDialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('deleteWorkoutConfirmButton')));
      await tester.pumpAndSettle();

      // 浮出錯誤,仍停留在詳情頁(沒有被誤 pop)。
      expect(find.text('刪除失敗，請稍後再試'), findsOneWidget);
      expect(find.byKey(const Key('workoutDetailSummaryCard')), findsOneWidget);

      // 刪除按鈕的 loading 已解除、恢復可按——拔掉 catch 分支裡
      // `setState(() => _isDeleting = false);` 那行,這裡必紅(按鈕會一直
      // 卡在 disabled 的 loading 圖示)。
      final deleteButton = tester.widget<IconButton>(
        find.byKey(const Key('workoutDetailDeleteButton')),
      );
      expect(deleteButton.onPressed, isNotNull);

      // 回到列表頁確認該筆仍在,DB 也真的沒被刪掉。
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historyWorkoutCard-w-1')), findsOneWidget);
      final stillThere = await harness.workoutRepo.fetchById('w-1');
      expect(stillThere, isNotNull);
    });
  });
}
