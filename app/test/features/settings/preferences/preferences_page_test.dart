// PreferencesPage 頂層 pump 真組裝(brief 要求至少一條)——只換
// sharedPreferencesProvider(必要注入慣例),四個偏好 controller 全部用真身,
// 驗證頁面初始呈現(含 legacy 預填的整體效果)、逐項互動寫入即時反映,以及
// 寫入失敗時的 UI 收斂(浮錯 + 解除 loading + provider 值不變,紀律
// 【UI】寫入失敗解除 loading＋浮錯＋失敗測試)。
//
// 失敗測試用的四個 _Throwing*Controller 是刻意讓 setXxx() 拋例外的真
// Controller 子類——跟 dashboard_page_test.dart 的
// `_ThrowingBodyWeightRepository extends DriftBodyWeightRepository` 是同一套「用
// override 換掉單一方法」慣例,不需要額外的 mock 套件。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/preferences/default_rest_seconds_preference.dart';
import 'package:workout_record/features/settings/preferences/formula_explanation_page.dart';
import 'package:workout_record/features/settings/preferences/one_rm_formula_preference.dart';
import 'package:workout_record/features/settings/preferences/preferences_page.dart';
import 'package:workout_record/features/settings/preferences/theme_preference.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';

class _ThrowingWeightUnitController extends WeightUnitController {
  @override
  Future<void> setUnit(WeightUnit unit) async {
    throw Exception('模擬寫入失敗(weight unit)');
  }
}

class _ThrowingThemeModeController extends ThemeModeController {
  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    throw Exception('模擬寫入失敗(theme)');
  }
}

class _ThrowingDefaultRestSecondsController extends DefaultRestSecondsController {
  @override
  Future<void> setSeconds(int seconds) async {
    throw Exception('模擬寫入失敗(rest seconds)');
  }
}

class _ThrowingOneRmFormulaController extends OneRmFormulaController {
  @override
  Future<void> setFormula(OneRmFormula formula) async {
    throw Exception('模擬寫入失敗(one rm formula)');
  }
}

Future<ProviderContainer> _container({
  Map<String, Object> prefsValues = const {},
  bool throwingWeightUnit = false,
  bool throwingTheme = false,
  bool throwingRestSeconds = false,
  bool throwingFormula = false,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (throwingWeightUnit)
        weightUnitControllerProvider.overrideWith(() => _ThrowingWeightUnitController()),
      if (throwingTheme)
        themeModeControllerProvider.overrideWith(() => _ThrowingThemeModeController()),
      if (throwingRestSeconds)
        defaultRestSecondsControllerProvider
            .overrideWith(() => _ThrowingDefaultRestSecondsController()),
      if (throwingFormula)
        oneRmFormulaControllerProvider.overrideWith(() => _ThrowingOneRmFormulaController()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PreferencesPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 休息秒數 dropdown「畫面上實際顯示」的文字節點——限定在 dropdown 子樹內,
/// 且預設 skipOffstage(DropdownButton 內部 IndexedStack 只有選中項是 onstage),
/// 所以只會命中目前畫面顯示的那一項,不會與 hint 或展開選單的項目混淆。
Finder _restSecondsShown(String text) => find.descendant(
      of: find.byKey(const Key('defaultRestSecondsDropdown')),
      matching: find.text(text),
    );

void main() {
  group('PreferencesPage(頂層真組裝)', () {
    testWidgets('無任何 prefs 值:四項全部顯示各自預設值', (tester) async {
      final container = await _container();
      await _pump(tester, container);

      expect(
        tester
            .widget<SegmentedButton<WeightUnit>>(
                find.byKey(const Key('weightUnitSegmentedButton')))
            .selected,
        {WeightUnit.kg},
      );
      expect(
        tester
            .widget<SegmentedButton<ThemeMode>>(find.byKey(const Key('themeModeSegmentedButton')))
            .selected,
        {ThemeMode.system},
      );
      expect(
        tester
            .widget<SegmentedButton<OneRmFormula>>(
                find.byKey(const Key('oneRmFormulaSegmentedButton')))
            .selected,
        {OneRmFormula.epley},
      );
      expect(_restSecondsShown('90 秒'), findsOneWidget);
    });

    testWidgets('legacy 值全數種好時(四項各自的 legacy key):頁面顯示預填後的值', (tester) async {
      final container = await _container(
        prefsValues: {
          kLegacyWeightUnitPrefsKey: 'lb',
          kLegacyThemePrefsKey: 'dark',
          kLegacyDefaultRestTimePrefsKey: 120,
          kLegacyOneRmFormulaPrefsKey: 'brzycki',
        },
      );
      await _pump(tester, container);

      expect(
        tester
            .widget<SegmentedButton<WeightUnit>>(
                find.byKey(const Key('weightUnitSegmentedButton')))
            .selected,
        {WeightUnit.lb},
      );
      expect(
        tester
            .widget<SegmentedButton<ThemeMode>>(find.byKey(const Key('themeModeSegmentedButton')))
            .selected,
        {ThemeMode.dark},
      );
      expect(
        tester
            .widget<SegmentedButton<OneRmFormula>>(
                find.byKey(const Key('oneRmFormulaSegmentedButton')))
            .selected,
        {OneRmFormula.brzycki},
      );
      expect(_restSecondsShown('120 秒'), findsOneWidget);
    });

    testWidgets('點選重量單位「磅 (lb)」→ provider 值即時反映 + prefs 寫入', (tester) async {
      final container = await _container();
      await _pump(tester, container);

      await tester.tap(find.text('磅 (lb)'));
      await tester.pumpAndSettle();

      expect(container.read(weightUnitProvider), WeightUnit.lb);
      expect(container.read(sharedPreferencesProvider).getString(kWeightUnitPrefsKey), 'lb');
      expect(
        tester
            .widget<SegmentedButton<WeightUnit>>(
                find.byKey(const Key('weightUnitSegmentedButton')))
            .selected,
        {WeightUnit.lb},
      );
    });

    testWidgets('點選主題「深色」→ provider 值即時反映 + prefs 寫入', (tester) async {
      final container = await _container();
      await _pump(tester, container);

      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(container.read(sharedPreferencesProvider).getString(kThemeModePrefsKey), 'dark');
    });

    testWidgets('選擇休息秒數「180 秒」→ provider 值即時反映 + prefs 寫入', (tester) async {
      final container = await _container();
      await _pump(tester, container);

      await tester.tap(find.byKey(const Key('defaultRestSecondsDropdown')));
      await tester.pumpAndSettle();
      // 19 個選項的選單超出預設測試視窗高度,180 秒排在選單捲動範圍外——
      // 先 ensureVisible 捲到看得見再點,不然點擊座標會落在選單外面的
      // AbsorbPointer 上,tap 到別的東西(修正前這裡誤判成功,實際上
      // provider 值沒變)。
      final option = find.text('180 秒').last;
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(container.read(defaultRestSecondsProvider), 180);
      expect(
        container.read(sharedPreferencesProvider).getInt(kDefaultRestSecondsPrefsKey),
        180,
      );
      expect(_restSecondsShown('180 秒'), findsOneWidget);
    });

    testWidgets('點選 1RM 公式「Lander」→ provider 值即時反映 + prefs 寫入', (tester) async {
      final container = await _container();
      await _pump(tester, container);

      await tester.tap(find.text('Lander'));
      await tester.pumpAndSettle();

      expect(container.read(oneRmFormulaProvider), OneRmFormula.lander);
      expect(
        container.read(sharedPreferencesProvider).getString(kOneRmFormulaPrefsKey),
        'lander',
      );
    });

    testWidgets('重量單位寫入失敗 → 浮錯 + 解除 loading + provider 值不變', (tester) async {
      final container = await _container(throwingWeightUnit: true);
      await _pump(tester, container);

      await tester.tap(find.text('磅 (lb)'));
      await tester.pumpAndSettle();

      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);
      expect(container.read(weightUnitProvider), WeightUnit.kg);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('主題寫入失敗 → 浮錯 + 解除 loading + provider 值不變', (tester) async {
      final container = await _container(throwingTheme: true);
      await _pump(tester, container);

      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();

      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);
      expect(container.read(themeModeProvider), ThemeMode.system);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('休息秒數寫入失敗 → 浮錯 + 解除 loading + provider 值不變', (tester) async {
      final container = await _container(throwingRestSeconds: true);
      await _pump(tester, container);

      await tester.tap(find.byKey(const Key('defaultRestSecondsDropdown')));
      await tester.pumpAndSettle();
      final option = find.text('180 秒').last;
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);
      expect(container.read(defaultRestSecondsProvider), 90);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // review MAJOR:畫面本身必須回退顯示舊值——只斷言 provider 值會漏掉
      // FormField 內部 state 停在使用者選過的 180 的狀況(SDK
      // dropdown.dart `_DropdownButtonFormFieldState.didChange`)。
      expect(_restSecondsShown('90 秒'), findsOneWidget);
      expect(_restSecondsShown('180 秒'), findsNothing);
    });

    testWidgets('1RM 公式寫入失敗 → 浮錯 + 解除 loading + provider 值不變', (tester) async {
      final container = await _container(throwingFormula: true);
      await _pump(tester, container);

      await tester.tap(find.text('Lander'));
      await tester.pumpAndSettle();

      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);
      expect(container.read(oneRmFormulaProvider), OneRmFormula.epley);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('公式說明入口', () {
    testWidgets('點「查看公式說明」→ 進入說明頁且列出三條公式與適用情境', (tester) async {
      final container = await _container();
      await _pump(tester, container);

      await tester.tap(find.byKey(const Key('formulaExplanationButton')));
      await tester.pumpAndSettle();

      expect(find.byType(FormulaExplanationPage), findsOneWidget);
      expect(find.text('Epley 公式'), findsOneWidget);
      expect(find.text('1RM = 重量 × (1 + 次數 / 30)'), findsOneWidget);
      expect(find.text('最常用的公式，適合大多數情況。'), findsOneWidget);
      expect(find.text('Brzycki 公式'), findsOneWidget);
      expect(find.text('1RM = 重量 × (36 / (37 - 次數))'), findsOneWidget);
      expect(find.text('較保守的估算，適合次數較少的情況。'), findsOneWidget);
      expect(find.text('Lander 公式'), findsOneWidget);
      expect(
        find.text('1RM = 重量 × (100 / (101.3 - 2.67123 × 次數))'),
        findsOneWidget,
      );
      expect(find.text('適合高次數的訓練估算。'), findsOneWidget);
    });
  });

  group('重置所有設定', () {
    const nonDefaults = <String, Object>{
      kWeightUnitPrefsKey: 'lb',
      kThemeModePrefsKey: 'dark',
      kDefaultRestSecondsPrefsKey: 150,
      kOneRmFormulaPrefsKey: 'lander',
      'unrelated_training_key': 'keep-me',
    };

    testWidgets('確認重置 → 四項偏好回預設並寫入 prefs,其他 key 不動', (tester) async {
      final container = await _container(prefsValues: nonDefaults);
      await _pump(tester, container);
      expect(container.read(weightUnitProvider), WeightUnit.lb);

      await tester.tap(find.byKey(const Key('resetPreferencesButton')));
      await tester.pumpAndSettle();
      expect(find.text('確定要將所有設定恢復為預設值嗎？'), findsOneWidget);
      await tester.tap(find.byKey(const Key('resetPreferencesConfirm')));
      await tester.pumpAndSettle();

      expect(container.read(weightUnitProvider), WeightUnit.kg);
      expect(container.read(themeModeProvider), ThemeMode.system);
      expect(container.read(defaultRestSecondsProvider), 90);
      expect(container.read(oneRmFormulaProvider), OneRmFormula.epley);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(kWeightUnitPrefsKey), 'kg');
      expect(prefs.getString(kThemeModePrefsKey), 'system');
      expect(prefs.getInt(kDefaultRestSecondsPrefsKey), 90);
      expect(prefs.getString(kOneRmFormulaPrefsKey), 'epley');
      expect(prefs.getString('unrelated_training_key'), 'keep-me');
    });

    testWidgets('取消 → 偏好維持不變', (tester) async {
      final container = await _container(prefsValues: nonDefaults);
      await _pump(tester, container);

      await tester.tap(find.byKey(const Key('resetPreferencesButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resetPreferencesCancel')));
      await tester.pumpAndSettle();

      expect(find.text('重置設定'), findsNothing);
      expect(container.read(weightUnitProvider), WeightUnit.lb);
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(container.read(defaultRestSecondsProvider), 150);
      expect(container.read(oneRmFormulaProvider), OneRmFormula.lander);
    });

    testWidgets('寫入失敗 → 浮錯、解除 reset 鎖定、值不變', (tester) async {
      final container = await _container(
        prefsValues: nonDefaults,
        throwingWeightUnit: true,
      );
      await _pump(tester, container);

      await tester.tap(find.byKey(const Key('resetPreferencesButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resetPreferencesConfirm')));
      await tester.pumpAndSettle();

      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);
      expect(container.read(weightUnitProvider), WeightUnit.lb);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('resetPreferencesButton')))
            .onPressed,
        isNotNull,
      );
    });
  });
}
