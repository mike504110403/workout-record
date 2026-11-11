/// Supabase session(含 refresh token)的安全儲存。
///
/// 套件預設把 session 明文放 SharedPreferences(iOS 的 NSUserDefaults),會跟著
/// 未加密的裝置備份走;這裡改存 iOS Keychain / Android Keystore。Web 沒有
/// Keychain,維持套件預設(見 [createSessionLocalStorage] 回傳 null)。
///
/// 三個行為要點:
/// 1. **升級搬移**:舊版 session 在 SharedPreferences 的套件 key 下,第一次啟動搬進
///    安全儲存並刪掉舊 key,既有登入者不用重登。
/// 2. **重灌陷阱**:iOS Keychain 在刪除 App 後仍保留。重灌後 SharedPreferences
///    是空的(旗標不存在、舊 key 也不在),第一次啟動要先清掉 Keychain 裡殘留的
///    session,否則會帶著上一個帳號的 token 自動登入。
/// 3. **不可崩潰**:安全儲存讀寫失敗(裝置鎖定、Keychain 錯誤)一律吞掉:讀失敗
///    視為沒有 session(重登即可),寫失敗只是這次不落地。
library;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

/// 「這個安裝是否跑過安全儲存初始化」旗標(存在 SharedPreferences)。
/// SharedPreferences 隨 App 刪除而消失、Keychain 不會——兩者的落差正是判斷重灌的依據。
const kSecureSessionInstalledKey = 'secure_session_storage_installed';

/// 安全儲存的最小介面(測試用 fake 取代,不碰真 Keychain)。
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// 清空整個安全儲存。App 沒有其他東西放在這裡;dev 與 prod 專案的 session key
  /// 不同,只刪目前專案的 key 會留下另一個專案的 token。
  Future<void> deleteAll();
}

/// 真實實作:iOS 用 `first_unlock_this_device`——開機解鎖一次後背景也讀得到
/// (token 自動更新需要),且不進備份、不隨裝置轉移。
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// 套件預設的 session key,與 `supabase_flutter` 的 `Supabase.initialize` 一致,
/// 舊版明文 session 才找得到、搬得過來。
String supabaseSessionKeyFor(String url) => 'sb-${Uri.parse(url).host.split('.').first}-auth-token';

/// 依平台決定 session 儲存:Web 回傳 null(= 沿用套件預設),其餘走安全儲存。
LocalStorage? createSessionLocalStorage({
  required String supabaseUrl,
  bool? isWeb,
  SecureKeyValueStore secure = const FlutterSecureKeyValueStore(),
}) {
  if (isWeb ?? kIsWeb) return null;
  return SecureSessionStorage(persistSessionKey: supabaseSessionKeyFor(supabaseUrl), secure: secure);
}

class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({
    required this.persistSessionKey,
    this.secure = const FlutterSecureKeyValueStore(),
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  final String persistSessionKey;
  final SecureKeyValueStore secure;
  final Future<SharedPreferences> Function() _prefsLoader;

  /// 狀態不確定(初始化失敗、重灌清不掉殘留、登出刪不掉)時為 true:這次啟動一律
  /// 當沒有 session,直到下一次 [persistSession] 成功蓋掉它。
  /// 原則:任何不確定的狀態都當作「沒有 session」(最壞是重登一次),不讓舊 token 被讀回。
  bool _staleUnclearable = false;

  @override
  Future<void> initialize() async {
    try {
      final prefs = await _prefsLoader();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy != null) {
        await _migrateLegacy(prefs, legacy);
      } else if (prefs.getBool(kSecureSessionInstalledKey) != true) {
        await _clearStaleAfterReinstall(prefs);
      }
    } catch (e, st) {
      // 初始化失敗不能讓 App 起不來;但安全儲存內容此刻不可信,當沒有 session,最壞是重登。
      _staleUnclearable = true;
      debugPrint('secure session init failed: $e\n$st');
    }
  }

  /// 舊版明文 session → 安全儲存。
  /// - 旗標不存在:Keychain 現有內容不可信(可能是上一次安裝殘留的別的帳號),
  ///   一律用舊明文覆蓋。
  /// - 旗標存在(搬到一半被殺、舊 key 沒刪掉):Keychain 已有就不覆蓋(那是較新的)。
  /// 收尾順序:先寫旗標再刪舊 key——反過來的話,中間被殺會留下「旗標不存在、舊 key
  /// 也不在」,下次啟動把剛搬好的 session 當重灌殘留清掉。
  /// 讀寫安全儲存失敗(狀態未知)會擲出,由 [initialize] 保留舊 key、下次啟動重試。
  Future<void> _migrateLegacy(SharedPreferences prefs, String legacy) async {
    if (prefs.getBool(kSecureSessionInstalledKey) != true) {
      await secure.write(persistSessionKey, legacy);
    } else {
      final existing = await secure.read(persistSessionKey);
      if (existing == null || existing.isEmpty) {
        await secure.write(persistSessionKey, legacy);
      }
    }
    await prefs.setBool(kSecureSessionInstalledKey, true);
    await prefs.remove(persistSessionKey);
  }

  /// 旗標不存在又沒有舊 key = 全新安裝、重灌,或上次登出沒刪成功;Keychain 裡若有
  /// 殘留一律清掉。用 deleteAll:dev 與 prod 專案的 key 不同,只刪目前專案會留下
  /// 另一個專案的 token。
  Future<void> _clearStaleAfterReinstall(SharedPreferences prefs) async {
    try {
      await secure.deleteAll();
    } catch (e) {
      _staleUnclearable = true;
      debugPrint('secure session stale clear failed: $e');
      return; // 旗標不寫,下次啟動再清
    }
    await prefs.setBool(kSecureSessionInstalledKey, true);
  }

  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;

  @override
  Future<String?> accessToken() async {
    if (_staleUnclearable) return null;
    try {
      final value = await secure.read(persistSessionKey);
      return (value == null || value.isEmpty) ? null : value;
    } catch (e) {
      debugPrint('secure session read failed: $e');
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await secure.delete(persistSessionKey);
    } catch (e) {
      // 刪不掉:Keychain 裡可能還有 token。這次啟動當沒有 session,並清掉旗標,
      // 讓下次啟動走重灌清除路徑(deleteAll)重試。
      _staleUnclearable = true;
      debugPrint('secure session delete failed: $e');
      await _prefsBestEffort((prefs) => prefs.remove(kSecureSessionInstalledKey));
      return;
    }
    _staleUnclearable = false;
    // 舊明文 key 若還在(例如搬移被中斷),一併刪掉,免得之後被當成「較新的」搬回來。
    await _prefsBestEffort((prefs) async {
      if (prefs.containsKey(persistSessionKey)) await prefs.remove(persistSessionKey);
    });
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await secure.write(persistSessionKey, persistSessionString);
    } catch (e) {
      debugPrint('secure session write failed: $e');
      return;
    }
    _staleUnclearable = false;
    // 寫入成功 = 這個安裝的安全儲存已被本 App 擁有:補寫旗標(避免下次啟動被當重灌清掉),
    // 並刪掉舊明文 key(避免之後被舊值覆蓋)。
    await _prefsBestEffort((prefs) async {
      if (prefs.getBool(kSecureSessionInstalledKey) != true) {
        await prefs.setBool(kSecureSessionInstalledKey, true);
      }
      if (prefs.containsKey(persistSessionKey)) await prefs.remove(persistSessionKey);
    });
  }

  /// 輔助的 SharedPreferences 動作失敗不影響主流程(不崩潰);失敗只會讓下次啟動
  /// 走較保守的路徑(視為沒有 session、重登)。
  Future<void> _prefsBestEffort(Future<void> Function(SharedPreferences prefs) action) async {
    try {
      await action(await _prefsLoader());
    } catch (e) {
      debugPrint('secure session prefs update failed: $e');
    }
  }
}
