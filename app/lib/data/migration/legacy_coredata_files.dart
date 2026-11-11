// 舊 iOS 版(CoreData)遺留物的平台分流入口:
// - [LegacyCoreDataFiles]:`WorkoutRecord.sqlite` 與 `-wal`/`-shm` 三個檔案的清除。
//   native(io)走 legacy_coredata_files_io.dart;web 走 no-op stub(同
//   coredata_importer.dart 的分流理由:web 不可能有舊檔,且不能 import dart:io)。
// - [legacyAppleUserIdReaderProvider]:讀舊 iOS 存在 UserDefaults `AppleIDUserID`
//   的 Apple user identifier(MethodChannel,跟 LegacyPrefsImporter 同一條 channel)。
// - [legacyUserDefaultsClearerProvider]:刪帳號時清掉舊 iOS 留在 UserDefaults 的
//   個資與 Apple ID 殘留(同一條 channel,原生端用明確 key 清單刪)。
//
// 用途見 SessionController:刪帳號後清掉舊檔(否則舊 iOS 資料永遠留在裝置上);
// 首次登入時比對舊 Apple ID,避免共用裝置的第一個登入者認領別人的舊資料。
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'legacy_coredata_files_io.dart'
    if (dart.library.js_interop) 'legacy_coredata_files_web.dart';

export 'legacy_coredata_files_io.dart'
    if (dart.library.js_interop) 'legacy_coredata_files_web.dart';

/// 可在測試以 `LegacyCoreDataFiles(supportDirPathProvider: ...)` 指向暫存目錄覆寫。
final legacyCoreDataFilesProvider = Provider<LegacyCoreDataFiles>((ref) => const LegacyCoreDataFiles());

const _legacyPrefsChannelName = 'com.mikelin.workitout/legacy_prefs';
const _legacyAppleUserIdMethod = 'getLegacyAppleUserId';
const _clearLegacyUserDefaultsMethod = 'clearLegacyUserDefaults';

/// 預設讀法:走 MethodChannel。非 iOS / Web / 測試環境沒有原生端
/// (MissingPluginException)或任何例外一律視為「沒有舊值」(null)——
/// 呼叫端對 null 的處理是照舊認領,所以這裡失敗是 fail-open,不擋登入。
Future<String?> _readLegacyAppleUserId() async {
  try {
    return await const MethodChannel(_legacyPrefsChannelName)
        .invokeMethod<String>(_legacyAppleUserIdMethod);
  } catch (_) {
    return null;
  }
}

/// 舊 iOS 版登入時存的 Apple user identifier;沒有(全新安裝、或舊版從未登入)為 null。
final legacyAppleUserIdReaderProvider =
    Provider<Future<String?> Function()>((ref) => _readLegacyAppleUserId);

/// 預設清法:走 MethodChannel 叫原生端刪舊 UserDefaults。盡力而為——非 iOS / 沒有
/// 原生端 / 任何例外都吞掉(刪帳號在雲端已成功,不能因為清不掉本機殘留而改變結果)。
Future<void> _clearLegacyUserDefaults() async {
  try {
    await const MethodChannel(_legacyPrefsChannelName)
        .invokeMethod<void>(_clearLegacyUserDefaultsMethod);
  } catch (_) {}
}

/// 刪帳號後清掉舊 iOS 留在 UserDefaults 的資料(Apple ID/姓名/信箱、個人資料、
/// 自訂動作等)。測試可覆寫。
final legacyUserDefaultsClearerProvider =
    Provider<Future<void> Function()>((ref) => _clearLegacyUserDefaults);
