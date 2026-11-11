// StatsPage 殼(三段 segmented control)的 widget test。只驗證分頁切換行為
// 本身,子頁內容各自有自己的測試(訓練統計見
// test/features/stats/workout_stats/workout_stats_tab_test.dart)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/stats/body_weight/body_weight_controller.dart';
import 'package:workout_record/features/stats/body_weight/body_weight_tab.dart';
import 'package:workout_record/features/stats/powerlifting/powerlifting_controller.dart';
import 'package:workout_record/features/stats/powerlifting/powerlifting_tab.dart';
import 'package:workout_record/features/stats/stats_page.dart';
import 'package:workout_record/features/stats/workout_stats/workout_stats_controller.dart';
import 'package:workout_record/features/stats/workout_stats/workout_stats_tab.dart';

import '../../data/test_helpers.dart';

Future<void> _pump(WidgetTester tester) async {
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);
  // WAVE4 merge 接線後,體重/三項是真子頁(不再是 placeholder),需要
  // prefs(session/userId 解析)——比照各子頁自身測試的 override 慣例。
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MaterialApp(home: StatsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('預設停在「訓練統計」分頁(不是體重)', (tester) async {
    await _pump(tester);

    expect(find.byType(WorkoutStatsTab), findsOneWidget);
  });

  testWidgets('預設選取的就是第一個分段(訓練排第一,選取不落在中間)', (tester) async {
    await _pump(tester);

    final control = tester.widget<SegmentedButton<int>>(
      find.byKey(const Key('statsSegmentedControl')),
    );
    expect(control.selected, {0});
    expect(control.segments.first.value, 0);
    // 分段順序:訓練 / 體重 / 三項。
    expect(
      [
        for (final i in [0, 1, 2])
          tester.widget<Text>(find.byKey(Key('statsSegment-$i'))).data,
      ],
      ['訓練', '體重', '三項'],
    );
  });

  testWidgets('切到「體重」分頁,顯示 BodyWeightTab', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('statsSegment-1')));
    await tester.pumpAndSettle();

    expect(find.byType(BodyWeightTab), findsOneWidget);
  });

  testWidgets('切到「三項」分頁,顯示 PowerliftingTab', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('statsSegment-2')));
    await tester.pumpAndSettle();

    expect(find.byType(PowerliftingTab), findsOneWidget);
  });

  testWidgets('沒有「數據」標題列:不放 AppBar,分段鈕頂在最上面', (tester) async {
    await _pump(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('數據'), findsNothing);
    // 分段鈕緊貼狀態列安全區下方(測試環境安全區為 0,頂端只留 AppSpacing.sm 的內距)。
    final controlTop = tester.getTopLeft(find.byKey(const Key('statsSegmentedControl'))).dy;
    expect(controlTop, lessThan(24));
  });

  testWidgets('子頁懶建置:未選過的子頁不存在、provider 也沒被觸發;選過一次後才建置', (tester) async {
    await _pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(StatsPage)));

    // 只有預設的「訓練」建置;體重/三項連 Element 都不存在(skipOffstage:false
    // 連被 IndexedStack 蓋住的也找),背後的 provider 也沒被建立。
    expect(find.byType(WorkoutStatsTab, skipOffstage: false), findsOneWidget);
    expect(find.byType(BodyWeightTab, skipOffstage: false), findsNothing);
    expect(find.byType(PowerliftingTab, skipOffstage: false), findsNothing);
    expect(container.exists(workoutStatsControllerProvider), isTrue);
    expect(container.exists(bodyWeightTabControllerProvider), isFalse);
    expect(container.exists(powerliftingControllerProvider), isFalse);

    await tester.tap(find.byKey(const Key('statsSegment-1')));
    await tester.pumpAndSettle();
    expect(find.byType(BodyWeightTab, skipOffstage: false), findsOneWidget);
    expect(container.exists(bodyWeightTabControllerProvider), isTrue);
    // 三項仍沒被選過 → 仍未建置。
    expect(find.byType(PowerliftingTab, skipOffstage: false), findsNothing);
    expect(container.exists(powerliftingControllerProvider), isFalse);
  });

  testWidgets('已建過的子頁切走後仍保留(不 dispose、不重新查詢)', (tester) async {
    await _pump(tester);

    // 訓練統計預設就在畫面上;切到體重分頁後,訓練統計子頁應該還在
    // element tree(只是被 IndexedStack 蓋住),不是被 dispose 重建。
    //
    // 這裡刻意用 skipOffstage:false——`IndexedStack` 的
    // `_IndexedStackElement.debugVisitOnstageChildren` 只把「目前選中的
    // 那個 index」視為 onstage,預設的 `find.byType`(skipOffstage:true)
    // 找不到被蓋住的子頁,即使它其實還活在 element tree、狀態沒被清掉。
    expect(find.byType(WorkoutStatsTab), findsOneWidget);

    await tester.tap(find.byKey(const Key('statsSegment-1')));
    await tester.pumpAndSettle();

    expect(find.byType(BodyWeightTab), findsOneWidget);
    expect(
      find.byType(WorkoutStatsTab, skipOffstage: false),
      findsOneWidget,
      reason: '訓練統計子頁應該還活在 element tree 裡(只是被蓋住),不是被 dispose 重建',
    );

    // 切回訓練後,體重子頁同樣保留。
    await tester.tap(find.byKey(const Key('statsSegment-0')));
    await tester.pumpAndSettle();
    expect(find.byType(BodyWeightTab, skipOffstage: false), findsOneWidget);
  });
}
