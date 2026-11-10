// TutorialPage:能渲染各章節;兩個入口(關於頁 aboutTutorialTile、設定頁
// settingsTutorialEntry)都能 push 到教學頁。
//
// 變異清單:拔掉任一入口的 Navigator.push → 對應入口測試必紅(斷言的是
// push 後出現教學頁 AppBar 標題與內容,不是只斷言 tile 存在)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/settings/about/about_page.dart';
import 'package:workout_record/features/settings/settings_page.dart';
import 'package:workout_record/features/settings/tutorial/tutorial_page.dart';

import '../../../data/test_helpers.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'WorkItOut',
      packageName: 'com.mikelin.workitout',
      version: '2.0.0',
      buildNumber: '6',
      buildSignature: '',
    );
  });

  testWidgets('教學頁渲染:標題與五個章節都在', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TutorialPage()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '使用教學'), findsOneWidget);
    expect(find.text('歡迎使用 WorkItOut'), findsOneWidget);
    expect(find.text('快速開始'), findsOneWidget);
    expect(find.text('開始訓練'), findsOneWidget);

    for (final (key, title) in const [
      ('tutorialSectionFeatures', '主要功能'),
      ('tutorialSectionAdvanced', '進階功能'),
      ('tutorialSectionTips', '實用技巧'),
      ('tutorialSectionFaq', '常見問題'),
    ]) {
      await tester.scrollUntilVisible(find.byKey(Key(key)), 300);
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('常見問題可展開看答案', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TutorialPage()));
    await tester.pumpAndSettle();

    const q = Key('tutorialFaq-如何查看進步情況？');
    await tester.scrollUntilVisible(find.byKey(q), 300);
    expect(find.textContaining('訓練容量趨勢和個人記錄'), findsNothing);

    await tester.tap(find.byKey(q));
    await tester.pumpAndSettle();
    expect(find.textContaining('前往「數據」頁面'), findsOneWidget);
  });

  testWidgets('關於頁 aboutTutorialTile → 教學頁', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('aboutTutorialTile')), 300);
    await tester.tap(find.byKey(const Key('aboutTutorialTile')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '使用教學'), findsOneWidget);
    expect(find.text('歡迎使用 WorkItOut'), findsOneWidget);
  });

  testWidgets('設定頁 settingsTutorialEntry → 教學頁', (tester) async {
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('settingsTutorialEntry')), 200);
    await tester.tap(find.byKey(const Key('settingsTutorialEntry')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '使用教學'), findsOneWidget);
    expect(find.text('歡迎使用 WorkItOut'), findsOneWidget);
  });
}
