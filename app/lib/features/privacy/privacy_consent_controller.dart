// 隱私同意的落地狀態控制。對應 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Services/PrivacyConsentService.swift`
// + `Views/Privacy/PrivacyConsentView.swift`。
//
// 勾選框是 PrivacyConsentPage 的頁面本地狀態(StatefulWidget setState,
// 對等 iOS `@State`),這裡的 controller 完全不追蹤勾選框是否勾了——只
// 負責「已經按下同意並繼續、真的寫進 SharedPreferences 的那個結果」。App 的
// 隱私同意 gate(app.dart)看的是 [PrivacyConsentState.isAgreed],不是「勾選框
// 是否勾了」,避免使用者勾了但還沒按按鈕時 gate 就提早放行——
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

  /// 「同意並繼續」——呼叫端(PrivacyConsentPage)已經用勾選框的本地
  /// 狀態擋住按鈕的 enabled 條件,這裡不重複檢查,直接落地三個 key
  /// (頁面雖只剩一個勾選框,兩個既有同意 key 仍都寫,舊版讀取端不受影響)。
  Future<void> agreeAndContinue() async {
    final now = DateTime.now();
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(kHasAgreedToAnalyticsKey, true);
    await prefs.setBool(kHasAgreedToPrivacyKey, true);
    await prefs.setInt(kPrivacyConsentDateKey, now.millisecondsSinceEpoch);

    state = PrivacyConsentState(consentDate: now);
  }
}

final privacyConsentControllerProvider =
    NotifierProvider<PrivacyConsentController, PrivacyConsentState>(
  PrivacyConsentController.new,
);
