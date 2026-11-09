// 登入後「本機 Drift 舊資料 → Supabase」一次性上傳的觸發與狀態。
//
// 觸發:[startCloudUploadTrigger](main.dart 呼叫)監聽 session——啟動時已恢復
// session(fireImmediately)與之後登入成功都會呼叫 [CloudUploadController.runIfNeeded];
// 失敗不寫旗標,下次啟動自動重試,設定頁 [CloudUploadStatusTile] 也可手動重試。
//
// 守門(任一不成立就 no-op、不顯示狀態):雲端模式([cloudUploadSinkProvider] 非
// null)、已登入且 session uid = auth uid、本機資料 owner = 這個 uid(帳號隔離:
// 別人的本機資料不能上傳到我的帳號)、旗標未寫、本機有可上傳資料。
//
// 上傳本體與對應規則見 data/migration/cloud_upload.dart。
import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/migration/cloud_upload.dart';
import '../../data/providers.dart';
import '../../data/supabase_client.dart';
import '../auth/session_controller.dart';
import '../auth/shared_preferences_provider.dart';
import '../onboarding/onboarding_status.dart' show kHasCompletedOnboardingKey;

/// null = 非雲端模式(測試以 override 換成假件)。
final cloudUploadSinkProvider = Provider<CloudUploadSink?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseCloudUploadSink(client);
});

final localToCloudUploaderProvider = Provider<LocalToCloudUploader>(
  (ref) => DriftToSupabaseUploader(prefs: ref.watch(sharedPreferencesProvider)),
);

enum CloudUploadPhase { idle, uploading, succeeded, failed }

class CloudUploadStatus {
  const CloudUploadStatus(this.phase, {this.uploadedRows = 0, this.errorMessage});

  const CloudUploadStatus.idle() : this(CloudUploadPhase.idle);

  final CloudUploadPhase phase;
  final int uploadedRows;
  final String? errorMessage;
}

class CloudUploadController extends Notifier<CloudUploadStatus> {
  @override
  CloudUploadStatus build() => const CloudUploadStatus.idle();

  /// 符合條件時上傳一次;不符條件或上傳中重入回 null。不拋例外。
  Future<CloudUploadResult?> runIfNeeded() async {
    if (state.phase == CloudUploadPhase.uploading) return null;
    try {
      final sink = ref.read(cloudUploadSinkProvider);
      if (sink == null) return null;
      final session = ref.read(sessionControllerProvider);
      final uid = session.appleUserId;
      if (!session.isLoggedIn || uid == null || sink.currentUid != uid) return null;
      final prefs = ref.read(sharedPreferencesProvider);
      if (prefs.getString(kLocalDataOwnerUserIdKey) != uid) return null;

      final uploader = ref.read(localToCloudUploaderProvider);
      if (uploader.isCompleted(uid)) return null;
      final db = ref.read(appDatabaseProvider);
      if (!await uploader.hasUploadableData(db)) return null;

      state = const CloudUploadStatus(CloudUploadPhase.uploading);
      // users 列:Onboarding 完成才 ensure(同 SessionController 的 2026-11-10 裁示 A,
      // 未完成交給 OnboardingController 依「本次新建」決定初始體重)。
      final onboarded = prefs.getBool(kHasCompletedOnboardingKey) ?? false;
      final result = await uploader.uploadIfNeeded(
        db,
        sink,
        ensureUser: onboarded
            ? CloudUserProfile(name: session.appleUserName, email: session.appleUserEmail)
            : null,
      );
      state = result.success
          ? CloudUploadStatus(CloudUploadPhase.succeeded, uploadedRows: result.uploadedRows)
          : CloudUploadStatus(CloudUploadPhase.failed, errorMessage: result.errorMessage);
      if (!result.success) debugPrint('cloud upload failed: ${result.errorMessage}');
      return result;
    } catch (e) {
      state = CloudUploadStatus(CloudUploadPhase.failed, errorMessage: '$e');
      debugPrint('cloud upload crashed: $e');
      return CloudUploadResult(success: false, errorMessage: '$e');
    }
  }
}

final cloudUploadControllerProvider =
    NotifierProvider<CloudUploadController, CloudUploadStatus>(CloudUploadController.new);

/// main.dart 呼叫一次:恢復 session(立即觸發)與之後每次登入成功(uid 改變)都
/// 嘗試上傳。回傳 subscription 給測試關閉。
ProviderSubscription<SessionState> startCloudUploadTrigger(ProviderContainer container) {
  return container.listen<SessionState>(
    sessionControllerProvider,
    (previous, next) {
      if (!next.isLoggedIn) return;
      if (previous != null && previous.isLoggedIn && previous.appleUserId == next.appleUserId) {
        return;
      }
      unawaited(container.read(cloudUploadControllerProvider.notifier).runIfNeeded());
    },
    fireImmediately: true,
  );
}
