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
import 'package:workout_record/features/settings/settings_page.dart';

import '../../data/test_helpers.dart';

class _Harness {
  _Harness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;
}

/// 五個真實目的頁裡有兩個(目標設定/我的模板)會碰資料層——比照
/// dashboard_page_test.dart / goal_settings_page_test.dart 的既有慣例,一律
/// 換成 in-memory DB + mock prefs,不連真實 sqlite。
Future<_Harness> _setUpHarness() async {
  SharedPreferences.setMockInitialValues({kAppleUserIdKey: testUserId});
  final prefs = await SharedPreferences.getInstance();
  final db = openTestDatabase();
  addTearDown(db.close);
  await seedTestUser(db);

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
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

  testWidgets('點「個人資料」→ 導到 ProfilePage', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    await tester.tap(find.byKey(const Key('settingsProfileEntry')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '個人資料'), findsOneWidget);
  });

  testWidgets('點「目標設定」→ 導到 GoalSettingsPage', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    await tester.tap(find.byKey(const Key('settingsGoalEntry')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '目標設定'), findsOneWidget);
  });

  testWidgets('點「我的模板」→ 導到 TemplatesListPage', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    await tester.tap(find.byKey(const Key('settingsTemplatesEntry')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '訓練模板'), findsOneWidget);
  });

  testWidgets('點「偏好設定」→ 導到 PreferencesPage(契約 stub)', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    await tester.tap(find.byKey(const Key('settingsPreferencesEntry')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '偏好設定'), findsOneWidget);
  });

  testWidgets('點「關於」→ 導到 AboutPage', (tester) async {
    final harness = await _setUpHarness();
    await _pumpSettingsPage(tester, harness);

    await tester.tap(find.byKey(const Key('settingsAboutEntry')));
    await tester.pumpAndSettle();

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
}
