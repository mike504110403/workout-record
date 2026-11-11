// DashboardPage widget seam:pump 真實頁面(repositories/provider 一律用真的,
// 只換 appDatabaseProvider 為 in-memory DB、sharedPreferencesProvider 為 mock
// prefs),斷言畫面呈現的數字/文案——不測 controller 內部欄位。
//
// 週界測試刻意用「10 天前」這種粗粒度區間(任何合理的一週定義都會落在上週)
// 做主要的本週內/外區分,額外再用一組獨立算法(逐日往回找星期一,不是複製
// dashboard_controller.dart 裡的算式)算出的精確週一邊界,驗證邊界前後各一
// 筆種子被正確排除/計入——週界算錯或範圍寫反時,這兩組測試都必須紅。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/core/theme/app_semantic_colors.dart';
import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, BodyWeight, UserGoal;
import 'package:workout_record/data/models/body_weight.dart';
import 'package:workout_record/data/models/user_goal.dart';
import 'package:workout_record/data/models/workout_template.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/body_weight_repository.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/user_goal_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/dashboard/dashboard_controller.dart';
import 'package:workout_record/features/dashboard/dashboard_page.dart';
import 'package:workout_record/features/workout/templates/applied_template.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';

import '../../data/test_helpers.dart';

// endedAt 預設為 startedAt + duration 分鐘(代表「已完成」)——波 3
// WorkoutRepository 的 fetchByDateRange/fetchRecent/countWorkouts/
// calculateTotalVolume 改為排除草稿(`endedAt IS NULL`,見
// .claude/decisions/2026-08-04-波3訓練流草稿寫穿與系統模板.md),這份測試檔
// 的種子全部代表「已完成訓練」,不是波 3 新增的草稿情境,補上 endedAt 才
// 能繼續被這些查詢計入。
Workout _buildWorkout({
  required String id,
  required DateTime startedAt,
  int duration = 60,
  double totalVolume = 1000,
  int totalSets = 10,
  int totalExercises = 3,
}) {
  final now = DateTime.now();
  return Workout(
    id: id,
    userId: testUserId,
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(minutes: duration)),
    duration: duration,
    totalVolume: totalVolume,
    totalSets: totalSets,
    totalExercises: totalExercises,
    createdAt: now,
    updatedAt: now,
  );
}

/// 獨立於 dashboard_controller.dart 算法的週一邊界計算——逐日往回找,不是
/// 複製被測程式的「今天減去 (weekday - 1) 天」算式,避免測試跟被測程式抄
/// 同一個(可能錯誤的)公式互相掩護。
DateTime _referenceWeekStart(DateTime now) {
  var day = DateTime(now.year, now.month, now.day);
  while (day.weekday != DateTime.monday) {
    day = day.subtract(const Duration(days: 1));
  }
  return day;
}

/// 修復 M1/m3 失敗路徑測試專用:模擬 `BodyWeightRepository.create` 寫入
/// DB 失敗(例如磁碟已滿、DB 被鎖)。只覆寫 create,其餘方法沿用真實實作。
class _ThrowingBodyWeightRepository extends DriftBodyWeightRepository {
  _ThrowingBodyWeightRepository(super.db);

  @override
  Future<void> create(BodyWeight bodyWeight) async {
    throw Exception('模擬體重寫入失敗(M1/m3 失敗路徑測試用)');
  }
}

/// m8 error 分支覆蓋專用:模擬 Dashboard 初始載入時查詢失敗(_load() 裡第一個
/// await 的 repository 呼叫就拋錯),讓 dashboardControllerProvider 落入
/// AsyncError,驗證 dashboard_page.dart 的 `error:` 分支真的會渲染。
class _ThrowingOnLoadBodyWeightRepository extends DriftBodyWeightRepository {
  _ThrowingOnLoadBodyWeightRepository(super.db);

  @override
  Future<BodyWeight?> getLatestWeight() async {
    throw Exception('模擬 Dashboard 載入失敗(m8 error 分支測試用)');
  }
}

/// error 分支重試路徑測試專用:只有第一次呼叫 `getLatestWeight()` 拋錯,
/// 之後恢復正常——模擬「暫時性失敗,重試就好了」的情境,用來驗證
/// dashboard_page.dart 的重試按鈕真的能讓畫面從 error 分支恢復,不是擺好看
/// 的裝飾。
class _FlakyBodyWeightRepository extends DriftBodyWeightRepository {
  _FlakyBodyWeightRepository(super.db);

  var _callCount = 0;

  @override
  Future<BodyWeight?> getLatestWeight() async {
    _callCount += 1;
    if (_callCount == 1) {
      throw Exception('模擬第一次載入失敗,重試後應恢復(error 分支重試測試用)');
    }
    return super.getLatestWeight();
  }
}

/// 記錄首頁 CTA / chip 呼叫了哪個 launcher 入口,不真的寫 DB(launcher 的實作
/// 由訓練流程切片負責,這裡只驗首頁「呼叫了誰、帶了什麼」)。
class _RecordingWorkoutController extends WorkoutController {
  final calls = <String>[];
  AppliedTemplate? lastTemplate;

  /// true 時 start 類入口拋錯,驗首頁的失敗提示。
  bool throwOnStart = false;

  @override
  Future<void> startFreeWorkout() async {
    calls.add('free');
    if (throwOnStart) throw Exception('模擬開始訓練失敗');
  }

  @override
  Future<void> startFromTemplate(AppliedTemplate template) async {
    calls.add('template');
    lastTemplate = template;
    if (throwOnStart) throw Exception('模擬開始訓練失敗');
  }
}

/// 模板 chip 彙整專用的 fetchRecent 攔截:首頁自己的「最近訓練」只取
/// [kDashboardRecentWorkoutLimit] 筆,彙整模板 id 取更多筆,以此分辨兩種呼叫。
/// [templateLookup] 非 null 時,彙整那一次呼叫改走它(可拋錯或卡住)。
class _InterceptingWorkoutRepository extends DriftWorkoutRepository {
  _InterceptingWorkoutRepository(AppDatabase db, this.templateLookup)
      : super(db, DriftExerciseRepository(db));

  final Future<List<Workout>> Function()? templateLookup;

  /// 彙整模板 id 那類呼叫(筆數超過首頁「最近訓練」)帶的 limit。
  final lookupLimits = <int>[];

  @override
  Future<List<Workout>> fetchRecent(int limit) {
    if (limit > kDashboardRecentWorkoutLimit) lookupLimits.add(limit);
    if (limit > kDashboardRecentWorkoutLimit && templateLookup != null) {
      return templateLookup!();
    }
    return super.fetchRecent(limit);
  }
}

class _DashboardHarness {
  _DashboardHarness(this.db, this.container)
      : workoutRepo = DriftWorkoutRepository(db, DriftExerciseRepository(db)),
        bodyWeightRepo = DriftBodyWeightRepository(db),
        userGoalRepo = DriftUserGoalRepository(db);

  final AppDatabase db;
  final ProviderContainer container;
  final WorkoutRepository workoutRepo;
  final BodyWeightRepository bodyWeightRepo;
  final UserGoalRepository userGoalRepo;
}

/// [extraPrefs] 疊加在預設的 `{kAppleUserIdKey: testUserId}` 之上(用於 M2
/// 換帳號測試,預先塞好 `kTestLoginUserIdPrefsKey` 讓 signInTest() 切到可
/// 預期的固定帳號,而不是隨機 UUID)。
///
/// [bodyWeightRepoBuilder] 給定時,額外把 `bodyWeightRepositoryProvider`
/// 換成它建出的 fake(用於 M1/m8 的失敗/重試路徑測試,模擬寫入失敗、查詢
/// 失敗、或先失敗後恢復)。用「傳入一個建構 repository 的 callback」而不是
/// 讓呼叫端直接傳一包 `overrides:` 清單——目前 pin 住的 riverpod 3.1.0 沒有
/// 對外 export `Override` 這個型別(`package:flutter_riverpod` 拿不到這個
/// 名字),沒辦法在函式簽章上具名引用它,這裡用 callback + `if` collection
/// element 繞開,靠型別推導組出 `overrides:` list literal,不需要點名該型別。
///
/// [disableAutoRetry] 為 true 時關掉 riverpod 內建的自動重試
/// (`ProviderContainer.defaultRetry`:provider build() 拋出 `Exception`
/// 時,框架本身就會照 200ms 起跳、指數退避的排程自動重試,最多 10 次)。
/// 用來測「dashboard_page.dart 的 error 分支重試按鈕真的有效」的測試需要
/// 這個——不關掉的話,riverpod 自己的自動重試會搶在我們斷言/按按鈕之前
/// 就把 flaky repo 重試到成功,測試斷言不到穩定的 error 畫面。
/// [weightUnit] 給定時覆寫 `weightUnitProvider`(stub 期恆回 kg,波 6
/// 顯示層改造在 lb 模式的回歸測試靠這個 override 驗證——不依賴另一位工人
/// 的持久化真身進度)。
Future<_DashboardHarness> _setUpHarness({
  Map<String, Object> extraPrefs = const {},
  BodyWeightRepository Function(AppDatabase db)? bodyWeightRepoBuilder,
  bool disableAutoRetry = false,
  WeightUnit? weightUnit,
  WorkoutController? workoutController,
  WorkoutRepository Function(AppDatabase db)? workoutRepoBuilder,
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
    retry: disableAutoRetry ? (retryCount, error) => null : null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (bodyWeightRepoBuilder != null)
        bodyWeightRepositoryProvider.overrideWithValue(bodyWeightRepoBuilder(db)),
      if (workoutRepoBuilder != null)
        workoutRepositoryProvider.overrideWithValue(workoutRepoBuilder(db)),
      if (weightUnit != null) weightUnitProvider.overrideWithValue(weightUnit),
      if (workoutController != null)
        workoutControllerProvider.overrideWith(() => workoutController),
    ],
  );
  addTearDown(container.dispose);
  return _DashboardHarness(db, container);
}

Future<void> _pumpDashboard(WidgetTester tester, _DashboardHarness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: DashboardPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<GoRouter> _pumpDashboardWithRouter(WidgetTester tester, _DashboardHarness harness) async {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(path: '/dashboard', builder: (context, state) => const DashboardPage()),
      GoRoute(
        path: '/workout',
        // launcher 以 push('/workout') 進全螢幕訓練頁(「繼續訓練」的
        // openCurrentWorkout 一定會 push;start 類入口在 recording controller 下
        // 不建草稿,launcher 不 push),測試裡需要有這條路由才不會出錯。首頁測試
        // 只守「呼叫了哪個入口、帶了哪個模板」,不斷言導到哪(導頁方式由訓練流程
        // 切片決定),所以這頁刻意沒有任何標記文字。
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/stats',
        builder: (context, state) => const Scaffold(body: Text('stats-route-marker')),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const Scaffold(body: Text('history-route-marker')),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('本週卡不含今日狀態', () {
    testWidgets('今日有訓練:不顯示「今日已完成訓練」那列(今天練過從最近訓練看得到)', (tester) async {
      final harness = await _setUpHarness();
      await harness.workoutRepo.create(
        _buildWorkout(id: 'today-1', startedAt: DateTime.now(), duration: 75, totalVolume: 5230),
      );

      await _pumpDashboard(tester, harness);

      expect(find.text('今日已完成訓練'), findsNothing);
      expect(find.byKey(const Key('todayWorkoutCard')), findsNothing);
      expect(find.byKey(const Key('noWorkoutTodayCard')), findsNothing);
      // 這筆訓練改由「最近訓練」呈現。
      expect(find.byKey(const Key('recentWorkoutRow-today-1')), findsOneWidget);
    });

    testWidgets('今日無訓練:也不顯示「今日尚未訓練」', (tester) async {
      final harness = await _setUpHarness();

      await _pumpDashboard(tester, harness);

      expect(find.text('今日尚未訓練'), findsNothing);
      expect(find.byKey(const Key('noWorkoutTodayCard')), findsNothing);
      expect(find.byKey(const Key('weekSummaryCard')), findsOneWidget);
    });

    testWidgets('本週卡沒有「查看進度」(與數據分頁重複)', (tester) async {
      final harness = await _setUpHarness();

      await _pumpDashboard(tester, harness);

      expect(find.text('查看進度'), findsNothing);
      expect(find.byKey(const Key('quickActionViewProgress')), findsNothing);
    });
  });

  group('首頁版面', () {
    testWidgets('不顯示「首頁」大標題(導覽列已標示所在分頁),也沒有 AppBar', (tester) async {
      final harness = await _setUpHarness();

      await _pumpDashboard(tester, harness);

      expect(find.text('首頁'), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SliverAppBar), findsNothing);
    });

    testWidgets('主 CTA 緊貼狀態列安全區下方 8px(無標題列佔位)', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final harness = await _setUpHarness();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 47)),
              child: child!,
            ),
            home: const DashboardPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byKey(const Key('quickActionStartWorkout'))).dy, 47 + 8);
    });
  });

  group('最新體重', () {
    testWidgets('顯示最新一筆體重;記錄體重存檔後畫面刷新為新值(走真實 repository 寫入)', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.bodyWeightRepo.create(
        BodyWeight(
          id: 'bw-old',
          userId: testUserId,
          weight: 70.0,
          measuredAt: now.subtract(const Duration(days: 3)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.bodyWeightRepo.create(
        BodyWeight(
          id: 'bw-new',
          userId: testUserId,
          // 刻意跟「等一下 UI 觸發的真實寫入」錯開至少 30 秒:Drift 的
          // dateTime() 欄位預設用「整數秒」精度存欄位(不是毫秒),用
          // `now` 會跟緊接著發生的真實寫入落在同一秒、變成兩筆
          // measuredAt 完全相同的並列——getLatestWeight() 排序在這種並列
          // 情況下由 SQLite 決定順序,不保證挑到後寫入的那筆,測試會間歇
          // 性 flaky(這裡吃過虧,見除錯記錄)。這是資料層既有的秒級精度
          // 限制,不在本波「不碰 data/」的範圍內修,測試端刻意拉開時間差
          // 避開它。
          weight: 71.2,
          measuredAt: now.subtract(const Duration(seconds: 30)),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _pumpDashboard(tester, harness);

      expect(find.text('71.2 kg'), findsOneWidget);
      expect(find.text('70.0 kg'), findsNothing);

      await tester.tap(find.byKey(const Key('quickActionRecordWeight')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bodyWeightInputField')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('bodyWeightInputField')), '82.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
      await tester.pumpAndSettle();

      // 畫面刷新為新值。
      expect(find.text('82.5 kg'), findsOneWidget);
      expect(find.text('71.2 kg'), findsNothing);

      // 直接查 repository,證明是真的寫進 DB,不是單純的本地畫面狀態。
      final latest = await harness.bodyWeightRepo.getLatestWeight();
      expect(latest?.weight, 82.5);
    });

    // 修復 M1(major):存體重失敗時先前 `_isSaving` 會永遠卡 true,欄位/
    // 按鈕全部 disable、沒有任何錯誤提示,使用者只能重開 app。改成
    // try/catch/finally 後,失敗要能:秀出錯誤、解除 disable、彈窗還開著
    // (沒有被誤 pop)。
    testWidgets('存體重失敗時:顯示錯誤 SnackBar,輸入框與按鈕解除 disable(不永久卡死)', (tester) async {
      final harness = await _setUpHarness(bodyWeightRepoBuilder: _ThrowingBodyWeightRepository.new);

      await _pumpDashboard(tester, harness);

      await tester.tap(find.byKey(const Key('quickActionRecordWeight')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bodyWeightInputField')), '82.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
      await tester.pumpAndSettle();

      // 彈窗沒有被誤 pop,錯誤訊息顯示。
      expect(find.byKey(const Key('bodyWeightInputField')), findsOneWidget);
      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);

      // _isSaving 已重置為 false:欄位可編輯、按鈕恢復可按。
      final field = tester.widget<TextField>(find.byKey(const Key('bodyWeightInputField')));
      expect(field.enabled, isTrue);
      final button = tester.widget<FilledButton>(find.byKey(const Key('saveBodyWeightButton')));
      expect(button.onPressed, isNotNull);
    });
  });

  group('目標進度', () {
    testWidgets('weeklyGoal=4、本週已練 1 次 → 25%,「不錯的開始」', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 4,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: now));

      await _pumpDashboard(tester, harness);

      expect(find.byKey(const Key('goalProgressCard')), findsOneWidget);
      expect(find.text('1 / 4 次'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('不錯的開始！繼續加油💪'), findsOneWidget);
    });

    testWidgets('weeklyGoal=4、本週已練 3 次 → 75%,「快達成目標了」', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 4,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: now));
      await harness.workoutRepo.create(_buildWorkout(id: 'w-2', startedAt: now));
      await harness.workoutRepo.create(_buildWorkout(id: 'w-3', startedAt: now));

      await _pumpDashboard(tester, harness);

      expect(find.text('3 / 4 次'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('快達成目標了！再加把勁🔥'), findsOneWidget);
    });

    testWidgets('未設定目標時顯示空狀態提示(不顯示進度卡)', (tester) async {
      final harness = await _setUpHarness();

      await _pumpDashboard(tester, harness);

      expect(find.byKey(const Key('goalEmptyState')), findsOneWidget);
      expect(find.byKey(const Key('goalProgressCard')), findsNothing);
      expect(find.text(kNoGoalMessage), findsOneWidget);
    });

    // 修復 m8 覆蓋缺口:鼓勵文案的 ==100 分支(先前只測到 <100 的「快達成」)。
    testWidgets('weeklyGoal=2、本週已練 2 次 → 100%,「太棒了！本週目標達成」', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 2,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: now));
      await harness.workoutRepo.create(_buildWorkout(id: 'w-2', startedAt: now));

      await _pumpDashboard(tester, harness);

      expect(find.text('2 / 2 次'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('太棒了！本週目標達成✨'), findsOneWidget);
    });

    // 修復 m8 覆蓋缺口:鼓勵文案的 >100 分支。
    testWidgets('weeklyGoal=1、本週已練 2 次 → 200%,「超越目標！你太強了」', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: now));
      await harness.workoutRepo.create(_buildWorkout(id: 'w-2', startedAt: now));

      await _pumpDashboard(tester, harness);

      expect(find.text('2 / 1 次'), findsOneWidget);
      expect(find.text('200%'), findsOneWidget);
      expect(find.text('超越目標！你太強了🏆'), findsOneWidget);
    });

    // 波 5 review 打回(MAJOR SP1):weeklyWorkoutGoal == 0 代表「未設定」
    // (goal_settings_page.dart 規格:目標設定頁週次數欄位留空即存 0),不是
    // 「目標剛好是 0 次」。dashboard_controller.dart 改成 `userGoal != null
    // && weeklyWorkoutGoal > 0` 才進入進度分支,0 時要跟「無 goal」一樣走
    // 空狀態——這條測試原本斷言的是舊行為(顯示「0/0 次、0%」進度卡),已
    // 依新規格改寫(變異:把 dashboard_controller.dart 的條件改回
    // `userGoal != null`,這條測試會回到舊斷言、必紅)。
    testWidgets('weeklyWorkoutGoal=0(未設定)時顯示空狀態,不是 0/0 次進度卡', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _pumpDashboard(tester, harness);

      expect(find.byKey(const Key('goalEmptyState')), findsOneWidget);
      expect(find.byKey(const Key('goalProgressCard')), findsNothing);
      expect(find.text(kNoGoalMessage), findsOneWidget);
    });
  });

  group('本週統計', () {
    testWidgets('計入本週內種子訓練,排除本週外(10 天前)的種子訓練', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.workoutRepo.create(
        _buildWorkout(id: 'in-week', startedAt: now, totalVolume: 100, totalSets: 5),
      );
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'out-of-week',
          startedAt: now.subtract(const Duration(days: 10)),
          totalVolume: 999,
          totalSets: 50,
        ),
      );

      await _pumpDashboard(tester, harness);

      final weekCountCard = find.byKey(const Key('weekWorkoutCountCard'));
      final weekVolumeCard = find.byKey(const Key('weekTotalVolumeCard'));
      // 第 3 波:本週卡的 MetricTile 把單位併在同一個 Text.rich(「1 次」「100 kg」)。
      expect(
        find.descendant(of: weekCountCard, matching: find.text('1 次')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: weekVolumeCard, matching: find.text('100 kg')),
        findsOneWidget,
      );
      // 修復 m7:先前這兩條反向斷言用 find.text 對全頁搜尋——「1099」/「2」
      // 這種數字字串理論上也可能巧合出現在畫面其他地方(例如訓練時長、體重
      // 之類的無關文字),真正該限定的是「這兩個數字不該出現在本週統計卡片
      // 裡」。比照檔內其他處,改用 find.descendant 限定卡片子樹。
      expect(
        find.descendant(of: weekVolumeCard, matching: find.text('1099 kg')),
        findsNothing,
      );
      expect(
        find.descendant(of: weekCountCard, matching: find.text('2 次')),
        findsNothing,
      );
    });

    testWidgets('精確週一邊界:下界本身(週一 00:00:00)計入,邊界前一小時排除', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      final weekStart = _referenceWeekStart(now);

      // 修復 m4:先前這裡種在 `weekStart + 1h`,只驗到「下界之後」計入,沒
      // 驗到「下界本身」(週一 00:00:00 整)是否真的落在區間內——如果實際跑
      // 測試的時間點剛好落在週一 00:00~01:00 之間,`weekStart + 1h` 反而會
      // 落到「現在」之後,被 `to: now` 的上界排除,造成 time-of-day flake。
      // 改種在 `weekStart` 本身:下界 `>=` 恆成立(不受目前是幾點影響),
      // 同時也才是真正驗證「含下界」的邊界案例。
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'just-inside',
          startedAt: weekStart,
          totalVolume: 50,
          totalSets: 1,
        ),
      );
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'just-outside',
          startedAt: weekStart.subtract(const Duration(hours: 1)),
          totalVolume: 77,
          totalSets: 1,
        ),
      );

      await _pumpDashboard(tester, harness);

      expect(
        find.descendant(
          of: find.byKey(const Key('weekWorkoutCountCard')),
          matching: find.text('1 次'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('weekTotalVolumeCard')),
          matching: find.text('50 kg'),
        ),
        findsOneWidget,
      );
    });
  });

  group('最近訓練', () {
    testWidgets('最多顯示 3 筆,排序新到舊', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      // i=0 最新(今天),i=4 最舊(4 天前)——刻意散在不同天。
      for (var i = 0; i < 5; i++) {
        await harness.workoutRepo.create(
          _buildWorkout(
            id: 'recent-$i',
            startedAt: now.subtract(Duration(days: i)),
            totalVolume: (i + 1) * 100,
          ),
        );
      }

      await _pumpDashboard(tester, harness);

      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('recentWorkoutRow-recent-$i')), findsOneWidget, reason: 'i=$i 應該出現');
      }
      expect(find.byKey(const Key('recentWorkoutRow-recent-3')), findsNothing, reason: '第 4 筆應被排除');
      expect(find.byKey(const Key('recentWorkoutRow-recent-4')), findsNothing, reason: '第 5 筆應被排除');

      // 新到舊排序:recent-0(最新)應該畫在 recent-2(最舊留下的那筆)上方。
      final topY = tester.getCenter(find.byKey(const Key('recentWorkoutRow-recent-0'))).dy;
      final bottomY = tester.getCenter(find.byKey(const Key('recentWorkoutRow-recent-2'))).dy;
      expect(topY, lessThan(bottomY));
    });
  });

  group('快速操作與導航', () {
    testWidgets('「開始訓練」呼叫 openFreeWorkout(startFreeWorkout)', (tester) async {
      final fake = _RecordingWorkoutController();
      final harness = await _setUpHarness(workoutController: fake);
      await _pumpDashboardWithRouter(tester, harness);

      await tester.tap(find.byKey(const Key('quickActionStartWorkout')));
      await tester.pumpAndSettle();

      expect(fake.calls, ['free']);
    });

    testWidgets('「查看全部」導到 /history', (tester) async {
      final harness = await _setUpHarness();
      await _pumpDashboardWithRouter(tester, harness);

      // 「查看全部」在頁面下半部,測試視窗高度有限,先捲動讓它進入可視範圍
      // 才能被 tap() 命中。
      await tester.ensureVisible(find.byKey(const Key('viewAllWorkoutsButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('viewAllWorkoutsButton')));
      await tester.pumpAndSettle();

      expect(find.text('history-route-marker'), findsOneWidget);
    });

    testWidgets('「記錄體重」開啟 bottom sheet(不導航離開首頁)', (tester) async {
      final fake = _RecordingWorkoutController();
      final harness = await _setUpHarness(workoutController: fake);
      await _pumpDashboardWithRouter(tester, harness);

      await tester.tap(find.byKey(const Key('quickActionRecordWeight')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bodyWeightInputField')), findsOneWidget);
      expect(fake.calls, isEmpty, reason: '記錄體重不該觸發任何訓練入口');
    });
  });

  group('跨表組裝', () {
    testWidgets('五區塊同時正確組裝(Users/Workouts/BodyWeights/UserGoals 跨表)', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();

      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 2,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.bodyWeightRepo.create(
        BodyWeight(
          id: 'bw-1',
          userId: testUserId,
          weight: 68.4,
          measuredAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      // 今日訓練,同時計入本週統計。
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'today',
          startedAt: now,
          duration: 50,
          totalVolume: 300,
          totalSets: 12,
          totalExercises: 4,
        ),
      );
      // 上週訓練,不該計入本週統計、也不是最近訓練列表的干擾(仍會出現在
      // fetchRecent,只是本測試不特別斷言它)。
      await harness.workoutRepo.create(
        _buildWorkout(id: 'last-week', startedAt: now.subtract(const Duration(days: 9))),
      );

      await _pumpDashboard(tester, harness);

      // 今日那筆訓練在「最近訓練」列:時長/容量/組數/動作數都在該列內。
      final todayRow = find.byKey(const Key('recentWorkoutRow-today'));
      expect(todayRow, findsOneWidget);
      expect(find.descendant(of: todayRow, matching: find.text('50 分鐘')), findsOneWidget);
      expect(find.descendant(of: todayRow, matching: find.text('300 kg')), findsOneWidget);
      expect(find.descendant(of: todayRow, matching: find.text('4 個動作 • 12 組')), findsOneWidget);
      // 最新體重。
      expect(find.text('68.4 kg'), findsOneWidget);
      // 目標進度:1/2 次 = 50%。
      expect(find.text('1 / 2 次'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      // 本週卡:只計今天那筆,不計上週那筆;有目標(2 次)時次數格併顯示「1 / 2 次」。
      expect(
        find.descendant(
          of: find.byKey(const Key('weekWorkoutCountCard')),
          matching: find.text('1 / 2 次'),
        ),
        findsOneWidget,
      );
      // 最近訓練:兩筆都會列出(fetchRecent 不分本週/上週)。
      expect(find.byKey(const Key('recentWorkoutRow-today')), findsOneWidget);
      expect(find.byKey(const Key('recentWorkoutRow-last-week')), findsOneWidget);
    });
  });

  // 修復 M2(major):sessionControllerProvider 不是 autoDispose,先前
  // dashboard_controller.dart 只在 build() 內用 ref.read 讀一次,換帳號後
  // build() 不會重跑,goalRepo.fetchByUser 永遠查前一個帳號的 userId,首頁
  // 會顯示前帳號的目標進度快取。改成 ref.watch(sessionControllerProvider)
  // 後,session 一變就會自動重新組裝整份 DashboardState。
  group('換帳號後重新整理(M2)', () {
    testWidgets('session 換成另一個使用者後,目標進度卡改用新帳號資料,不留前帳號快取', (tester) async {
      const secondUserId = 'test-user-2';
      final harness = await _setUpHarness(
        extraPrefs: {kTestLoginUserIdPrefsKey: secondUserId},
      );
      final now = DateTime.now();
      await seedTestUser(harness.db, id: secondUserId);

      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-user1',
          userId: testUserId,
          weeklyWorkoutGoal: 4,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-user2',
          userId: secondUserId,
          weeklyWorkoutGoal: 2,
          createdAt: now,
          updatedAt: now,
        ),
      );
      // 訓練次數目前不分帳號查詢(帳號隔離是另一波的決策範圍),兩個帳號
      // 看到的都會是同一個「本週 1 次」,這裡只驗證會隨帳號變動的目標進度。
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: now));

      await _pumpDashboard(tester, harness);

      // 帳號一:1/4 次 = 25%。
      expect(find.text('1 / 4 次'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);

      // 換帳號:signOut 再 signInTest。prefs 已預先塞好固定的
      // kTestLoginUserIdPrefsKey,signInTest() 會讀到既有值而非產生亂數
      // id,測試才能預期地切到「帳號二」。刻意不手動呼叫
      // dashboardControllerProvider 的 refresh()——這正是要驗證的行為:
      // 光是 session 變了,畫面就該自動反映新帳號,不需要呼叫端額外觸發。
      await harness.container.read(sessionControllerProvider.notifier).signOut();
      await harness.container.read(sessionControllerProvider.notifier).signInTest();
      await tester.pumpAndSettle();

      // 帳號二:1/2 次 = 50%,不是帳號一的 1/4 次、25% 快取。
      expect(find.text('1 / 2 次'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('1 / 4 次'), findsNothing);
      expect(find.text('25%'), findsNothing);
    });
  });

  // M3(major)的真實回歸測試(切走再切回首頁分頁時,透過 router.dart 真的
  // invalidate、重新查詢)搬到 test/features/dashboard/dashboard_shell_revisit_test.dart
  // ——那邊 pump 完整的 WorkItOutApp(真的 go_router StatefulShellRoute +
  // bottom nav),不是像這個檔案其他測試一樣繞過 router 直接 pump
  // DashboardPage。複審 r2 打回的原因:這裡先前那條「provider 被
  // invalidate 後重新查詢」測試是直接呼叫 `container.invalidate(...)`,
  // 測的是 Riverpod 自身的 invalidate 行為,不是 router.dart
  // _AppShell.onDestinationSelected 有沒有真的接上這個呼叫——複審把
  // router.dart 裡呼叫 invalidate 的那三行刪掉,這條測試照樣全綠,是假防護。
  // 純函式那半(index 對應)留在 test/router/router_redirect_test.dart。

  // m8 覆蓋缺口:dashboard_page.dart 的 `error:` 分支,以及重試按鈕真的能
  // 讓畫面從錯誤恢復(不是擺好看的裝飾按鈕)。
  group('載入失敗', () {
    testWidgets('查詢拋錯時顯示 error 分支文案', (tester) async {
      final harness = await _setUpHarness(
        bodyWeightRepoBuilder: _ThrowingOnLoadBodyWeightRepository.new,
        disableAutoRetry: true,
      );

      await _pumpDashboard(tester, harness);

      expect(find.textContaining('載入失敗'), findsOneWidget);
      expect(find.byKey(const Key('dashboardErrorRetryButton')), findsOneWidget);
      expect(find.byKey(const Key('weekSummaryCard')), findsNothing);
    });

    testWidgets('點重試按鈕後,暫時性失敗恢復,畫面回到正常呈現', (tester) async {
      final harness = await _setUpHarness(
        bodyWeightRepoBuilder: _FlakyBodyWeightRepository.new,
        disableAutoRetry: true,
      );

      await _pumpDashboard(tester, harness);

      // 第一次載入失敗,停在 error 分支。
      expect(find.textContaining('載入失敗'), findsOneWidget);
      final retryButton = find.byKey(const Key('dashboardErrorRetryButton'));
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      // 重試後 _FlakyBodyWeightRepository 第二次呼叫不再拋錯,畫面恢復成
      // 正常的 data 分支,error 文案與重試按鈕都消失。
      expect(find.textContaining('載入失敗'), findsNothing);
      expect(find.byKey(const Key('dashboardErrorRetryButton')), findsNothing);
      expect(find.byKey(const Key('weekSummaryCard')), findsOneWidget);
    });
  });

  // 波 6:重量顯示層改造——override weightUnitProvider 成 lb,驗證今日概覽
  // (總容量/當前體重)、最近訓練列表卡片、記錄體重輸入框(顯示 + 反向換算
  // 入庫)三個消費點。變異:任一處漏接 provider、恆用 kg 版格式化,這些斷言
  // 必紅(期望值寫死字面,不用 `kgToDisplay` 現算)。
  group('重量單位(lb 模式)', () {
    testWidgets('最近訓練列的總容量/體重卡的當前體重換算成 lb 顯示,字尾正確', (tester) async {
      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'today-lb',
          startedAt: DateTime.now(),
          duration: 75,
          totalVolume: 5230,
          totalSets: 24,
          totalExercises: 6,
        ),
      );
      final now = DateTime.now();
      await harness.bodyWeightRepo.create(
        BodyWeight(
          id: 'bw-lb',
          userId: testUserId,
          weight: 71.2,
          measuredAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _pumpDashboard(tester, harness);

      // 期望值寫死字面(5230 kg × 2.20462 = 11530.2、71.2 kg × 2.20462 = 156.97),
      // 不用正式換算函式現算,免得換算係數錯了測試跟著一起錯。
      const expectedVolume = '11530 lb';
      const expectedWeight = '157.0 lb';
      // 總容量字串可能同時出現在本週卡,限定在最近訓練列子樹內斷言。
      expect(
        find.descendant(
          of: find.byKey(const Key('recentWorkoutRow-today-lb')),
          matching: find.text(expectedVolume),
        ),
        findsOneWidget,
      );
      expect(find.text(expectedWeight), findsOneWidget);
      // kg 版字串不該殘留(排除漏接 provider、恆用 kg 的變異)。
      expect(find.text('5230 kg'), findsNothing);
      expect(find.text('71.2 kg'), findsNothing);
    });

    testWidgets('最近訓練列表卡片總容量換算成 lb 顯示', (tester) async {
      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'recent-lb',
          startedAt: DateTime.now().subtract(const Duration(days: 1)),
          totalVolume: 1000,
        ),
      );

      await _pumpDashboard(tester, harness);

      const expectedVolume = '2205 lb'; // 1000 kg × 2.20462 = 2204.62,寫死字面
      // 第 3 波:本週卡的總容量格(「2205 lb」)可能與列表同字串,限定在最近訓練列。
      expect(
        find.descendant(
          of: find.byKey(const Key('recentWorkoutRow-recent-lb')),
          matching: find.text(expectedVolume),
        ),
        findsOneWidget,
      );
      expect(find.text('1000 kg'), findsNothing);
    });

    testWidgets('記錄體重輸入框:label 顯示 lb,輸入 220.5 lb 換算存成約 100kg', (tester) async {
      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);

      await _pumpDashboard(tester, harness);

      await tester.tap(find.byKey(const Key('quickActionRecordWeight')));
      await tester.pumpAndSettle();

      expect(find.text('體重 (lb)'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('bodyWeightInputField')), '220.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveBodyWeightButton')));
      await tester.pumpAndSettle();

      final latest = await harness.bodyWeightRepo.getLatestWeight();
      expect(latest, isNotNull);
      // 期望值用 displayToKg 現算,不手抄係數——220.5 / kLbPerKg ≈
      // 100.017kg(220.5lb 本身就不是剛好 100kg 換算出來的整數,誤差界只
      // 針對「這個換算函式本身」的浮點捨入,給 0.001kg 足夠寬容。
      expect(latest!.weight, closeTo(displayToKg(220.5, WeightUnit.lb), 0.001));
      // Drift dateTime 欄位是秒級精度,weight 是 REAL 欄位不受影響,但保留
      // 較寬鬆的「大約 100kg」語意斷言(brief 範例的驗收語意),誤差界對齊
      // 220.5lb 與 100kg 之間的實際換算差(約 0.017kg)。
      expect(latest.weight, closeTo(100.0, 0.02));
    });
  });

  // 第 3 波 A:首頁改版。
  group('主 CTA', () {
    testWidgets('沒有進行中訓練:全寬主 CTA 顯示「開始訓練」,點了呼叫 startFreeWorkout', (tester) async {
      final fake = _RecordingWorkoutController();
      final harness = await _setUpHarness(workoutController: fake);
      await _pumpDashboardWithRouter(tester, harness);

      final cta = find.byKey(const Key('quickActionStartWorkout'));
      expect(cta, findsOneWidget);
      expect(find.descendant(of: cta, matching: find.text('開始訓練')), findsOneWidget);
      expect(find.text('繼續訓練'), findsNothing);
      // 全寬:CTA 寬度等於頁面內容寬(視窗寬 800 扣左右各 16)。
      expect(tester.getSize(cta).width, 800 - 32);

      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(fake.calls, ['free']);
    });

    testWidgets('有進行中訓練草稿:主 CTA 變成「繼續訓練」,且不再開新訓練', (tester) async {
      final fake = _RecordingWorkoutController();
      final harness = await _setUpHarness(workoutController: fake);
      final now = DateTime.now();
      // endedAt 為 null = 進行中草稿。
      await harness.workoutRepo.create(
        Workout(
          id: 'draft-1',
          userId: testUserId,
          startedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _pumpDashboardWithRouter(tester, harness);

      final cta = find.byKey(const Key('quickActionStartWorkout'));
      expect(find.descendant(of: cta, matching: find.text('繼續訓練')), findsOneWidget);
      expect(find.text('開始訓練'), findsNothing);

      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(fake.calls, isEmpty, reason: '繼續訓練走 openCurrentWorkout,不呼叫 startFreeWorkout');
    });

    testWidgets('開始訓練失敗:顯示 SnackBar「無法開始訓練,請稍後再試」,頁面不崩', (tester) async {
      final fake = _RecordingWorkoutController()..throwOnStart = true;
      final harness = await _setUpHarness(workoutController: fake);
      await _pumpDashboardWithRouter(tester, harness);

      expect(find.text('無法開始訓練,請稍後再試'), findsNothing);
      await tester.tap(find.byKey(const Key('quickActionStartWorkout')));
      await tester.pumpAndSettle();

      expect(fake.calls, ['free']);
      expect(find.text('無法開始訓練,請稍後再試'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // 失敗後按鈕仍可再按(沒有被卡成載入中)。
      expect(find.byKey(const Key('quickActionStartWorkout')), findsOneWidget);
    });
  });

  group('最近用的模板 chip', () {
    Future<void> seedTemplates(_DashboardHarness harness, int count) async {
      final now = DateTime.now();
      final repo = harness.container.read(templateRepositoryProvider);
      for (var i = 0; i < count; i++) {
        await repo.create(
          WorkoutTemplate(
            id: 'tpl-$i',
            userId: testUserId,
            name: '模板$i',
            exercises: const [],
            createdAt: now.add(Duration(seconds: i)),
            updatedAt: now.add(Duration(seconds: i)),
          ),
        );
      }
    }

    Finder chips() => find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('recentTemplateChip-'),
        );

    testWidgets('沒有任何模板:整列不顯示', (tester) async {
      // 系統模板由 DB 種子建立,測試 DB 若有種子就刪光,確保「完全沒模板」。
      final harness = await _setUpHarness();
      await harness.db.delete(harness.db.templates).go();
      await _pumpDashboard(tester, harness);

      expect(find.byKey(const Key('recentTemplatesRow')), findsNothing);
      expect(find.text('最近用的模板'), findsNothing);
      expect(chips(), findsNothing);
    });

    testWidgets('有模板但沒有使用紀錄:列出前幾個,最多 4 個', (tester) async {
      final harness = await _setUpHarness();
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 6);
      await _pumpDashboard(tester, harness);

      // 沒有使用紀錄:列的是模板清單,標題不能說「最近用的」。
      expect(find.text('模板'), findsOneWidget);
      expect(find.text('最近用的模板'), findsNothing);
      expect(chips(), findsNWidgets(4));
    });

    testWidgets('有使用紀錄:依最近使用排序(新到舊),只列用過的,自由訓練略過', (tester) async {
      final harness = await _setUpHarness();
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 6);
      final now = DateTime.now();
      Workout used(String id, String? templateId, int daysAgo) {
        final startedAt = now.subtract(Duration(days: daysAgo));
        return Workout(
          id: id,
          userId: testUserId,
          templateId: templateId,
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(minutes: 30)),
          duration: 30,
          createdAt: now,
          updatedAt: now,
        );
      }

      await harness.workoutRepo.create(used('w-a', 'tpl-3', 5));
      await harness.workoutRepo.create(used('w-free', null, 3));
      await harness.workoutRepo.create(used('w-b', 'tpl-1', 2));
      await harness.workoutRepo.create(used('w-c', 'tpl-3', 1)); // tpl-3 再用一次:仍只出現一個 chip
      await _pumpDashboard(tester, harness);

      expect(chips(), findsNWidgets(2));
      expect(find.text('最近用的模板'), findsOneWidget);
      expect(find.text('模板'), findsNothing);
      expect(find.byKey(const Key('recentTemplateChip-tpl-0')), findsNothing);
      final first = tester.getTopLeft(find.byKey(const Key('recentTemplateChip-tpl-3'))).dx;
      final second = tester.getTopLeft(find.byKey(const Key('recentTemplateChip-tpl-1'))).dx;
      expect(first, lessThan(second), reason: 'tpl-3 最近用過,排在前面');
    });

    testWidgets('用過超過 4 種模板:最多 4 個 chip', (tester) async {
      final harness = await _setUpHarness();
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 6);
      final now = DateTime.now();
      for (var i = 0; i < 6; i++) {
        final startedAt = now.subtract(Duration(days: 6 - i));
        await harness.workoutRepo.create(
          Workout(
            id: 'w-$i',
            userId: testUserId,
            templateId: 'tpl-$i',
            startedAt: startedAt,
            endedAt: startedAt.add(const Duration(minutes: 30)),
            duration: 30,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await _pumpDashboard(tester, harness);

      expect(chips(), findsNWidgets(4));
      // 最近 4 個:tpl-5、4、3、2。
      expect(find.byKey(const Key('recentTemplateChip-tpl-5')), findsOneWidget);
      expect(find.byKey(const Key('recentTemplateChip-tpl-2')), findsOneWidget);
      expect(find.byKey(const Key('recentTemplateChip-tpl-1')), findsNothing);
    });

    testWidgets('點 chip:呼叫 startFromTemplate 帶入該模板', (tester) async {
      final fake = _RecordingWorkoutController();
      final harness = await _setUpHarness(workoutController: fake);
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 2);
      await _pumpDashboardWithRouter(tester, harness);

      await tester.tap(find.byKey(const Key('recentTemplateChip-tpl-1')));
      await tester.pumpAndSettle();

      expect(fake.calls, ['template']);
      expect(fake.lastTemplate?.templateId, 'tpl-1');
      expect(fake.lastTemplate?.templateName, '模板1');
    });

    testWidgets('點 chip 開始訓練失敗:顯示 SnackBar', (tester) async {
      final fake = _RecordingWorkoutController()..throwOnStart = true;
      final harness = await _setUpHarness(workoutController: fake);
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 2);
      await _pumpDashboardWithRouter(tester, harness);

      await tester.tap(find.byKey(const Key('recentTemplateChip-tpl-1')));
      await tester.pumpAndSettle();

      expect(fake.calls, ['template']);
      expect(find.text('無法開始訓練,請稍後再試'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    Future<void> seedUsed(_DashboardHarness harness, String id, String? templateId, int daysAgo) {
      final now = DateTime.now();
      final startedAt = now.subtract(Duration(days: daysAgo));
      return harness.workoutRepo.create(
        Workout(
          id: id,
          userId: testUserId,
          templateId: templateId,
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(minutes: 30)),
          duration: 30,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    testWidgets('用過但已刪除的模板被略過,其餘照使用順序列出', (tester) async {
      final harness = await _setUpHarness();
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 3);
      await seedUsed(harness, 'w-a', 'tpl-0', 3);
      await seedUsed(harness, 'w-b', 'tpl-2', 2); // tpl-2 稍後被刪除
      await seedUsed(harness, 'w-c', 'tpl-1', 1);
      await harness.container.read(templateRepositoryProvider).delete('tpl-2');
      await _pumpDashboard(tester, harness);

      expect(chips(), findsNWidgets(2));
      expect(find.byKey(const Key('recentTemplateChip-tpl-2')), findsNothing);
      final first = tester.getTopLeft(find.byKey(const Key('recentTemplateChip-tpl-1'))).dx;
      final second = tester.getTopLeft(find.byKey(const Key('recentTemplateChip-tpl-0'))).dx;
      expect(first, lessThan(second));
      expect(find.text('最近用的模板'), findsOneWidget);
    });

    testWidgets('用過的模板全被刪除:走 fallback,標題改「模板」', (tester) async {
      final harness = await _setUpHarness();
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 3);
      await seedUsed(harness, 'w-a', 'tpl-0', 2);
      await seedUsed(harness, 'w-b', 'tpl-1', 1);
      final repo = harness.container.read(templateRepositoryProvider);
      await repo.delete('tpl-0');
      await repo.delete('tpl-1');
      await _pumpDashboard(tester, harness);

      expect(chips(), findsOneWidget);
      expect(find.byKey(const Key('recentTemplateChip-tpl-2')), findsOneWidget);
      expect(find.text('模板'), findsOneWidget);
      expect(find.text('最近用的模板'), findsNothing);
    });

    testWidgets('fallback:個人模板排在系統模板前,且不會因為系統模板而擠掉個人模板', (tester) async {
      // 不清系統模板:DB 種子帶有多個系統模板,個人模板必須排在它們前面。
      final harness = await _setUpHarness();
      await seedTemplates(harness, 2);
      final all = await harness.container.read(templateRepositoryProvider).fetchSystemTemplates();
      expect(all.length, greaterThanOrEqualTo(2), reason: '測試前提:種子有系統模板');
      await _pumpDashboard(tester, harness);

      expect(chips(), findsNWidgets(4));
      final personal0 = tester.getTopLeft(find.byKey(const Key('recentTemplateChip-tpl-0'))).dx;
      final personal1 = tester.getTopLeft(find.byKey(const Key('recentTemplateChip-tpl-1'))).dx;
      expect(personal0, lessThan(personal1));
      // 其餘兩個是系統模板,都排在個人模板之後。
      final systemChips = [
        for (final t in all.take(2)) tester.getTopLeft(find.byKey(Key('recentTemplateChip-${t.id}'))).dx,
      ];
      for (final dx in systemChips) {
        expect(dx, greaterThan(personal1));
      }
    });

    testWidgets('使用紀錄查詢失敗:chip 列不顯示、不報錯,主 CTA 照常', (tester) async {
      final harness = await _setUpHarness(
        // 關掉 riverpod 自動重試,否則重試排程的 Timer 會殘留到測試結束。
        disableAutoRetry: true,
        workoutRepoBuilder: (db) =>
            _InterceptingWorkoutRepository(db, () async => throw Exception('模擬彙整失敗')),
      );
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 2);
      await _pumpDashboard(tester, harness);

      expect(find.byKey(const Key('quickActionStartWorkout')), findsOneWidget);
      expect(find.byKey(const Key('recentTemplatesRow')), findsNothing);
      expect(chips(), findsNothing);
      expect(find.text('載入失敗，請稍後再試'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('使用紀錄還沒查回來:主 CTA 先顯示、不等它;查回來後 chip 才出現', (tester) async {
      final pending = Completer<List<Workout>>();
      late _InterceptingWorkoutRepository repo;
      final harness = await _setUpHarness(
        workoutRepoBuilder: (db) =>
            repo = _InterceptingWorkoutRepository(db, () => pending.future),
      );
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 2);
      await _pumpDashboard(tester, harness);

      expect(find.byKey(const Key('quickActionStartWorkout')), findsOneWidget);
      expect(find.byKey(const Key('weekSummaryCard')), findsOneWidget);
      expect(chips(), findsNothing);

      pending.complete(const []);
      await tester.pumpAndSettle();
      expect(chips(), findsNWidgets(2));
      // 回看 10 筆(雲端版每筆都巢狀抓全部動作與組,不能放大),且只查一次。
      expect(repo.lookupLimits, [10]);
    });

    testWidgets('dashboard 重新載入(refresh / invalidate)會帶動最近用的模板更新', (tester) async {
      final harness = await _setUpHarness();
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 3);
      await seedUsed(harness, 'w-a', 'tpl-0', 3);
      await _pumpDashboard(tester, harness);
      expect(chips(), findsOneWidget);
      expect(find.byKey(const Key('recentTemplateChip-tpl-0')), findsOneWidget);

      await seedUsed(harness, 'w-b', 'tpl-1', 2);
      await harness.container.read(dashboardControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(chips(), findsNWidgets(2));
      expect(find.byKey(const Key('recentTemplateChip-tpl-1')), findsOneWidget);

      // 訓練完成等情境走 invalidate(router.dart),同樣要更新。
      await seedUsed(harness, 'w-c', 'tpl-2', 1);
      harness.container.invalidate(dashboardControllerProvider);
      await tester.pumpAndSettle();
      expect(chips(), findsNWidgets(3));
      expect(find.byKey(const Key('recentTemplateChip-tpl-2')), findsOneWidget);
    });

    testWidgets('下拉刷新一併刷新模板清單:別處新增的模板出現在 chip 列', (tester) async {
      final harness = await _setUpHarness();
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 1);
      await _pumpDashboard(tester, harness);
      expect(chips(), findsOneWidget);

      // 繞過 TemplatesController 直接寫 repository,模擬別處(例如其他分頁)新增。
      final now = DateTime.now();
      await harness.container.read(templateRepositoryProvider).create(
            WorkoutTemplate(
              id: 'tpl-new',
              userId: testUserId,
              name: '新模板',
              exercises: const [],
              createdAt: now,
              updatedAt: now,
            ),
          );
      await tester.fling(find.byType(CustomScrollView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recentTemplateChip-tpl-new')), findsOneWidget);
    });

    testWidgets('有進行中草稿:不顯示模板 chip(避免點了只是回到草稿)', (tester) async {
      final harness = await _setUpHarness();
      await harness.db.delete(harness.db.templates).go();
      await seedTemplates(harness, 2);
      final now = DateTime.now();
      await harness.workoutRepo.create(
        Workout(id: 'draft-1', userId: testUserId, startedAt: now, createdAt: now, updatedAt: now),
      );
      await _pumpDashboard(tester, harness);

      expect(find.text('繼續訓練'), findsOneWidget);
      expect(chips(), findsNothing);
    });
  });

  group('本週卡(今日概覽與本週統計合併)', () {
    testWidgets('舊的「今日概覽」「本週統計」標題消失,只有一張本週卡(次數、容量、目標進度)', (tester) async {
      final harness = await _setUpHarness();
      await _pumpDashboard(tester, harness);

      expect(find.text('今日概覽'), findsNothing);
      expect(find.text('本週統計'), findsNothing);
      expect(find.byKey(const Key('weekSummaryCard')), findsOneWidget);
      expect(find.text('本週'), findsOneWidget);
      // 週次數、容量格與今日狀態都在同一張卡裡。
      final card = find.byKey(const Key('weekSummaryCard'));
      expect(find.descendant(of: card, matching: find.byKey(const Key('weekWorkoutCountCard'))), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const Key('weekTotalVolumeCard'))), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const Key('goalEmptyState'))), findsOneWidget);
    });

    testWidgets('數字正確:本週 2 次、容量 700、目標 4 次 → 次數格「2 / 4 次」、容量「700 kg」、50%', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 4,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.workoutRepo.create(_buildWorkout(id: 'w-a', startedAt: now, totalVolume: 300));
      await harness.workoutRepo.create(_buildWorkout(id: 'w-b', startedAt: now, totalVolume: 400));
      // 本週之外(10 天前)不計。
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'w-old',
          startedAt: now.subtract(const Duration(days: 10)),
          totalVolume: 9000,
        ),
      );

      await _pumpDashboard(tester, harness);

      final card = find.byKey(const Key('weekSummaryCard'));
      expect(
        find.descendant(
          of: find.byKey(const Key('weekWorkoutCountCard')),
          matching: find.text('2 / 4 次'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('weekTotalVolumeCard')),
          matching: find.text('700 kg'),
        ),
        findsOneWidget,
      );
      expect(find.descendant(of: card, matching: find.text('50%')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const Key('goalProgressCard'))), findsOneWidget);
    });

    testWidgets('目標進度條:未達標用 primary,達標(>=100%)用 success 語意色', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 2,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.workoutRepo.create(_buildWorkout(id: 'w-1', startedAt: now));
      await _pumpDashboard(tester, harness);

      final context = tester.element(find.byType(DashboardPage));
      final scheme = Theme.of(context).colorScheme;
      LinearProgressIndicator bar() => tester.widget<LinearProgressIndicator>(
            find.descendant(
              of: find.byKey(const Key('goalProgressCard')),
              matching: find.byType(LinearProgressIndicator),
            ),
          );
      expect(bar().color, scheme.primary);

      await harness.workoutRepo.create(_buildWorkout(id: 'w-2', startedAt: now));
      harness.container.invalidate(dashboardControllerProvider);
      await tester.pumpAndSettle();

      final success = AppSemanticColors.light.success;
      expect(bar().color, success);
    });
  });

  group('體重卡近 7 天變化', () {
    BodyWeight weightAt(String id, double kg, DateTime at) => BodyWeight(
          id: id,
          userId: testUserId,
          weight: kg,
          measuredAt: at,
          createdAt: at,
          updatedAt: at,
        );

    testWidgets('單列:體重、近 7 天變化與新增 icon 在同一水平列,卡片高度精簡', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.bodyWeightRepo.create(weightAt('bw-a', 70.0, now.subtract(const Duration(days: 3))));
      await harness.bodyWeightRepo.create(weightAt('bw-b', 71.2, now.subtract(const Duration(seconds: 30))));

      await _pumpDashboard(tester, harness);

      final card = find.byKey(const Key('bodyWeightMiniCard'));
      final weightY = tester.getCenter(find.text('71.2 kg')).dy;
      final changeY = tester.getCenter(find.byKey(const Key('bodyWeightWeekChange'))).dy;
      final addY = tester.getCenter(find.byKey(const Key('quickActionRecordWeight'))).dy;
      expect(changeY, closeTo(weightY, 1));
      expect(addY, closeTo(weightY, 1));
      // 單列:高度 = 新增 icon 鈕(48)+ 卡片上下留白(共 64),遠小於舊版兩行排版(約 100)。
      expect(tester.getSize(card).height, lessThanOrEqualTo(64));
      // 舊的「當前體重」小標與文字按鈕「記錄體重」已移除,新增入口改為 icon。
      expect(find.text('當前體重'), findsNothing);
      expect(tester.widget(find.byKey(const Key('quickActionRecordWeight'))), isA<IconButton>());
    });

    testWidgets('7 天內有兩筆以上:顯示最新減最早(▲1.2)', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.bodyWeightRepo.create(weightAt('bw-a', 70.0, now.subtract(const Duration(days: 3))));
      await harness.bodyWeightRepo.create(weightAt('bw-b', 71.2, now.subtract(const Duration(seconds: 30))));
      // 8 天前的紀錄在區間外,不參與變化計算。
      await harness.bodyWeightRepo.create(weightAt('bw-old', 60.0, now.subtract(const Duration(days: 8))));

      await _pumpDashboard(tester, harness);

      expect(find.text('71.2 kg'), findsOneWidget);
      expect(find.text('近 7 天 \u25B21.2'), findsOneWidget);
    });

    testWidgets('體重下降:顯示向下箭頭(▼0.8)', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.bodyWeightRepo.create(weightAt('bw-a', 70.0, now.subtract(const Duration(days: 5))));
      await harness.bodyWeightRepo.create(weightAt('bw-b', 69.2, now.subtract(const Duration(seconds: 30))));

      await _pumpDashboard(tester, harness);

      expect(find.text('近 7 天 \u25BC0.8'), findsOneWidget);
    });

    testWidgets('區間內只有一筆、或完全沒有紀錄:算不出變化,顯示 —', (tester) async {
      final harness = await _setUpHarness();
      await _pumpDashboard(tester, harness);
      expect(find.text('近 7 天 —'), findsOneWidget);
      expect(find.text('尚未記錄'), findsOneWidget);

      final now = DateTime.now();
      await harness.bodyWeightRepo.create(weightAt('bw-a', 70.0, now.subtract(const Duration(seconds: 30))));
      // 區間外的舊紀錄不補足第二筆。
      await harness.bodyWeightRepo.create(weightAt('bw-old', 65.0, now.subtract(const Duration(days: 20))));
      harness.container.invalidate(dashboardControllerProvider);
      await tester.pumpAndSettle();

      expect(find.text('70.0 kg'), findsOneWidget);
      expect(find.text('近 7 天 —'), findsOneWidget);
    });

    testWidgets('lb 模式:變化量依單位換算(▲1.2 kg → ▲2.6)', (tester) async {
      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
      final now = DateTime.now();
      await harness.bodyWeightRepo.create(weightAt('bw-a', 70.0, now.subtract(const Duration(days: 2))));
      await harness.bodyWeightRepo.create(weightAt('bw-b', 71.2, now.subtract(const Duration(seconds: 30))));

      await _pumpDashboard(tester, harness);

      // 1.2 kg × 2.20462 = 2.645 → 2.6;期望值寫死,不用正式換算函式算。
      expect(find.text('近 7 天 \u25B22.6'), findsOneWidget);
    });
  });

  group('窄螢幕不溢位', () {
    testWidgets('360 寬、字體 1.5 倍、5 位數容量與 lb 單位:各卡不拋 overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = await _setUpHarness(weightUnit: WeightUnit.lb);
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 14,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.bodyWeightRepo.create(
        BodyWeight(
          id: 'bw-1',
          userId: testUserId,
          weight: 120.5,
          measuredAt: now.subtract(const Duration(days: 2)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.bodyWeightRepo.create(
        BodyWeight(
          id: 'bw-2',
          userId: testUserId,
          weight: 118.0,
          measuredAt: now.subtract(const Duration(seconds: 30)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await harness.workoutRepo.create(
        _buildWorkout(
          id: 'big',
          startedAt: now,
          duration: 125,
          totalVolume: 98765,
          totalSets: 120,
          totalExercises: 15,
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: harness.container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const DashboardPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // RenderFlex overflow 會被 flutter_test 當成例外攔下;走到這裡且沒有例外即通過。
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('weekSummaryCard')), findsOneWidget);
      expect(find.byKey(const Key('bodyWeightMiniCard')), findsOneWidget);
    });
  });
}
