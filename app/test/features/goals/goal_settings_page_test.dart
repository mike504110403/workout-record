// GoalSettingsPage widget seam:pump 真實頁面(repositories/provider 一律用
// 真的,只換 appDatabaseProvider 為 in-memory DB、sharedPreferencesProvider
// 為 mock prefs),斷言表單呈現/存檔行為與 DB 落地結果——不測 controller
// 內部欄位。頁面一律被 push 進一個有底層路由的 Navigator(同真實情境:
// GoalSettingsPage 永遠是被別的頁面 push 進來,不是 app 唯一路由),讓
// `save()` 內的 `Navigator.pop()` 有東西可以彈回去。
//
// 變異清單(逐規則列,每條都有對應斷言守住):
//   - 拔掉 createOrUpdate 呼叫必紅:「首次進頁」直接查 DB 斷言新增了一筆,
//     兩欄正確。
//   - 存檔改成整筆重建預設值必紅:「已有 goal」種一筆六肌群有值、
//     restDayReminder=true 的既有 goal,存檔後除斷言週次數改變外,額外
//     斷言 volumeGoals 六個欄位與 restDayReminder 沒被清空/重置。
//   - 目標體重存 0 而非 null 必紅:「目標體重留空」種一筆有 targetWeight
//     的既有 goal,清空欄位存檔後直接查 DB 斷言 targetWeight 是 null
//     (不是 0.0)。
//   - 值域不擋必紅:「值域擋下」分別打超界的週次數/體重,斷言錯誤文字
//     出現且存檔按鈕 onPressed 為 null(按不下去)。
//   - 失敗時卡死/誤 pop 必紅:「存檔失敗」用 throwing repository,斷言
//     顯示錯誤 SnackBar、頁面沒被 pop、欄位與按鈕解除 disable。
//   - 拔掉 bodyWeightTabControllerProvider invalidate 必紅:「體重頁目標
//     失效」直接在 container 層級驗證存檔後該 provider 重新查詢出新
//     targetWeight(dashboardControllerProvider 那一路的失效由
//     test/features/dashboard/goal_navigation_test.dart 的端對端返回流程
//     覆蓋,那邊順便也覆蓋 Dashboard 導航入口本身)。
//   - 拔掉 GoalSettingsController.save() 內的 `ref.invalidateSelf()` 必紅
//     (review 打回 MAJOR S1):「存檔後再次進頁」斷言存檔返回後不重開
//     app、直接再次進頁,表單 prefill 的是剛存的新值,不是存檔前的舊快取。
//   - 初次載入 error/重試分支零覆蓋必紅(review 打回,升級為必修 S2):
//     「載入失敗」group 兩個測試,分別守住「查詢拋錯要顯示 error 分支＋
//     重試按鈕」「按重試按鈕要能從暫時性失敗恢復」。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart' hide UserGoal;
import 'package:workout_record/data/models/user_goal.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/user_goal_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/goals/goal_settings_page.dart';
import 'package:workout_record/features/stats/body_weight/body_weight_controller.dart';

import '../../data/test_helpers.dart';

/// 失敗路徑用:只覆寫 `createOrUpdate`,其餘方法(含 `fetchByUser`,頁面初次
/// 載入需要它)沿用真實實作(仿 dashboard_page_test.dart 的
/// `_ThrowingBodyWeightRepository` 慣例)。
class _ThrowingUserGoalRepository extends UserGoalRepository {
  _ThrowingUserGoalRepository(super.db);

  @override
  Future<UserGoal> createOrUpdate(UserGoal userGoal) async {
    throw Exception('模擬目標存檔失敗(失敗路徑測試用)');
  }
}

/// 初次載入失敗路徑用:`build()` 內第一個 await 的 `fetchByUser()` 就拋錯,
/// 讓 `goalSettingsControllerProvider` 落入 `AsyncError`(仿
/// dashboard_page_test.dart 的 `_ThrowingOnLoadBodyWeightRepository`)。
class _ThrowingOnLoadUserGoalRepository extends UserGoalRepository {
  _ThrowingOnLoadUserGoalRepository(super.db);

  @override
  Future<UserGoal?> fetchByUser(String userId) async {
    throw Exception('模擬目標載入失敗(失敗路徑測試用)');
  }
}

/// 重試恢復路徑用:只有第一次呼叫 `fetchByUser()` 拋錯,之後恢復正常——
/// 模擬「暫時性失敗,重試就好了」的情境(仿 dashboard_page_test.dart 的
/// `_FlakyBodyWeightRepository`)。
class _FlakyUserGoalRepository extends UserGoalRepository {
  _FlakyUserGoalRepository(super.db);

  var _callCount = 0;

  @override
  Future<UserGoal?> fetchByUser(String userId) async {
    _callCount += 1;
    if (_callCount == 1) {
      throw Exception('模擬第一次載入失敗,重試後應恢復(失敗路徑測試用)');
    }
    return super.fetchByUser(userId);
  }
}

class _Harness {
  _Harness(this.db, this.container) : userGoalRepo = UserGoalRepository(db);

  final AppDatabase db;
  final ProviderContainer container;
  final UserGoalRepository userGoalRepo;
}

/// [disableAutoRetry] 為 true 時關掉 riverpod 內建的自動重試(理由同
/// dashboard_page_test.dart 的同名參數:`build()` 拋出 `Exception` 時框架
/// 本身就會自動重試,不關掉的話 flaky repo 會被框架搶在斷言/按重試按鈕之前
/// 就自動重試成功,測試斷言不到穩定的 error 畫面)。
Future<_Harness> _setUpHarness({
  UserGoalRepository Function(AppDatabase db)? userGoalRepoBuilder,
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
      if (userGoalRepoBuilder != null)
        userGoalRepositoryProvider.overrideWithValue(userGoalRepoBuilder(db)),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(db, container);
}

/// push 一個有底層路由的 Navigator,`GoalSettingsPage` 被 push 上去——
/// `save()` 內的 `Navigator.pop()` 才有上一頁可以彈回去(同真實情境:一律
/// 是被 Dashboard push 進來,不是 app 唯一路由)。
Future<void> _pushGoalSettingsPage(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('openGoalSettingsButton'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const GoalSettingsPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('openGoalSettingsButton')));
  await tester.pumpAndSettle();
}

void main() {
  group('首次進頁(無既有 goal)', () {
    testWidgets('欄位空/預設 → 存檔 → DB 出現一筆,兩欄正確', (tester) async {
      final harness = await _setUpHarness();
      await _pushGoalSettingsPage(tester, harness);

      final weeklyFieldBefore =
          tester.widget<TextField>(find.byKey(const Key('weeklyWorkoutGoalField')));
      expect(weeklyFieldBefore.controller?.text, '');
      final weightFieldBefore =
          tester.widget<TextField>(find.byKey(const Key('targetWeightField')));
      expect(weightFieldBefore.controller?.text, '');

      await tester.enterText(find.byKey(const Key('weeklyWorkoutGoalField')), '5');
      await tester.enterText(find.byKey(const Key('targetWeightField')), '72.5');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveGoalSettingsButton')));
      await tester.pumpAndSettle();

      // 存檔成功後 pop 回上一頁。
      expect(find.byKey(const Key('openGoalSettingsButton')), findsOneWidget);
      expect(find.byType(GoalSettingsPage), findsNothing);

      final saved = await harness.userGoalRepo.fetchByUser(testUserId);
      expect(saved, isNotNull);
      expect(saved!.weeklyWorkoutGoal, 5);
      expect(saved.targetWeight, 72.5);
    });
  });

  group('已有 goal', () {
    testWidgets('帶入現值 → 改週次數存檔 → 六肌群等其餘欄位原值不變', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      const existingVolumeGoals = VolumeGoals(
        chest: 500,
        back: 480,
        legs: 700,
        shoulders: 200,
        arms: 150,
        core: 100,
      );
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 3,
          targetWeight: 68.0,
          volumeGoals: existingVolumeGoals,
          restDayReminder: true,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _pushGoalSettingsPage(tester, harness);

      final weeklyField =
          tester.widget<TextField>(find.byKey(const Key('weeklyWorkoutGoalField')));
      expect(weeklyField.controller?.text, '3');
      final weightField = tester.widget<TextField>(find.byKey(const Key('targetWeightField')));
      expect(weightField.controller?.text, '68.0');

      await tester.enterText(find.byKey(const Key('weeklyWorkoutGoalField')), '6');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveGoalSettingsButton')));
      await tester.pumpAndSettle();

      final saved = await harness.userGoalRepo.fetchByUser(testUserId);
      expect(saved, isNotNull);
      expect(saved!.weeklyWorkoutGoal, 6);
      expect(saved.targetWeight, 68.0);
      expect(saved.restDayReminder, isTrue);
      expect(saved.volumeGoals.chest, existingVolumeGoals.chest);
      expect(saved.volumeGoals.back, existingVolumeGoals.back);
      expect(saved.volumeGoals.legs, existingVolumeGoals.legs);
      expect(saved.volumeGoals.shoulders, existingVolumeGoals.shoulders);
      expect(saved.volumeGoals.arms, existingVolumeGoals.arms);
      expect(saved.volumeGoals.core, existingVolumeGoals.core);
    });
  });

  group('目標體重留空', () {
    testWidgets('清空既有目標體重 → 存檔後 DB 為 null(不是 0)', (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 3,
          targetWeight: 75.0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _pushGoalSettingsPage(tester, harness);

      final weightField = tester.widget<TextField>(find.byKey(const Key('targetWeightField')));
      expect(weightField.controller?.text, '75.0');

      await tester.enterText(find.byKey(const Key('targetWeightField')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveGoalSettingsButton')));
      await tester.pumpAndSettle();

      final saved = await harness.userGoalRepo.fetchByUser(testUserId);
      expect(saved, isNotNull);
      expect(saved!.targetWeight, isNull);
      expect(saved.weeklyWorkoutGoal, 3);
    });
  });

  group('值域擋下', () {
    testWidgets('週次數超過 14 時顯示錯誤、存檔按鈕 disable', (tester) async {
      final harness = await _setUpHarness();
      await _pushGoalSettingsPage(tester, harness);

      await tester.enterText(find.byKey(const Key('weeklyWorkoutGoalField')), '15');
      await tester.pumpAndSettle();

      expect(find.text('請輸入 0-14 的整數'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byKey(const Key('saveGoalSettingsButton')));
      expect(button.onPressed, isNull);
    });

    testWidgets('目標體重超過 300 時顯示錯誤、存檔按鈕 disable', (tester) async {
      final harness = await _setUpHarness();
      await _pushGoalSettingsPage(tester, harness);

      await tester.enterText(find.byKey(const Key('targetWeightField')), '301');
      await tester.pumpAndSettle();

      expect(find.text('請輸入 20-300 的體重,或留空'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byKey(const Key('saveGoalSettingsButton')));
      expect(button.onPressed, isNull);
    });

    testWidgets('目標體重低於 20 時顯示錯誤、存檔按鈕 disable', (tester) async {
      final harness = await _setUpHarness();
      await _pushGoalSettingsPage(tester, harness);

      await tester.enterText(find.byKey(const Key('targetWeightField')), '19.9');
      await tester.pumpAndSettle();

      expect(find.text('請輸入 20-300 的體重,或留空'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byKey(const Key('saveGoalSettingsButton')));
      expect(button.onPressed, isNull);
    });
  });

  group('存檔失敗', () {
    testWidgets('repository 拋錯 → 解除 loading、浮錯誤、不 pop', (tester) async {
      final harness =
          await _setUpHarness(userGoalRepoBuilder: _ThrowingUserGoalRepository.new);
      await _pushGoalSettingsPage(tester, harness);

      await tester.enterText(find.byKey(const Key('weeklyWorkoutGoalField')), '4');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveGoalSettingsButton')));
      await tester.pumpAndSettle();

      // 沒有被誤 pop:GoalSettingsPage 的欄位還在畫面上。
      expect(find.byKey(const Key('weeklyWorkoutGoalField')), findsOneWidget);
      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);

      // _isSaving 已重置為 false:欄位可編輯、按鈕恢復可按。
      final field = tester.widget<TextField>(find.byKey(const Key('weeklyWorkoutGoalField')));
      expect(field.enabled, isTrue);
      final button = tester.widget<FilledButton>(find.byKey(const Key('saveGoalSettingsButton')));
      expect(button.onPressed, isNotNull);
    });
  });

  group('體重頁目標線失效', () {
    testWidgets('存檔後 bodyWeightTabControllerProvider 重新查詢出新 targetWeight',
        (tester) async {
      final harness = await _setUpHarness();
      final now = DateTime.now();
      await harness.userGoalRepo.createOrUpdate(
        UserGoal(
          id: 'goal-1',
          userId: testUserId,
          weeklyWorkoutGoal: 3,
          targetWeight: 60.0,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 先讀一次,讓 provider 已經常駐、快取住舊值(同真實情境:使用者先進
      // 過體重頁)。bodyWeightTabControllerProvider 不是 autoDispose,即使
      // 這裡沒有持續的 listener,快取的 AsyncData 仍會留著直到被 invalidate。
      final before = await harness.container.read(bodyWeightTabControllerProvider.future);
      expect(before.targetWeight, 60.0);

      await _pushGoalSettingsPage(tester, harness);
      await tester.enterText(find.byKey(const Key('targetWeightField')), '65.0');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveGoalSettingsButton')));
      await tester.pumpAndSettle();

      final after = await harness.container.read(bodyWeightTabControllerProvider.future);
      expect(after.targetWeight, 65.0);
    });
  });

  group('存檔後再次進頁(MAJOR S1)', () {
    testWidgets('存檔返回、不重開 app 直接再次進頁 → prefill 剛存的新值,不是舊快取',
        (tester) async {
      final harness = await _setUpHarness();
      await _pushGoalSettingsPage(tester, harness);

      await tester.enterText(find.byKey(const Key('weeklyWorkoutGoalField')), '5');
      await tester.enterText(find.byKey(const Key('targetWeightField')), '70.0');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('saveGoalSettingsButton')));
      await tester.pumpAndSettle();

      // 已返回上一頁(同一個 container,沒有重開 app)。
      expect(find.byKey(const Key('openGoalSettingsButton')), findsOneWidget);

      // 再次進頁:拔掉 `ref.invalidateSelf()` 的話,provider 仍是存檔前的
      // 舊快取(weeklyWorkoutGoal=0/未設定、targetWeight=null),這裡會斷言
      // 失敗。
      await tester.tap(find.byKey(const Key('openGoalSettingsButton')));
      await tester.pumpAndSettle();

      final weeklyField =
          tester.widget<TextField>(find.byKey(const Key('weeklyWorkoutGoalField')));
      expect(weeklyField.controller?.text, '5');
      final weightField = tester.widget<TextField>(find.byKey(const Key('targetWeightField')));
      expect(weightField.controller?.text, '70.0');
    });
  });

  group('載入失敗', () {
    testWidgets('查詢拋錯時顯示 error 分支文案與重試按鈕', (tester) async {
      final harness = await _setUpHarness(
        userGoalRepoBuilder: _ThrowingOnLoadUserGoalRepository.new,
        disableAutoRetry: true,
      );

      await _pushGoalSettingsPage(tester, harness);

      expect(find.textContaining('載入失敗'), findsOneWidget);
      expect(find.byKey(const Key('goalSettingsErrorRetryButton')), findsOneWidget);
      expect(find.byKey(const Key('weeklyWorkoutGoalField')), findsNothing);
    });

    testWidgets('點重試按鈕後,暫時性失敗恢復,畫面回到正常表單', (tester) async {
      final harness = await _setUpHarness(
        userGoalRepoBuilder: _FlakyUserGoalRepository.new,
        disableAutoRetry: true,
      );

      await _pushGoalSettingsPage(tester, harness);

      expect(find.textContaining('載入失敗'), findsOneWidget);
      final retryButton = find.byKey(const Key('goalSettingsErrorRetryButton'));
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('載入失敗'), findsNothing);
      expect(find.byKey(const Key('goalSettingsErrorRetryButton')), findsNothing);
      expect(find.byKey(const Key('weeklyWorkoutGoalField')), findsOneWidget);
    });
  });
}
