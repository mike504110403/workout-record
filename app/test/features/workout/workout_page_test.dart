// M5:WorkoutPage 進入畫面時偵測未完成訓練草稿的行為(對照
// workout_page.dart `_checkForRecoverableDraft`)。真 in-memory DB + 真
// repositories,只 override DB/prefs(同 workout_controller_test.dart 的
// seam 規格)。覆蓋:繼續分支(state 接手草稿、startedAt 一致)、放棄分支
// (DB 查不到該列)、`_draftCheckStarted` 一次性守衛(同一個 State 存活期間
// 不重複彈對話框)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart'
    hide Workout, WorkoutExercise, WorkoutSet, Exercise;
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/data/repositories/exercise_repository.dart';
import 'package:workout_record/data/repositories/workout_repository.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/workout/workout_controller.dart';
import 'package:workout_record/features/workout/workout_page.dart';

import '../../data/test_helpers.dart';

typedef _Harness = ({AppDatabase db, ProviderContainer container});

Future<_Harness> _setUpHarness() async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  await seedTestUser(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (db: db, container: container);
}

/// 直接透過 repository 種一筆進行中草稿(不經 controller),模擬「上次
/// session 留下的未完成訓練」——controller 的 [state] 保持乾淨的 idle,
/// 對照 `build()` 「刻意不自動接手上一個 session 遺留的草稿」的文件說明。
/// `startedAt` 用整秒的字面量(不用 `DateTime.now()`)避免 DB 往返的時間
/// 精度落差影響比對。
Future<String> _seedDraft(AppDatabase db, {String workoutId = 'recoverable-draft-1'}) async {
  final repo = WorkoutRepository(db, ExerciseRepository(db));
  final startedAt = DateTime(2026, 3, 1, 9, 0);
  await repo.create(Workout(
    id: workoutId,
    userId: testUserId,
    startedAt: startedAt,
    createdAt: startedAt,
    updatedAt: startedAt,
  ));
  return workoutId;
}

Future<void> _pumpPage(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: WorkoutPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('進入畫面偵測未完成草稿', () {
    testWidgets('有草稿 → 彈對話框 → 繼續 → state 接手草稿,startedAt 與草稿列一致', (tester) async {
      final harness = await _setUpHarness();
      await _seedDraft(harness.db);

      await _pumpPage(tester, harness);

      expect(find.text('發現未完成的訓練'), findsOneWidget);
      await tester.tap(find.byKey(const Key('resumeDraftContinueButton')));
      await tester.pumpAndSettle();

      expect(find.text('發現未完成的訓練'), findsNothing);
      final state = harness.container.read(workoutControllerProvider).value!;
      expect(state.draft, isNotNull);
      expect(state.draft!.id, 'recoverable-draft-1');
      expect(state.draft!.startedAt, DateTime(2026, 3, 1, 9, 0));
      expect(state.draft!.endedAt, isNull);
    });

    testWidgets('有草稿 → 彈對話框 → 放棄 → state 仍是 idle,DB 查不到該列', (tester) async {
      final harness = await _setUpHarness();
      final workoutId = await _seedDraft(harness.db);
      final repo = WorkoutRepository(harness.db, ExerciseRepository(harness.db));

      await _pumpPage(tester, harness);

      expect(find.text('發現未完成的訓練'), findsOneWidget);
      await tester.tap(find.byKey(const Key('resumeDraftDiscardButton')));
      await tester.pumpAndSettle();

      expect(find.text('發現未完成的訓練'), findsNothing);
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);
      expect(await repo.fetchById(workoutId), isNull);
    });

    testWidgets('沒有草稿 → 不彈對話框,直接顯示開始畫面', (tester) async {
      final harness = await _setUpHarness();

      await _pumpPage(tester, harness);

      expect(find.text('發現未完成的訓練'), findsNothing);
      expect(harness.container.read(workoutControllerProvider).value!.draft, isNull);
    });

    // `_draftCheckStarted` 一次性守衛的迴歸煙霧測試——**注意這不是有效的
    // 雙向變異測試**:實測過把 `if (_draftCheckStarted) return;` 拿掉,這則
    // 測試仍然綠(見 workout_page.dart `_checkForRecoverableDraft` 目前唯一
    // 呼叫點是 `initState()` 裡的 `WidgetsBinding.instance.
    // addPostFrameCallback`——這個 callback 本來就只在下一幀觸發一次,不會
    // 因為之後再 `pump()` 就重新觸發,所以 `_draftCheckStarted` 這個旗標在
    // 目前這個唯一呼叫點下沒有可觀察的黑箱效果,是面向未來變更的防禦寫法,
    // 不是可被外部行為測試釘住的邏輯)。保留這則測試只作為「對話框解決後
    // 不會無端再彈」的迴歸煙霧測試,不宣稱它驗證了 `_draftCheckStarted`
    // 本身。
    testWidgets('放棄後再次 pump(同一個 State,模擬切分頁回來)→ 不重複彈對話框(迴歸煙霧測試)',
        (tester) async {
      final harness = await _setUpHarness();
      await _seedDraft(harness.db);

      await _pumpPage(tester, harness);
      expect(find.text('發現未完成的訓練'), findsOneWidget);
      await tester.tap(find.byKey(const Key('resumeDraftDiscardButton')));
      await tester.pumpAndSettle();
      expect(find.text('發現未完成的訓練'), findsNothing);

      // 再種一筆(不同 id 的)草稿(模擬另一個 session 又留下一筆)——若
      // 一次性守衛失效,下一次 pump 觸發的 postFrameCallback 會再查一次
      // DB 並彈對話框。
      await _seedDraft(harness.db, workoutId: 'recoverable-draft-2');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('發現未完成的訓練'), findsNothing);
    });
  });
}
