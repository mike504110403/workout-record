// 隱私同意的落地狀態控制。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Services/PrivacyConsentService.swift`
// + `Views/Privacy/PrivacyConsentView.swift`。
//
// 兩個勾選框是 PrivacyConsentPage 的頁面本地狀態(StatefulWidget setState,
// 對等 iOS `@State`),這裡的 controller 完全不追蹤勾選框目前勾了幾個——只
// 負責「已經按下同意並繼續、真的寫進 SharedPreferences 的那個結果」。App 的
// 隱私同意 gate(app.dart)看的是 [PrivacyConsentState.isAgreed],不是「兩個
// 勾選框是否都勾了」,避免使用者勾滿兩框但還沒按按鈕時 gate 就提早放行——
// 勾選動作本身不該有任何持久化副作用。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/shared_preferences_provider.dart';

const kHasAgreedToAnalyticsKey = 'has_agreed_to_analytics';
const kHasAgreedToPrivacyKey = 'has_agreed_to_privacy';
const kPrivacyConsentDateKey = 'privacy_consent_date';

class PrivacyConsentState {
  const PrivacyConsentState({this.consentDate});

  final DateTime? consentDate;

  /// 對等 App 的隱私同意 gate 條件:同意結果已經落地才算數。
  bool get isAgreed => consentDate != null;

  PrivacyConsentState copyWith({DateTime? consentDate}) {
    return PrivacyConsentState(consentDate: consentDate ?? this.consentDate);
  }
}

class PrivacyConsentController extends Notifier<PrivacyConsentState> {
  @override
  PrivacyConsentState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final consentMillis = prefs.getInt(kPrivacyConsentDateKey);
    return PrivacyConsentState(
      consentDate: consentMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(consentMillis),
    );
  }

  /// 「同意並繼續」——呼叫端(PrivacyConsentPage)已經用兩個勾選框的本地
  /// 狀態擋住按鈕的 enabled 條件,這裡不重複檢查,直接落地三個 key。
  Future<void> agreeAndContinue() async {
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
