import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/session_controller.dart';
import 'features/onboarding/privacy_consent_controller.dart';
import 'features/onboarding/privacy_consent_page.dart';
import 'router.dart';

class WorkItOutApp extends ConsumerWidget {
  const WorkItOutApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Work It Out',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      // 隱私同意浮層蓋在整個 App 上層(對等 iOS `checkPrivacyConsent()`
      // sheet,不管目前停在 Onboarding 還是主畫面,登入後未同意就強制擋下)。
      builder: (context, child) {
        final isLoggedIn = ref.watch(sessionControllerProvider).isLoggedIn;
        final hasFullyAgreed = ref.watch(privacyConsentControllerProvider).isFullyAgreed;
        if (isLoggedIn && !hasFullyAgreed) {
          return const PrivacyConsentPage();
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
