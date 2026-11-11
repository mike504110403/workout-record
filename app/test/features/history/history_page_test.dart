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
import 'package:workout_record/features/history/calendar_grid.dart';
import 'package:workout_record/features/history/history_calendar_controller.dart';
import 'package:workout_record/features/history/history_format.dart';
import 'package:workout_record/features/history/history_week_grouping.dart';
import 'package:workout_record/features/history/edit/workout_edit_page.dart';
import 'package:workout_record/features/history/history_page.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';

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
class _ThrowingDeleteWorkoutRepository extends DriftWorkoutRepository {
  _ThrowingDeleteWorkoutRepository(super.db, super.exerciseRepository);

  @override
  Future<void> delete(String id) async {
    throw Exception('模擬刪除失敗(delete 失敗路徑測試用)');
  }
}

/// 日曆預設選中/重試測試專用:可讓前 [failMonthLoads] 次 `fetchByDateRange`
/// 失敗(模擬初次載入失敗再重試)、讓 `fetchRecent` 拋錯,並計數 `fetchRecent`
/// 被呼叫幾次。其餘沿用真實實作。
class _FlakyCalendarWorkoutRepository extends DriftWorkoutRepository {
  _FlakyCalendarWorkoutRepository(
    super.db,
    super.exerciseRepository, {
    this.failMonthLoads = 0,
    this.recentThrows = false,
  });

  int failMonthLoads;
  final bool recentThrows;
  int fetchRecentCalls = 0;

  @override
  Future<List<Workout>> fetchByDateRange(DateTime from, DateTime to) async {
    if (failMonthLoads > 0) {
      failMonthLoads--;
      throw Exception('模擬月份查詢失敗');
    }
    return super.fetchByDateRange(from, to);
  }

  @override
  Future<List<Workout>> fetchRecent(int limit) async {
    fetchRecentCalls++;
    if (recentThrows) throw Exception('模擬 fetchRecent 失敗');
    return super.fetchRecent(limit);
  }
}

class _HistoryHarness {
  _HistoryHarness(this.db, this.container)
    : workoutRepo = DriftWorkoutRepository(db, DriftExerciseRepository(db)),
      exerciseRepo = DriftExerciseRepository(db);

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
/// [weightUnit] 給定時覆寫 `weightUnitProvider`(波 6 lb 模式回歸測試用,
/// 理由同 dashboard_page_test.dart `_setUpHarness` 的同名參數)。
Future<_HistoryHarness> _setUpHarness({
  WorkoutRepository Function(AppDatabase db)? workoutRepoBuilder,
  bool disableAutoRetry = false,
  WeightUnit? weightUnit,
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
      if (workoutRepoBuilder != null) workoutRepositoryProvider.overrideWithValue(workoutRepoBuilder(db)),
      if (weightUnit != null) weightUnitProvider.overrideWithValue(weightUnit),
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
  await tester.tap(find.byKey(const Key('historyViewModeToggleButton')));
  await tester.pumpAndSettle();
}

void main() {
  group('列表檢視', () {
    testWidgets('顯示已完成訓練,日期降冪排序', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.workoutRepo.create(
        _buildWorkout(id: 'oldest', startedAt: now.subtract(const Duration(days: 4)), totalVolume: 100),
      );
      await harness.workoutRepo.create(_buildWorkout(id: 'newest', startedAt: now, totalVolume: 300));
      await harness.workoutRepo.create(
        _buildWorkout(id: 'middle', startedAt: now.subtract(const Duration(days: 2)), totalVolume: 200),
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
      await harness.workoutRepo.create(_buildWorkout(id: 'completed-1', startedAt: now, totalVolume: 500));
      // 草稿:endedAt 明確傳 null,不吃預設值(fixture 必須兩種形狀都有)。
      await harness.workoutRepo.create(
        _buildWorkout(id: 'draft-1', startedAt: now.subtract(const Duration(hours: 1)), isDraft: true),
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

    testWidgets('按週分組:本週/上週/M/D – M/D 標題,各筆歸在對應標題之下,卡片顯示星期幾', (tester) async {
      final harness = await _setUpHarness();
      final thisWeek = startOfIsoWeek(DateTime.now());
      // 本週週一、上週三、兩週前的週五(標題為日期區間)。
      final thisWeekDay = DateTime(thisWeek.year, thisWeek.month, thisWeek.day, 9);
      final lastWeekDay = DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 5, 9);
      final olderDay = DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 10, 9);
      final olderStart = startOfIsoWeek(olderDay);
      final olderEnd = DateTime(olderStart.year, olderStart.month, olderStart.day + 6);
      final olderLabel = '${olderStart.month}/${olderStart.day} – ${olderEnd.month}/${olderEnd.day}';

      await harness.workoutRepo.create(_buildWorkout(id: 'w-this', startedAt: thisWeekDay));
      await harness.workoutRepo.create(_buildWorkout(id: 'w-last', startedAt: lastWeekDay));
      await harness.workoutRepo.create(_buildWorkout(id: 'w-older', startedAt: olderDay));

      await _pumpHistory(tester, harness);

      expect(find.text('本週'), findsOneWidget);
      expect(find.text('上週'), findsOneWidget);
      expect(find.text(olderLabel), findsOneWidget);

      // 垂直順序:標題 → 該週卡片 → 下一個標題 → ...
      double y(Finder f) => tester.getCenter(f).dy;
      final thisHeader = y(find.text('本週'));
      final lastHeader = y(find.text('上週'));
      final olderHeader = y(find.text(olderLabel));
      final thisCard = y(find.byKey(const Key('historyWorkoutCard-w-this')));
      final lastCard = y(find.byKey(const Key('historyWorkoutCard-w-last')));
      final olderCard = y(find.byKey(const Key('historyWorkoutCard-w-older')));
      expect(thisHeader, lessThan(thisCard));
      expect(thisCard, lessThan(lastHeader));
      expect(lastHeader, lessThan(lastCard));
      expect(lastCard, lessThan(olderHeader));
      expect(olderHeader, lessThan(olderCard));

      // 星期幾:上週三固定是「週三」。
      expect(
        find.descendant(of: find.byKey(const Key('historyWorkoutCard-w-last')), matching: find.text('週三')),
        findsOneWidget,
      );
    });

    testWidgets('卡片顯示動作名摘要:最多兩個動作名,超出以 +N 收尾', (tester) async {
      final harness = await _setUpHarness();
      final exercises = await harness.exerciseRepo.fetchAll();
      WorkoutExercise we(String id, String workoutId, int index) => _buildExercise(
        id: id,
        workoutId: workoutId,
        exerciseId: exercises[index].id,
        orderIndex: index,
        sets: [_buildSet(id: '$id-s', workoutExerciseId: id, setNumber: 1, weight: 50, reps: 5)],
      );
      final now = DateTime.now();
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'w-three',
          startedAt: now,
          totalExercises: 3,
          exercises: [we('we-a', 'w-three', 0), we('we-b', 'w-three', 1), we('we-c', 'w-three', 2)],
        ),
      );
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'w-one',
          startedAt: now.subtract(const Duration(minutes: 5)),
          totalExercises: 1,
          exercises: [we('we-d', 'w-one', 3)],
        ),
      );

      await _pumpHistory(tester, harness);

      final names = [for (final e in exercises) e.name];
      expect(
        find.descendant(
          of: find.byKey(const Key('historyWorkoutCard-w-three')),
          matching: find.text('${names[0]}、${names[1]} +1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('historyWorkoutCard-w-one')), matching: find.text(names[3])),
        findsOneWidget,
      );
    });
  });

  group('頂列與檢視切換', () {
    testWidgets('沒有「歷史」標題、沒有 AppBar 與列表/日曆分段鈕,只有一個切換 icon', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHistory(tester, harness);

      expect(find.text('歷史'), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SegmentedButton<HistoryViewMode>), findsNothing);
      expect(find.byKey(const Key('historyViewModeToggleButton')), findsOneWidget);
    });

    testWidgets('切換 icon 在列表與日曆之間來回切換,icon 指向「下一個」檢視', (tester) async {
      final harness = await _setUpHarness();
      await harness.workoutRepo.create(_buildWorkout(id: 'w-toggle', startedAt: DateTime.now()));
      await _pumpHistory(tester, harness);

      // 起始是列表:有卡片、沒有月曆;icon 是日曆(按下去去日曆)。
      expect(find.byKey(const Key('historyWorkoutDismissible-w-toggle')), findsOneWidget);
      expect(find.byKey(const Key('historyCalendarGrid')), findsNothing);
      expect(find.byIcon(Icons.calendar_month), findsOneWidget);

      await tester.tap(find.byKey(const Key('historyViewModeToggleButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historyCalendarGrid')), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutDismissible-w-toggle')), findsNothing);
      expect(find.byIcon(Icons.view_list), findsOneWidget);

      await tester.tap(find.byKey(const Key('historyViewModeToggleButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historyCalendarGrid')), findsNothing);
      expect(find.byKey(const Key('historyWorkoutDismissible-w-toggle')), findsOneWidget);
    });

    testWidgets('日曆模式:切換 icon 併進月份列,不另佔頂列', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      final toggleY = tester.getCenter(find.byKey(const Key('historyViewModeToggleButton'))).dy;
      final prevY = tester.getCenter(find.byKey(const Key('historyCalendarPrevMonthButton'))).dy;
      final nextY = tester.getCenter(find.byKey(const Key('historyCalendarNextMonthButton'))).dy;
      expect(toggleY, prevY);
      expect(toggleY, nextY);
      // 切換鈕在月份導覽右側。
      expect(
        tester.getCenter(find.byKey(const Key('historyViewModeToggleButton'))).dx,
        greaterThan(tester.getCenter(find.byKey(const Key('historyCalendarNextMonthButton'))).dx),
      );
    });

    testWidgets('日曆載入失敗時切換 icon 仍在,可切回列表', (tester) async {
      final harness = await _setUpHarness(
        disableAutoRetry: true,
        workoutRepoBuilder: (db) =>
            _FlakyCalendarWorkoutRepository(db, DriftExerciseRepository(db), failMonthLoads: 1),
      );
      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      expect(find.byKey(const Key('historyCalendarErrorRetryButton')), findsOneWidget);
      expect(find.byKey(const Key('historyViewModeToggleButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('historyViewModeToggleButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historyCalendarErrorRetryButton')), findsNothing);
      expect(find.byKey(const Key('historyEmptyState')), findsOneWidget);
    });

    testWidgets('列表空狀態時切換 icon 仍在(日曆不會被鎖在外面)', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHistory(tester, harness);

      expect(find.byKey(const Key('historyEmptyState')), findsOneWidget);
      await _switchToCalendar(tester);
      expect(find.byKey(const Key('historyCalendarGrid')), findsOneWidget);
    });
  });

  group('列表懶建置', () {
    testWidgets('60 筆長清單:只建可視範圍的列,仍可捲到最底找到最後一筆', (tester) async {
      final harness = await _setUpHarness();
      // 每天一筆、往前推 60 天,newest 在最上面;最後一筆是 w-59。
      final base = DateTime.now();
      for (var i = 0; i < 60; i++) {
        await harness.workoutRepo.create(
          _buildWorkout(id: 'w-$i', startedAt: base.subtract(Duration(days: i)), totalVolume: 100.0 + i),
        );
      }

      await _pumpHistory(tester, harness);

      // 直接斷言結構:列表必須是 builder 式 delegate。`ListView(children:)` 的
      // Element 本來就懶,光看「最後一筆還沒建出來」分不出它與 builder 清單,
      // 但它的 delegate 是 SliverChildListDelegate(children 已全數建好 widget)。
      final sliverList = tester.widget<SliverList>(find.byType(SliverList));
      expect(sliverList.delegate, isA<SliverChildBuilderDelegate>());

      // 行為面:最上面的在、最底下的還沒建。
      expect(find.byKey(const Key('historyWorkoutCard-w-0')), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-w-59')), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('historyWorkoutCard-w-59')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('historyWorkoutCard-w-59')), findsOneWidget);
      // 捲到底之後,最上面的已被回收。
      expect(find.byKey(const Key('historyWorkoutCard-w-0')), findsNothing);
    });
  });

  group('刪除流程(列表滑動)', () {
    testWidgets('滑動 → 確認對話框 → 取消則不刪除', (tester) async {
      final harness = await _setUpHarness();
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);

      await tester.drag(find.byKey(const Key('historyWorkoutDismissible-w-1')), const Offset(-500, 0));
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

      await tester.drag(find.byKey(const Key('historyWorkoutDismissible-w-1')), const Offset(-500, 0));
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
        workoutRepoBuilder: (db) => _ThrowingDeleteWorkoutRepository(db, DriftExerciseRepository(db)),
        disableAutoRetry: true,
      );
      // 種子資料透過 harness.workoutRepo(真實 repository,同一個 db)寫入,
      // 覆寫的是 provider 讀到的 repository,不影響種子寫入路徑。
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);

      await tester.drag(find.byKey(const Key('historyWorkoutDismissible-w-1')), const Offset(-500, 0));
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
        _buildWorkout(id: 'draft-11', startedAt: DateTime(now.year, now.month, 11, 9), isDraft: true),
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
      await harness.workoutRepo.create(_buildWorkout(id: 'w-day10', startedAt: day, totalVolume: 777));

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

  group('日曆預設選中', () {
    String headerOf(DateTime d) => '${formatHistoryDate(d)} ${formatHistoryWeekday(d)}';

    testWidgets('今天有訓練 → 預設選今天,下方直接列出今天的訓練', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.workoutRepo.create(_buildWorkout(id: 'w-today', startedAt: now));
      // 同月另一天也有訓練(上月不會干擾):確認選的是今天而不是「最近有訓練的某天」。
      await harness.workoutRepo.create(
        _buildWorkout(id: 'w-earlier', startedAt: now.subtract(const Duration(hours: 30))),
      );

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      expect(find.byKey(const Key('historyCalendarSelectedDateSection')), findsOneWidget);
      expect(find.text(headerOf(now)), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-w-today')), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-w-earlier')), findsNothing);
    });

    testWidgets('今天沒訓練 → 選最近一次有訓練的日子(同月)', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      final earlier = DateTime(now.year, now.month, 1, 9);
      await harness.workoutRepo.create(_buildWorkout(id: 'w-first', startedAt: earlier));

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      expect(find.text(headerOf(earlier)), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-w-first')), findsOneWidget);
      expect(find.text('當天無訓練記錄'), findsNothing);
    }, skip: DateTime.now().day == 1); // 1 號時「今天沒訓練」與「選 1 號」無法區分。

    testWidgets('今天沒訓練且最近一次在上個月 → 顯示月份一併切到上個月並選中該日', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      final lastMonthDay = DateTime(now.year, now.month - 1, 10, 9);
      await harness.workoutRepo.create(_buildWorkout(id: 'w-old', startedAt: lastMonthDay));

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      expect(find.text(formatMonthLabel(DateTime(lastMonthDay.year, lastMonthDay.month, 1))), findsOneWidget);
      expect(find.text(headerOf(lastMonthDay)), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-w-old')), findsOneWidget);
    });

    testWidgets('完全沒有訓練 → 選今天,顯示「當天無訓練記錄」', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      expect(find.text(headerOf(now)), findsOneWidget);
      expect(find.text('當天無訓練記錄'), findsOneWidget);
    });

    testWidgets('本月有訓練時直接取本月最近一天,不呼叫 fetchRecent', (tester) async {
      late _FlakyCalendarWorkoutRepository repo;
      final harness = await _setUpHarness(
        workoutRepoBuilder: (db) =>
            repo = _FlakyCalendarWorkoutRepository(db, DriftExerciseRepository(db), recentThrows: true),
      );
      final now = DateTime.now();
      final d1 = DateTime(now.year, now.month, 1, 9);
      await harness.workoutRepo.create(_buildWorkout(id: 'w-first', startedAt: d1));

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      expect(find.byKey(const Key('historyWorkoutCard-w-first')), findsOneWidget);
      expect(repo.fetchRecentCalls, 0);
    });

    testWidgets('本月沒資料且 fetchRecent 失敗 → 日曆照常顯示並選今天,不變錯誤頁', (tester) async {
      late _FlakyCalendarWorkoutRepository repo;
      final harness = await _setUpHarness(
        disableAutoRetry: true,
        workoutRepoBuilder: (db) =>
            repo = _FlakyCalendarWorkoutRepository(db, DriftExerciseRepository(db), recentThrows: true),
      );

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      expect(repo.fetchRecentCalls, 1);
      expect(find.byKey(const Key('historyCalendarErrorRetryButton')), findsNothing);
      expect(find.byKey(const Key('historyCalendarGrid')), findsOneWidget);
      expect(find.text(headerOf(DateTime.now())), findsOneWidget);
      expect(find.text('當天無訓練記錄'), findsOneWidget);
    });

    testWidgets('初次載入失敗後按重試 → 套用預設選中(今天有訓練就選今天)', (tester) async {
      final harness = await _setUpHarness(
        disableAutoRetry: true,
        workoutRepoBuilder: (db) =>
            _FlakyCalendarWorkoutRepository(db, DriftExerciseRepository(db), failMonthLoads: 1),
      );
      await harness.workoutRepo.create(_buildWorkout(id: 'w-today', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);
      expect(find.byKey(const Key('historyCalendarErrorRetryButton')), findsOneWidget);

      await tester.tap(find.byKey(const Key('historyCalendarErrorRetryButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historyCalendarGrid')), findsOneWidget);
      expect(find.byKey(const Key('historyCalendarSelectedDateSection')), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-w-today')), findsOneWidget);
    });

    testWidgets('日曆沒開過就被列表刪除觸發 refresh → 套用預設選中', (tester) async {
      final harness = await _setUpHarness();
      await harness.workoutRepo.create(_buildWorkout(id: 'w-today', startedAt: DateTime.now()));

      await _pumpHistory(tester, harness);
      // 日曆從未顯示過:直接叫 refresh(列表刪除成功後就是這樣呼叫)。
      await harness.container.read(historyCalendarControllerProvider.notifier).refresh();
      final state = harness.container.read(historyCalendarControllerProvider).requireValue;
      expect(state.selectedDate, dateOnly(DateTime.now()));
      expect(state.selectedWorkouts.map((w) => w.id), ['w-today']);
    });

    testWidgets('切月份:有訓練的月份選該月最近一天,沒有訓練的月份不選(下方不留空白區塊)', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      final d10 = DateTime(now.year, now.month - 1, 10, 9);
      final d20 = DateTime(now.year, now.month - 1, 20, 9);
      await harness.workoutRepo.create(_buildWorkout(id: 'w-10', startedAt: d10));
      await harness.workoutRepo.create(_buildWorkout(id: 'w-20', startedAt: d20));

      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);
      expect(find.text(headerOf(d20)), findsOneWidget);

      // 下個月(本月)沒有訓練 → 不選。
      await tester.tap(find.byKey(const Key('historyCalendarNextMonthButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historyCalendarSelectedDateSection')), findsNothing);

      // 回上個月 → 選該月最近一天(20 號)。
      await tester.tap(find.byKey(const Key('historyCalendarPrevMonthButton')));
      await tester.pumpAndSettle();
      expect(find.text(headerOf(d20)), findsOneWidget);
      expect(find.byKey(const Key('historyWorkoutCard-w-20')), findsOneWidget);
    });
  });

  group('日曆星期列', () {
    testWidgets('顯示一二三四五六日標題,且日期格落在對應星期欄(週一起算)', (tester) async {
      final harness = await _setUpHarness();
      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      const labels = ['一', '二', '三', '四', '五', '六', '日'];
      final headerXs = <double>[];
      for (var i = 0; i < labels.length; i++) {
        final header = find.byKey(Key('historyCalendarWeekday-$i'));
        expect(header, findsOneWidget);
        expect(tester.widget<Text>(header).data, labels[i]);
        headerXs.add(tester.getCenter(header).dx);
      }
      // 由左到右嚴格遞增。
      for (var i = 1; i < headerXs.length; i++) {
        expect(headerXs[i], greaterThan(headerXs[i - 1]));
      }

      // 當月 1 號所在欄 = weekday - 1(週一=0),其水平中心要對齊該欄標題。
      final now = DateTime.now();
      final first = DateTime(now.year, now.month, 1);
      final cell = find.byKey(Key('historyCalendarDay-${now.year}-${now.month}-1'));
      expect(tester.getCenter(cell).dx, closeTo(headerXs[first.weekday - 1], 1.0));
    });

    testWidgets('有訓練的日期格有實心底色(與無訓練的日期格不同)', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.workoutRepo.create(
        _buildWorkout(id: 'w-day10', startedAt: DateTime(now.year, now.month, 10, 9)),
      );
      await _pumpHistory(tester, harness);
      await _switchToCalendar(tester);

      Color? backgroundOf(int day) {
        final container = find.descendant(
          of: find.byKey(Key('historyCalendarDay-${now.year}-${now.month}-$day')),
          matching: find.byType(Container),
        );
        final decoration = tester.widget<Container>(container.first).decoration as BoxDecoration;
        return decoration.color;
      }

      expect(backgroundOf(10), isNotNull);
      // 12 號既沒訓練、也一定不是今天以外的特殊格(若今天剛好是 12 號,改比 13 號)。
      final plainDay = now.day == 12 ? 13 : 12;
      expect(backgroundOf(plainDay), isNull);
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
          sets: [_buildSet(id: 'set-3', workoutExerciseId: 'we-2', setNumber: 1, weight: 40, reps: 10)],
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
      expect(find.text(formatVolumeKg(1234, WeightUnit.kg)), findsWidgets);
      expect(
        find.descendant(of: find.byKey(const Key('workoutDetailDuration')), matching: find.text('45 分鐘')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('workoutDetailTotalSets')), matching: find.text('7 組')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('workoutDetailTotalExercises')), matching: find.text('2 個')),
        findsOneWidget,
      );

      // 編輯按鈕已接線(WAVE5 merge):按下推入編輯頁。
      expect(find.byKey(const Key('workoutDetailEditButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('workoutDetailEditButton')));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutEditPage), findsOneWidget);
    });

    testWidgets('動作明細懶建置:很多個動作時最後一個要捲動才建出來', (tester) async {
      final harness = await _setUpHarness();
      final exerciseId = (await harness.exerciseRepo.fetchSystemExercises()).first.id;
      const count = 15;
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'w-many',
          startedAt: DateTime.now(),
          totalExercises: count,
          exercises: [
            for (var i = 0; i < count; i++)
              _buildExercise(
                id: 'we-$i',
                workoutId: 'w-many',
                exerciseId: exerciseId,
                orderIndex: i,
                sets: [_buildSet(id: 'set-$i', workoutExerciseId: 'we-$i', setNumber: 1, weight: 50, reps: 5)],
              ),
          ],
        ),
      );

      await _pumpHistory(tester, harness);
      await tester.tap(find.byKey(const Key('historyWorkoutCard-w-many')));
      await tester.pumpAndSettle();

      // 前面還有摘要卡與容量分布卡,動作明細尾端不在可視範圍 → 沒建出來。
      expect(find.byKey(const Key('workoutDetailExercise-we-14')), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('workoutDetailExercise-we-14')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('workoutDetailExercise-we-14')), findsOneWidget);
    });

    testWidgets('容量分布卡:動作數 < 2 隱藏、>= 2 顯示', (tester) async {
      final harness = await _setUpHarness();
      final exercises = await harness.exerciseRepo.fetchAll();
      WorkoutExercise we(String id, String workoutId, int index) => _buildExercise(
        id: id,
        workoutId: workoutId,
        exerciseId: exercises[index].id,
        orderIndex: index,
        sets: [_buildSet(id: '$id-s', workoutExerciseId: id, setNumber: 1, weight: 50, reps: 5)],
      );
      final now = DateTime.now();
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'w-single',
          startedAt: now,
          totalExercises: 1,
          exercises: [we('we-s1', 'w-single', 0)],
        ),
      );
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'w-double',
          startedAt: now.subtract(const Duration(days: 1)),
          totalExercises: 2,
          exercises: [we('we-d1', 'w-double', 0), we('we-d2', 'w-double', 1)],
        ),
      );

      await _pumpHistory(tester, harness);

      await tester.tap(find.byKey(const Key('historyWorkoutCard-w-single')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workoutDetailSummaryCard')), findsOneWidget);
      expect(find.byKey(const Key('workoutDetailVolumeBreakdownCard')), findsNothing);
      expect(find.text('容量分布'), findsNothing);
      // 動作明細不受影響。
      expect(find.byKey(const Key('workoutDetailExercise-we-s1')), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('historyWorkoutCard-w-double')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workoutDetailVolumeBreakdownCard')), findsOneWidget);
      expect(find.text('容量分布'), findsOneWidget);
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
        formatVolumeKg(after.totalVolume, WeightUnit.kg),
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
        workoutRepoBuilder: (db) => _ThrowingDeleteWorkoutRepository(db, DriftExerciseRepository(db)),
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
      final deleteButton = tester.widget<IconButton>(find.byKey(const Key('workoutDetailDeleteButton')));
      expect(deleteButton.onPressed, isNotNull);

      // 回到列表頁確認該筆仍在,DB 也真的沒被刪掉。
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historyWorkoutCard-w-1')), findsOneWidget);
      final stillThere = await harness.workoutRepo.fetchById('w-1');
      expect(stillThere, isNotNull);
    });
  });

  // 波 6:override weightUnitProvider 成 lb,覆蓋「列表卡片」與「詳情頁」
  // 兩個消費群組——變異:任一處漏接 provider、恆用 kg 版格式化,這些斷言
  // 必紅。期望值一律用 formatVolumeKg/kgToDisplay 現算,不手抄係數。
  group('重量單位(lb 模式)', () {
    testWidgets('列表卡片總容量換算成 lb 顯示', (tester) async {
      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
      await harness.workoutRepo.create(
        _buildWorkout(id: 'w-lb', startedAt: DateTime.now(), totalVolume: 1234),
      );

      await _pumpHistory(tester, harness);

      expect(find.text(formatVolumeKg(1234, WeightUnit.lb)), findsWidgets);
      expect(find.text(formatVolumeKg(1234, WeightUnit.kg)), findsNothing);
    });

    testWidgets('詳情頁 summary/容量分布/動作明細換算成 lb 顯示;刪除確認對話框內容也換算', (tester) async {
      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
      final exerciseId = (await harness.exerciseRepo.fetchSystemExercises()).first.id;
      final startedAt = DateTime.now();
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'w-detail-lb',
          startedAt: startedAt,
          totalVolume: 1234,
          totalSets: 1,
          totalExercises: 1,
          exercises: [
            _buildExercise(
              id: 'we-1',
              workoutId: 'w-detail-lb',
              exerciseId: exerciseId,
              sets: [_buildSet(id: 'set-1', workoutExerciseId: 'we-1', setNumber: 1, weight: 60, reps: 8)],
            ),
          ],
        ),
      );

      await _pumpHistory(tester, harness);
      await tester.tap(find.byKey(const Key('historyWorkoutCard-w-detail-lb')));
      await tester.pumpAndSettle();

      // summary 卡總容量。
      expect(
        find.descendant(
          of: find.byKey(const Key('workoutDetailSummaryCard')),
          matching: find.text(formatVolumeKg(1234, WeightUnit.lb)),
        ),
        findsOneWidget,
      );
      // 動作明細:單組重量(60kg)換算成 lb 顯示。
      expect(
        find.descendant(
          of: find.byKey(const Key('workoutDetailExerciseList')),
          matching: find.text(formatWeightKg(60, WeightUnit.lb)),
        ),
        findsOneWidget,
      );

      // 刪除確認對話框內容也用 lb 顯示(delete_workout_dialog.dart 消費同一
      // 個 weightUnitProvider)。
      await tester.tap(find.byKey(const Key('workoutDetailDeleteButton')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('deleteWorkoutDialog')),
          matching: find.textContaining(formatVolumeKg(1234, WeightUnit.lb)),
        ),
        findsOneWidget,
      );
    });
  });
}
