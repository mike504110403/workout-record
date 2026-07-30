// 隱私同意浮層的狀態控制。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Services/PrivacyConsentService.swift`
// + `Views/Privacy/PrivacyConsentView.swift`。
//
// 兩個勾選框在使用者按下「同意並繼續」之前只是頁面本地狀態(對等 iOS
// `@State`),按下才一次寫入 SharedPreferences 三個 key。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/shared_preferences_provider.dart';

const kHasAgreedToAnalyticsKey = 'has_agreed_to_analytics';
const kHasAgreedToPrivacyKey = 'has_agreed_to_privacy';
const kPrivacyConsentDateKey = 'privacy_consent_date';

class PrivacyConsentState {
  const PrivacyConsentState({
    this.hasAgreedToAnalytics = false,
    this.hasAgreedToPrivacy = false,
    this.consentDate,
  });

  final bool hasAgreedToAnalytics;
  final bool hasAgreedToPrivacy;
  final DateTime? consentDate;

  bool get isFullyAgreed => hasAgreedToAnalytics && hasAgreedToPrivacy;

  PrivacyConsentState copyWith({
    bool? hasAgreedToAnalytics,
    bool? hasAgreedToPrivacy,
    DateTime? consentDate,
  }) {
    return PrivacyConsentState(
      hasAgreedToAnalytics: hasAgreedToAnalytics ?? this.hasAgreedToAnalytics,
      hasAgreedToPrivacy: hasAgreedToPrivacy ?? this.hasAgreedToPrivacy,
      consentDate: consentDate ?? this.consentDate,
    );
  }
}

class PrivacyConsentController extends Notifier<PrivacyConsentState> {
  @override
  PrivacyConsentState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final consentMillis = prefs.getInt(kPrivacyConsentDateKey);
    return PrivacyConsentState(
      hasAgreedToAnalytics: prefs.getBool(kHasAgreedToAnalyticsKey) ?? false,
      hasAgreedToPrivacy: prefs.getBool(kHasAgreedToPrivacyKey) ?? false,
      consentDate: consentMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(consentMillis),
    );
  }

  void setAnalyticsAgreed(bool value) {
    state = state.copyWith(hasAgreedToAnalytics: value);
  }

  void setPrivacyAgreed(bool value) {
    state = state.copyWith(hasAgreedToPrivacy: value);
  }

  /// 「同意並繼續」——兩者皆勾才寫入,對等 iOS 按鈕的 disabled 條件。
  Future<void> agreeAndContinue() async {
    if (!state.isFullyAgreed) return;

    final now = DateTime.now();
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(kHasAgreedToAnalyticsKey, true);
    await prefs.setBool(kHasAgreedToPrivacyKey, true);
    await prefs.setInt(kPrivacyConsentDateKey, now.millisecondsSinceEpoch);

    state = state.copyWith(consentDate: now);
  }
}

final privacyConsentControllerProvider =
    NotifierProvider<PrivacyConsentController, PrivacyConsentState>(
  PrivacyConsentController.new,
);
