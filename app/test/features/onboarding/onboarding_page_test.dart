// OnboardingPage widget seam:「跳過教學」在第一頁就能用;基本資訊頁
// (index 1)體重非有效數值時「下一步」是 disabled,填入有效體重才 enabled
// (對等 iOS `canProceed(from: .basicInfo)`)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/providers.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_page.dart';

import '../../data/test_helpers.dart';

void main() {
  testWidgets('第一頁(歡迎頁)就看得到「跳過教學」按鈕', (tester) async {
    SharedPreferences.setMockInitialValues({kAppleUserIdKey: 'test-user'});
    final prefs = await SharedPreferences.getInstance();
    final db = openTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(home: OnboardingPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('歡迎使用健身記錄'), findsOneWidget);
    expect(find.byKey(const Key('skipOnboardingButton')), findsOneWidget);
  });

  testWidgets('基本資訊頁:體重欄位空白時「下一步」disabled,填有效數值後 enabled', (tester) async {
    SharedPreferences.setMockInitialValues({kAppleUserIdKey: 'test-user'});
    final prefs = await SharedPreferences.getInstance();
    final db = openTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(home: OnboardingPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 從歡迎頁(index 0)前進到基本資訊頁(index 1)。
    await tester.tap(find.byKey(const Key('onboardingNextButton')));
    await tester.pumpAndSettle();
    expect(find.text('基本資訊'), findsOneWidget);

    FilledButton nextButton() =>
        tester.widget<FilledButton>(find.byKey(const Key('onboardingNextButton')));

    expect(nextButton().onPressed, isNull, reason: '體重欄位還是空的,下一步應該 disabled');

    await tester.enterText(find.byKey(const Key('onboardingWeightField')), '70');
    await tester.pumpAndSettle();

    expect(nextButton().onPressed, isNotNull, reason: '填了有效體重之後下一步應該 enabled');
  });

  testWidgets('基本資訊頁:體重欄位填非數值文字時「下一步」仍是 disabled', (tester) async {
    SharedPreferences.setMockInitialValues({kAppleUserIdKey: 'test-user'});
    final prefs = await SharedPreferences.getInstance();
    final db = openTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(home: OnboardingPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboardingNextButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('onboardingWeightField')), 'abc');
    await tester.pumpAndSettle();

    final nextButton =
        tester.widget<FilledButton>(find.byKey(const Key('onboardingNextButton')));
    expect(nextButton.onPressed, isNull);
  });
}
