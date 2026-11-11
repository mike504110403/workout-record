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
// 只有 v1 完成旗標的使用者(舊版已上傳過)走靜默補送:不進 uploading,只有實際補送了
// 子列(送出筆數不含動作複本)才顯示 succeeded;沒資料要補或失敗都維持 idle(失敗只
// debugPrint,下次啟動再試)。否則每位舊使用者升級後都會看到一次「正在同步/已同步完成
// 共 0 筆」。
//
// 重入:啟動恢復 session 與登入成功可能幾乎同時觸發,守門檢查之間有 await;旗標必須在
// 第一個 await 之前設好,否則兩次呼叫都會通過檢查而各跑一次上傳。
//
// 上傳本體與對應規則見 data/migration/cloud_upload.dart。
import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart' show AppDatabase;
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

/// 失敗文案(使用者看得懂的一句話;原始例外只進 debugPrint)。
String cloudUploadFailureMessage(CloudUploadFailureKind kind) => switch (kind) {
      CloudUploadFailureKind.network => '網路連線不穩或中斷,請確認網路後再按「重試上傳」。',
      CloudUploadFailureKind.other => '上傳時發生問題,請稍後再按「重試上傳」。',
    };

enum CloudUploadPhase { idle, uploading, succeeded, failed }

class CloudUploadStatus {
  const CloudUploadStatus(
    this.phase, {
    this.uploadedRows = 0,
    this.unownedRows = 0,
    this.errorMessage,
  });

  const CloudUploadStatus.idle() : this(CloudUploadPhase.idle);

  final CloudUploadPhase phase;
  final int uploadedRows;

  /// 因 id 已被其他帳號佔用而未上傳的筆數(成功時才有意義)。
  final int unownedRows;
  final String? errorMessage;
}

class CloudUploadController extends Notifier<CloudUploadStatus> {
  @override
  CloudUploadStatus build() => const CloudUploadStatus.idle();

  /// 執行中(含守門檢查與靜默補送;靜默路徑狀態不進 uploading,只能靠這個擋重入)。
  bool _running = false;

  /// 符合條件時上傳一次;不符條件或上傳中重入回 null。不拋例外。
  Future<CloudUploadResult?> runIfNeeded() async {
    if (state.phase == CloudUploadPhase.uploading || _running) return null;
    // 在第一個 await 之前設好(見檔頭「重入」)。
    _running = true;
    var silent = false;
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

      if (uploader.isLegacyCompleted(uid)) {
        silent = true;
        return await _repairSilently(uploader, db, sink);
      }

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
          ? CloudUploadStatus(
              CloudUploadPhase.succeeded,
              uploadedRows: result.uploadedRows,
              unownedRows: result.unownedTotal,
            )
          : CloudUploadStatus(
              CloudUploadPhase.failed,
              errorMessage: cloudUploadFailureMessage(result.failureKind ?? CloudUploadFailureKind.other),
            );
      if (!result.success) debugPrint('cloud upload failed: ${result.errorMessage}');
      if (result.unownedCounts.isNotEmpty) {
        debugPrint('cloud upload: 屬於其他帳號、未上傳的筆數 ${result.unownedCounts}');
      }
      return result;
    } catch (e) {
      final kind = classifyCloudUploadError(e);
      if (!silent) {
        state = CloudUploadStatus(CloudUploadPhase.failed, errorMessage: cloudUploadFailureMessage(kind));
      }
      debugPrint('cloud upload crashed: $e');
      return CloudUploadResult(success: false, errorMessage: '$e', failureKind: kind);
    } finally {
      _running = false;
    }
  }

  /// v1 補送(見檔頭):不經 uploading;子表實際送出筆數 > 0 才 succeeded(補送路徑的
  /// uploadedRows 不含動作複本),其餘維持原狀態。
  /// v1 完成後本來就不再 ensure users,這裡不帶 ensureUser。
  Future<CloudUploadResult> _repairSilently(
    LocalToCloudUploader uploader,
    AppDatabase db,
    CloudUploadSink sink,
  ) async {
    final result = await uploader.uploadIfNeeded(db, sink);
    if (!result.success) {
      debugPrint('cloud upload (v1 補送) failed, 下次啟動再試: ${result.errorMessage}');
    } else if (result.uploadedRows > 0) {
      state = CloudUploadStatus(
        CloudUploadPhase.succeeded,
        uploadedRows: result.uploadedRows,
        unownedRows: result.unownedTotal,
      );
    }
    if (result.unownedCounts.isNotEmpty) {
      debugPrint('cloud upload (v1 補送): 屬於其他帳號、未上傳的筆數 ${result.unownedCounts}');
    }
    return result;
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
