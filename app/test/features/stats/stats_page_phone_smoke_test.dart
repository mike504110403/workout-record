// WAVE4 merge 接線後的手機畫布 smoke:三個真子頁在 390×844(iPhone 級寬度)
// 逐一切過,不得有 RenderFlex overflow 等例外。
//
// 背景:波 4 B 線的統計卡網格在 800×600 測試畫布全綠、實機 390pt 寬卻溢出
// 13px(review 抓到後已修)。這支測試把「組裝後的三個子頁都過一次手機
// 畫布」釘成迴歸防線,防同型 bug 再次只在大畫布下驗證。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/stats/stats_page.dart';

import '../../data/test_helpers.dart';

void main() {
  testWidgets('390×844 手機畫布:三個子頁逐一切過,無 overflow 例外', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = openTestDatabase();
    addTearDown(db.close);
    await seedTestUser(db);
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
    expect(tester.takeException(), isNull, reason: '訓練統計子頁(預設)不得 overflow');

    await tester.tap(find.byKey(const Key('statsSegment-0')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '體重子頁不得 overflow');

    await tester.tap(find.byKey(const Key('statsSegment-2')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '三項子頁不得 overflow');
  });
}
