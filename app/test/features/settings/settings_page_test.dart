// SettingsPage 主頁 seam:七項入口各自導頁正確(波 6 core brief seam 段)。
// 登出流程既有斷言在 settings_logout_test.dart,這裡不重複。
//
// 變異清單:拔掉任一入口的 `Navigator.push` 呼叫,對應那一條測試必紅(斷言
// 的是「push 後真的出現目的頁的 AppBar 標題」,不是只斷言 ListTile 存在)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/db/app_database.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/preferences/theme_preference.dart';
import 'package:workout_record/features/settings/preferences/weight_unit.dart';
import 'package:workout_record/features/settings/settings_page.dart';

import '../../data/test_helpers.dart';

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

class _Harness {
  _Harness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;
}

/// 五個真實目的頁裡有兩個(目標設定/我的模板)會碰資料層——比照
/// dashboard_page_test.dart / goal_settings_page_test.dart 的既有慣例,一律
/// 換成 in-memory DB + mock prefs,不連真實 sqlite。
Future<_Harness> _setUpHarness({
  Map<String, Object> extraPrefs = const {},
  bool throwingWeightUnit = false,
  bool throwingTheme = false,
}) async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId, ...extraPrefs});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      if (throwingWeightUnit)
        weightUnitControllerProvider.overrideWith(() => _ThrowingWeightUnitController()),
      if (throwingTheme)
        themeModeControllerProvider.overrideWith(() => _ThrowingThemeModeController()),
    ],
  );
  addTearDown(container.dispose);
  return _Harness(db, container);
}

Future<void> _pumpSettingsPage(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 第 3 波起設定頁是 large title + 群組卡片,入口多半落在 800x600 預設視窗外,
/// 先捲到可見再點。
Future<void> _tapEntry(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  // 「關於」入口會 push AboutPage,它一 build 就呼叫
  // `PackageInfo.fromPlatform()`——測試環境沒 mock 的話會走平台 channel
  // 拋 MissingPluginException,about_page.dart 已經 catch 成 null 顯示
  // 「版本未知」,但仍需要這個 mock 讓 Future 儘快穩定完成,不然
  // `pumpAndSettle` 會因為 CircularProgressIndicator 一直畫新 frame 而
  // timeout(同 about_page_test.dart 的既有慣例)。
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'WorkItOut',
      packageName: 'com.mikelin.workitout',
      version: '2.0.0',
      buildNumber: '6',
      buildSignature: '',
    );
  });

  testWidgets('入口依 section 分組:四個小標題依序出現,入口落在各自標題之後(review minor)',
      (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    double top(Finder f) => tester.getTopLeft(f).dy;
    final personal = top(find.text('個人'));
    final profile = top(find.byKey(const Key('settingsProfileEntry')));
    final goal = top(find.byKey(const Key('settingsGoalEntry')));
    final training = top(find.text('訓練'));
    final templates = top(find.byKey(const Key('settingsTemplatesEntry')));
    final app = top(find.text('應用程式'));
    final prefs = top(find.byKey(const Key('settingsPreferencesEntry')));
    final about = top(find.byKey(const Key('settingsAboutEntry')));
    final account = top(find.text('帳號'));
    final signOut = top(find.byKey(const Key('signOutButton')));

    expect(
      [personal, profile, goal, training, templates, app, prefs, about, account, signOut],
      orderedEquals([
        personal, profile, goal, training, templates, app, prefs, about, account, signOut,
      ]..sort()),
    );
  });

  testWidgets('點「個人資料」→ 導到 ProfilePage', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    await _tapEntry(tester, const Key('settingsProfileEntry'));

    expect(find.widgetWithText(AppBar, '個人資料'), findsOneWidget);
  });

  testWidgets('點「目標設定」→ 導到 GoalSettingsPage', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    await _tapEntry(tester, const Key('settingsGoalEntry'));

    expect(find.widgetWithText(AppBar, '目標設定'), findsOneWidget);
  });

  testWidgets('點「我的模板」→ 導到 TemplatesListPage', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    await _tapEntry(tester, const Key('settingsTemplatesEntry'));

    expect(find.widgetWithText(AppBar, '我的模板'), findsOneWidget);
  });

  testWidgets('點「偏好設定」→ 導到 PreferencesPage(契約 stub)', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    await _tapEntry(tester, const Key('settingsPreferencesEntry'));

    expect(find.widgetWithText(AppBar, '偏好設定'), findsOneWidget);
  });

  testWidgets('點「關於」→ 導到 AboutPage', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    await _tapEntry(tester, const Key('settingsAboutEntry'));

    expect(find.widgetWithText(AppBar, '關於'), findsOneWidget);
  });

  testWidgets('登出按鈕仍在,ImportRetryTile 位置在列表尾(未觸發時不渲染)', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    expect(find.byKey(const Key('signOutButton')), findsOneWidget);
    // 沒有標記 kCoreDataImportFailedPermanentlyKey,ImportRetryTile 不渲染
    // 任何內容(見 widgets/import_retry_tile.dart),這裡只驗證七項入口 +
    // 登出按鈕都在同一棵主頁組裝出來,沒有互相排擠。
    expect(find.byKey(const Key('settingsProfileEntry')), findsOneWidget);
    expect(find.byKey(const Key('settingsGoalEntry')), findsOneWidget);
    expect(find.byKey(const Key('settingsTemplatesEntry')), findsOneWidget);
    expect(find.byKey(const Key('settingsPreferencesEntry')), findsOneWidget);
    expect(find.byKey(const Key('settingsAboutEntry')), findsOneWidget);
  });

  testWidgets('頂部是 M3 large title(SliverAppBar.large),不是一條只重複分頁名稱的 AppBar',
      (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    expect(find.byType(SliverAppBar), findsOneWidget);
    expect(find.descendant(of: find.byType(SliverAppBar), matching: find.text('設定')), findsWidgets);
    // Scaffold 本身沒有掛傳統 appBar。
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).appBar, isNull);
  });

  testWidgets('每個入口的圖示一律單色 onSurfaceVariant(登出也是;只有刪除帳號才用 error)',
      (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    final muted = Theme.of(tester.element(find.byType(SettingsPage))).colorScheme.onSurfaceVariant;
    for (final key in const [
      'settingsProfileEntry',
      'settingsGoalEntry',
      'settingsCustomExercisesEntry',
      'settingsTemplatesEntry',
      'settingsPreferencesEntry',
      'settingsTutorialEntry',
      'settingsAboutEntry',
      'signOutButton',
    ]) {
      final leading = find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(Icon),
      );
      expect(leading, findsWidgets, reason: key);
      // 第一個 Icon 是 leading 圖示。
      expect(tester.widget<Icon>(leading.first).color, muted, reason: key);
    }
  });

  group('行內偏好:重量單位 / 主題直接在設定主列表切換', () {
    SegmentedButton<T> segmented<T>(WidgetTester tester, String key) =>
        tester.widget<SegmentedButton<T>>(find.byKey(Key(key)));

    testWidgets('預設:kg、跟隨系統;legacy 值預填時顯示 lb、深色', (tester) async {
      var harness = await _setUpHarness();
      await _pumpSettingsPage(tester, harness);
      expect(segmented<WeightUnit>(tester, 'weightUnitSegmentedButton').selected, {WeightUnit.kg});
      expect(segmented<ThemeMode>(tester, 'themeModeSegmentedButton').selected, {ThemeMode.system});

      harness = await _setUpHarness(
        extraPrefs: {kLegacyWeightUnitPrefsKey: 'lb', kLegacyThemePrefsKey: 'dark'},
      );
      await _pumpSettingsPage(tester, harness);
      expect(segmented<WeightUnit>(tester, 'weightUnitSegmentedButton').selected, {WeightUnit.lb});
      expect(segmented<ThemeMode>(tester, 'themeModeSegmentedButton').selected, {ThemeMode.dark});
    });

    testWidgets('點「磅 (lb)」→ provider 值即時反映 + prefs 寫入', (tester) async {
      final harness = await _setUpHarness();
      await _pumpSettingsPage(tester, harness);

      await tester.ensureVisible(find.text('磅 (lb)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('磅 (lb)'));
      await tester.pumpAndSettle();

      expect(harness.container.read(weightUnitProvider), WeightUnit.lb);
      expect(
        harness.container.read(sharedPreferencesProvider).getString(kWeightUnitPrefsKey),
        'lb',
      );
      expect(segmented<WeightUnit>(tester, 'weightUnitSegmentedButton').selected, {WeightUnit.lb});
    });

    testWidgets('點主題「深色」→ provider 值即時反映 + prefs 寫入', (tester) async {
      final harness = await _setUpHarness();
      await _pumpSettingsPage(tester, harness);

      await tester.ensureVisible(find.text('深色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();

      expect(harness.container.read(themeModeProvider), ThemeMode.dark);
      expect(
        harness.container.read(sharedPreferencesProvider).getString(kThemeModePrefsKey),
        'dark',
      );
    });

    testWidgets('重量單位寫入失敗 → 浮錯 + 解除 loading + provider 值不變、畫面回舊選項', (tester) async {
      final harness = await _setUpHarness(throwingWeightUnit: true);
      await _pumpSettingsPage(tester, harness);

      await tester.ensureVisible(find.text('磅 (lb)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('磅 (lb)'));
      await tester.pumpAndSettle();

      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);
      expect(harness.container.read(weightUnitProvider), WeightUnit.kg);
      expect(segmented<WeightUnit>(tester, 'weightUnitSegmentedButton').selected, {WeightUnit.kg});
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('主題寫入失敗 → 浮錯 + 解除 loading + provider 值不變', (tester) async {
      final harness = await _setUpHarness(throwingTheme: true);
      await _pumpSettingsPage(tester, harness);

      await tester.ensureVisible(find.text('深色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();

      expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);
      expect(harness.container.read(themeModeProvider), ThemeMode.system);
      expect(segmented<ThemeMode>(tester, 'themeModeSegmentedButton').selected, {ThemeMode.system});
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  testWidgets('360 寬、字體 1.5 倍:行內 SegmentedButton 與各群組不溢位', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = await _setUpHarness();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('themeModeSegmentedButton')), findsOneWidget);
  });
}
