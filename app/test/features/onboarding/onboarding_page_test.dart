// OnboardingPage widget seam(2026-11 改版:5 步縮成 2 步):
// - 步驟 1「基本資訊」(單位、體重、身高、性別、年齡)→ 步驟 2「目標」(目標體重、
//   每週訓練次數);步驟指示「1 / 2」、進度條、固定底部主按鈕。
// - 基本資訊頁體重非有效數值時「下一步」disabled(對等 iOS
//   `canProceed(from: .basicInfo)`);「跳過」在任一步都能直接完成。
// - 兩步都不得出現 emoji;從 UI 走完 2 步後 complete() 寫入的欄位與原本一致
//   (prefs 個資 + 初始 BodyWeight + UserGoal + 完成旗標)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_controller.dart';
import 'package:workout_record/features/onboarding/onboarding_page.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';

import '../../data/test_helpers.dart';

/// 掛上 OnboardingPage,回傳 container 供斷言。視窗拉高讓整張表單都在畫面內。
Future<ProviderContainer> _pumpPage(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 1400);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({kAppleUserIdKey: 'test-user'});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: OnboardingPage()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 畫面上所有 Text 的文字(含 TextField 的 label/hint 以外的純 Text)。
Iterable<String> _allTexts(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');

final _emoji = RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}]', unicode: true);

void main() {
  testWidgets('第一步:顯示「1 / 2」、基本資訊欄位全在、不含功能介紹與舊 App 名', (tester) async {
    await _pumpPage(tester);

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byKey(const Key('onboardingProgress')), findsOneWidget);
    expect(find.text('基本資訊'), findsOneWidget);
    expect(find.text('歡迎使用 Work It Out'), findsOneWidget);
    expect(find.text('歡迎使用健身記錄'), findsNothing);
    for (final key in const [
      'onboardingWeightUnitToggle',
      'onboardingWeightField',
      'onboardingHeightField',
      'onboardingGenderToggle',
      'onboardingAgeField',
      'skipOnboardingButton',
      'onboardingNextButton',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    // 功能介紹頁已移除。
    expect(find.text('記錄訓練'), findsNothing);
    expect(find.text('主要功能'), findsNothing);
    expect(find.textContaining('成就'), findsNothing);
    // 返回鍵只在第 2 步出現。
    expect(find.byKey(const Key('onboardingBackButton')), findsNothing);
  });

  testWidgets('基本資訊頁:體重欄位空白時「下一步」disabled,填有效數值後 enabled', (tester) async {
    await _pumpPage(tester);

    FilledButton nextButton() =>
        tester.widget<FilledButton>(find.byKey(const Key('onboardingNextButton')));

    expect(nextButton().onPressed, isNull, reason: '體重欄位還是空的,下一步應該 disabled');

    await tester.enterText(find.byKey(const Key('onboardingWeightField')), '70');
    await tester.pumpAndSettle();

    expect(nextButton().onPressed, isNotNull, reason: '填了有效體重之後下一步應該 enabled');
  });

  testWidgets('基本資訊頁:體重欄位填非數值文字時「下一步」仍是 disabled', (tester) async {
    await _pumpPage(tester);

    await tester.enterText(find.byKey(const Key('onboardingWeightField')), 'abc');
    await tester.pumpAndSettle();

    final nextButton = tester.widget<FilledButton>(find.byKey(const Key('onboardingNextButton')));
    expect(nextButton.onPressed, isNull);
  });

  testWidgets('兩步畫面都沒有 emoji', (tester) async {
    await _pumpPage(tester);

    for (final t in _allTexts(tester)) {
      expect(_emoji.hasMatch(t), isFalse, reason: '第 1 步出現 emoji:$t');
    }

    await tester.enterText(find.byKey(const Key('onboardingWeightField')), '70');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingNextButton')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    for (final t in _allTexts(tester)) {
      expect(_emoji.hasMatch(t), isFalse, reason: '第 2 步出現 emoji:$t');
    }
  });

  testWidgets('走完 2 步:欄位、下一步/返回、完成後寫入與原本 complete() 一致', (tester) async {
    final container = await _pumpPage(tester);

    // 步驟 1:單位換 lb 再換回 kg(確認切換不丟資料),填體重/身高/性別/年齡。
    await tester.tap(find.text('lb'));
    await tester.pumpAndSettle();
    expect(container.read(onboardingControllerProvider).weightUnit, OnboardingWeightUnit.lb);
    await tester.tap(find.text('kg'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('onboardingWeightField')), '70.5');
    await tester.enterText(find.byKey(const Key('onboardingHeightField')), '175');
    await tester.tap(find.text('男性'));
    await tester.enterText(find.byKey(const Key('onboardingAgeField')), '30');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboardingNextButton')));
    await tester.pumpAndSettle();

    // 步驟 2:目標。
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('目標'), findsOneWidget);
    expect(find.byKey(const Key('onboardingTargetWeightField')), findsOneWidget);
    expect(find.byKey(const Key('onboardingNextButton')), findsNothing);
    expect(find.byKey(const Key('startUsingButton')), findsOneWidget);

    // 返回第 1 步,草稿保留。
    await tester.tap(find.byKey(const Key('onboardingBackButton')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('70.5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboardingNextButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('onboardingTargetWeightField')), '65');
    await tester.tap(find.byKey(const Key('onboardingWeeklyGoalIncrement')));
    await tester.pumpAndSettle();
    expect(find.text('5 次'), findsOneWidget);

    await tester.tap(find.byKey(const Key('startUsingButton')));
    await tester.pumpAndSettle();

    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getDouble(kUserCurrentWeightKey), 70.5);
    expect(prefs.getDouble(kUserHeightKey), 175);
    expect(prefs.getString(kUserGenderKey), '男性');
    expect(prefs.getInt(kUserAgeKey), 30);
    expect(prefs.getDouble(kUserTargetWeightKey), 65);
    expect(prefs.getInt(kWeeklyWorkoutGoalKey), 5);
    expect(prefs.getString(kUserWeightUnitKey), 'kg');
    expect(container.read(onboardingStatusProvider), isTrue);

    final db = container.read(appDatabaseProvider);
    final bodyWeights = await db.select(db.bodyWeights).get();
    expect(bodyWeights, hasLength(1));
    expect(bodyWeights.single.weight, 70.5);

    final goal = await container.read(userGoalRepositoryProvider).fetchByUser('test-user');
    expect(goal?.weeklyWorkoutGoal, 5);
    expect(goal?.targetWeight, 65);
  });

  testWidgets('「跳過」不驗證欄位,直接完成 Onboarding', (tester) async {
    final container = await _pumpPage(tester);

    await tester.tap(find.byKey(const Key('skipOnboardingButton')));
    await tester.pumpAndSettle();

    expect(container.read(onboardingStatusProvider), isTrue);
  });
}
