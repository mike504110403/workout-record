// Smoke test for the 5-tab navigation shell: verifies all five tabs are
// present in the bottom NavigationBar and that switching tabs shows the
// corresponding placeholder page.
//
// Since wave 1 (login/onboarding/privacy gate) landed, reaching the tab
// shell requires a logged-in + onboarded + privacy-agreed SharedPreferences
// state — see app/lib/router.dart's `resolveAuthRedirect` and
// app/lib/app.dart's privacy-consent builder gate.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_record/app.dart';
import 'package:workout_record/features/auth/session_controller.dart';
import 'package:workout_record/features/auth/shared_preferences_provider.dart';
import 'package:workout_record/features/onboarding/onboarding_status.dart';
import 'package:workout_record/features/onboarding/privacy_consent_controller.dart';

void main() {
  testWidgets('5-tab shell shows all tabs and switches pages', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kAppleUserIdKey: 'test-user',
      kAppleUserNameKey: 'Test User',
      kAppleUserEmailKey: 'test@example.com',
      kHasCompletedOnboardingKey: true,
      kHasAgreedToAnalyticsKey: true,
      kHasAgreedToPrivacyKey: true,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const WorkItOutApp(),
      ),
    );
    await tester.pumpAndSettle();

    const tabLabels = ['首頁', '訓練', '數據', '歷史', '設定'];
    for (final label in tabLabels) {
      expect(find.text(label), findsWidgets);
    }

    // Starts on the dashboard tab.
    expect(find.widgetWithText(AppBar, '首頁'), findsOneWidget);

    // Switch to each remaining tab and verify its page becomes visible.
    for (final label in tabLabels.skip(1)) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, label), findsOneWidget);
    }
  });
}
