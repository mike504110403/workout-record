import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_record/data/secure_session_storage.dart';
import 'package:workout_record/data/supabase_client.dart';

const _key = 'sb-abc-auth-token';

/// 記憶體版安全儲存;可指定哪些操作丟例外(模擬裝置鎖定 / Keychain 錯誤)。
class _FakeSecure implements SecureKeyValueStore {
  _FakeSecure([Map<String, String>? initial]) : data = {...?initial};
  final Map<String, String> data;
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('keychain locked');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('keychain write error');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('keychain delete error');
    data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    if (failDelete) throw StateError('keychain delete error');
    data.clear();
  }
}

/// 包一層 SharedPreferences,可指定 setBool / remove 丟例外,並記錄呼叫順序
/// (模擬搬移中途被殺:只做完一半的寫入)。
class _FlakyPrefs implements SharedPreferences {
  _FlakyPrefs(this.inner);
  final SharedPreferences inner;
  bool failSetBool = false;
  bool failRemove = false;
  final List<String> log = [];

  @override
  String? getString(String key) => inner.getString(key);
  @override
  bool? getBool(String key) => inner.getBool(key);
  @override
  bool containsKey(String key) => inner.containsKey(key);

  @override
  Future<bool> setBool(String key, bool value) async {
    log.add('setBool');
    if (failSetBool) throw StateError('killed before setBool');
    return inner.setBool(key, value);
  }

  @override
  Future<bool> remove(String key) async {
    log.add('remove');
    if (failRemove) throw StateError('killed before remove');
    return inner.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 同一個 fake store 與 prefs 再建一個實例 = 模擬下一次啟動。
Future<SecureSessionStorage> _relaunch(_FakeSecure secure) async {
  final s = SecureSessionStorage(persistSessionKey: _key, secure: secure);
  await s.initialize();
  return s;
}

Future<SecureSessionStorage> _storage(_FakeSecure secure, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final s = SecureSessionStorage(persistSessionKey: _key, secure: secure);
  await s.initialize();
  return s;
}

void main() {
  group('升級搬移', () {
    test('舊 key 有、安全儲存沒有 → 搬過去並刪掉舊 key,且讀得到', () async {
      final secure = _FakeSecure();
      final s = await _storage(secure, {_key: 'OLD_SESSION'});

      expect(secure.data[_key], 'OLD_SESSION');
      expect(await s.accessToken(), 'OLD_SESSION');
      expect(await s.hasAccessToken(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_key), isFalse);
      expect(prefs.getBool(kSecureSessionInstalledKey), isTrue);
    });

    test('旗標存在(搬移被中斷過)且安全儲存已有新 session → 不被舊值覆蓋,舊 key 仍刪除', () async {
      final secure = _FakeSecure({_key: 'NEW_SESSION'});
      final s = await _storage(secure, {_key: 'OLD_SESSION', kSecureSessionInstalledKey: true});

      expect(await s.accessToken(), 'NEW_SESSION');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_key), isFalse);
    });

    test('升級者(旗標不存在但有舊 key)不會被當成重灌而清掉 session;Keychain 殘留不可信,一律用舊明文覆蓋', () async {
      final secure = _FakeSecure({_key: 'STALE_OTHER_ACCOUNT'});
      final s = await _storage(secure, {_key: 'OLD_SESSION'});
      expect(await s.accessToken(), 'OLD_SESSION');
      expect(secure.data[_key], 'OLD_SESSION');
    });

    test('旗標不存在的搬移:寫安全儲存失敗 → 當沒有 session(不讀回殘留),舊 key 保留', () async {
      final secure = _FakeSecure({_key: 'STALE_OTHER_ACCOUNT'})..failWrite = true;
      final s = await _storage(secure, {_key: 'OLD_SESSION'});
      secure.failWrite = false;

      expect(await s.accessToken(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key), 'OLD_SESSION');
    });

    test('搬移收尾先寫旗標再刪舊 key;旗標寫入前被殺 → 下次啟動仍從舊 key 搬,不被當重灌清掉', () async {
      SharedPreferences.setMockInitialValues({_key: 'OLD_SESSION'});
      final flaky = _FlakyPrefs(await SharedPreferences.getInstance())..failSetBool = true;
      final secure = _FakeSecure();
      final s = SecureSessionStorage(persistSessionKey: _key, secure: secure, prefsLoader: () async => flaky);
      await s.initialize();

      expect(flaky.log, ['setBool']); // 先寫旗標;它失敗後不得繼續刪舊 key
      expect(flaky.inner.getString(_key), 'OLD_SESSION');

      final second = await _relaunch(secure);
      expect(await second.accessToken(), 'OLD_SESSION');
    });

    test('搬移收尾順序:setBool 在 remove 之前', () async {
      SharedPreferences.setMockInitialValues({_key: 'OLD_SESSION'});
      final flaky = _FlakyPrefs(await SharedPreferences.getInstance());
      await SecureSessionStorage(persistSessionKey: _key, secure: _FakeSecure(), prefsLoader: () async => flaky)
          .initialize();
      expect(flaky.log, ['setBool', 'remove']);
    });

    test('搬移時讀安全儲存失敗 → 保留舊 key 供下次重試,不崩潰', () async {
      final secure = _FakeSecure()..failRead = true;
      final s = await _storage(secure, {_key: 'OLD_SESSION', kSecureSessionInstalledKey: true});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key), 'OLD_SESSION');
      expect(await s.accessToken(), isNull);
    });

    test('搬移時寫安全儲存失敗 → 保留舊 key 供下次重試', () async {
      final secure = _FakeSecure()..failWrite = true;
      await _storage(secure, {_key: 'OLD_SESSION'});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key), 'OLD_SESSION');
    });
  });

  group('iOS 重灌陷阱', () {
    test('旗標不存在(重灌)→ 清掉 Keychain 殘留 session 並寫旗標', () async {
      final secure = _FakeSecure({_key: 'STALE_FROM_OLD_INSTALL'});
      final s = await _storage(secure, {});

      expect(secure.data.containsKey(_key), isFalse);
      expect(await s.accessToken(), isNull);
      expect(await s.hasAccessToken(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kSecureSessionInstalledKey), isTrue);
    });

    test('重灌清除用 deleteAll:另一個專案(dev / prod)的 token 也一併清掉', () async {
      final secure = _FakeSecure({_key: 'STALE', 'sb-other-auth-token': 'OTHER_PROJECT'});
      await _storage(secure, {});

      expect(secure.data, isEmpty);
    });

    test('旗標存在(正常重啟)→ 保留安全儲存裡的 session', () async {
      final secure = _FakeSecure({_key: 'LIVE'});
      final s = await _storage(secure, {kSecureSessionInstalledKey: true});

      expect(await s.accessToken(), 'LIVE');
    });

    test('清殘留失敗 → 這次啟動當沒有 session、旗標不寫;之後 persist 成功即恢復', () async {
      final secure = _FakeSecure({_key: 'STALE'})..failDelete = true;
      final s = await _storage(secure, {});

      expect(await s.accessToken(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kSecureSessionInstalledKey), isNull);

      await s.persistSession('FRESH_LOGIN');
      expect(await s.accessToken(), 'FRESH_LOGIN');
    });
  });

  group('讀寫失敗不崩潰', () {
    test('讀取丟例外 → accessToken 為 null、hasAccessToken 為 false', () async {
      final secure = _FakeSecure({_key: 'X'});
      final s = await _storage(secure, {kSecureSessionInstalledKey: true});
      secure.failRead = true;

      expect(await s.accessToken(), isNull);
      expect(await s.hasAccessToken(), isFalse);
    });

    test('寫入 / 刪除丟例外 → 不擲出', () async {
      final secure = _FakeSecure();
      final s = await _storage(secure, {kSecureSessionInstalledKey: true});
      secure.failWrite = true;
      secure.failDelete = true;

      await s.persistSession('S');
      await s.removePersistedSession();
    });

    test('SharedPreferences 載入失敗 → initialize 不擲出', () async {
      final s = SecureSessionStorage(
        persistSessionKey: _key,
        secure: _FakeSecure(),
        prefsLoader: () async => throw StateError('prefs broken'),
      );
      await s.initialize();
    });

    test('initialize 最外層失敗 → 狀態不明,當沒有 session(即使安全儲存裡有 token)', () async {
      final s = SecureSessionStorage(
        persistSessionKey: _key,
        secure: _FakeSecure({_key: 'MAYBE_STALE'}),
        prefsLoader: () async => throw StateError('prefs broken'),
      );
      await s.initialize();

      expect(await s.accessToken(), isNull);
      expect(await s.hasAccessToken(), isFalse);
    });
  });

  group('persist / remove', () {
    test('persistSession 寫入、removePersistedSession 刪除', () async {
      final secure = _FakeSecure();
      final s = await _storage(secure, {kSecureSessionInstalledKey: true});

      await s.persistSession('S1');
      expect(secure.data[_key], 'S1');
      expect(await s.hasAccessToken(), isTrue);

      await s.removePersistedSession();
      expect(secure.data.containsKey(_key), isFalse);
      expect(await s.hasAccessToken(), isFalse);
    });
  });

  group('persist 成功補旗標與清舊 key(跨啟動)', () {
    test('重灌清殘留失敗那次啟動 persist 成功 → 下次啟動不把剛登入的 session 當殘留清掉', () async {
      final secure = _FakeSecure({_key: 'STALE'})..failDelete = true;
      final s = await _storage(secure, {});
      secure.failDelete = false;

      await s.persistSession('FRESH_LOGIN');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kSecureSessionInstalledKey), isTrue);

      final second = await _relaunch(secure);
      expect(await second.accessToken(), 'FRESH_LOGIN');
    });

    test('搬移失敗留著舊 key 後 persist 成功 → 舊 key 被刪,下次啟動不被舊值覆蓋', () async {
      final secure = _FakeSecure()..failWrite = true;
      final s = await _storage(secure, {_key: 'OLD_SESSION'});
      secure.failWrite = false;

      await s.persistSession('NEW_LOGIN');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_key), isFalse);

      final second = await _relaunch(secure);
      expect(await second.accessToken(), 'NEW_LOGIN');
    });

    test('persist 成功清除 stale 狀態,同一實例立即可讀', () async {
      final secure = _FakeSecure({_key: 'STALE'})..failDelete = true;
      final s = await _storage(secure, {});
      expect(await s.accessToken(), isNull);
      secure.failDelete = false;

      await s.persistSession('FRESH');
      expect(await s.accessToken(), 'FRESH');
    });

    test('persist 寫入失敗 → 不補旗標、不刪舊 key', () async {
      final secure = _FakeSecure()..failWrite = true;
      final s = await _storage(secure, {_key: 'OLD_SESSION'});

      await s.persistSession('X');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kSecureSessionInstalledKey), isNull);
      expect(prefs.getString(_key), 'OLD_SESSION');
    });
  });

  group('removePersistedSession(跨啟動)', () {
    test('刪除成功 → 順手刪舊明文 key,下次啟動不會把它搬回來', () async {
      final secure = _FakeSecure({_key: 'LIVE'});
      final s = await _storage(secure, {kSecureSessionInstalledKey: true});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, 'LEFTOVER_LEGACY'); // 模擬舊明文 key 殘留

      await s.removePersistedSession();
      expect(prefs.containsKey(_key), isFalse);

      final second = await _relaunch(secure);
      expect(await second.accessToken(), isNull);
    });

    test('刪除失敗 → 這次啟動當沒有 session、旗標被清掉;下次啟動走重灌清除路徑重試', () async {
      final secure = _FakeSecure({_key: 'LIVE'});
      final s = await _storage(secure, {kSecureSessionInstalledKey: true});
      secure.failDelete = true;

      await s.removePersistedSession();
      expect(await s.accessToken(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kSecureSessionInstalledKey), isFalse);

      secure.failDelete = false;
      final second = await _relaunch(secure);
      expect(secure.data, isEmpty);
      expect(await second.accessToken(), isNull);
      expect(prefs.getBool(kSecureSessionInstalledKey), isTrue);
    });

    test('刪除失敗後下次啟動仍刪不掉 → 仍當沒有 session,旗標不寫', () async {
      final secure = _FakeSecure({_key: 'LIVE'});
      final s = await _storage(secure, {kSecureSessionInstalledKey: true});
      secure.failDelete = true;
      await s.removePersistedSession();

      final second = await _relaunch(secure);
      expect(await second.accessToken(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kSecureSessionInstalledKey), isNull);
    });
  });

  group('平台選擇', () {
    test('Web → null(沿用套件預設,不換實作)', () {
      expect(createSessionLocalStorage(supabaseUrl: 'https://abc.supabase.co', isWeb: true), isNull);
    });

    test('非 Web → SecureSessionStorage,key 與套件預設一致', () {
      final s = createSessionLocalStorage(supabaseUrl: 'https://abc.supabase.co', isWeb: false);
      expect(s, isA<SecureSessionStorage>());
      expect((s! as SecureSessionStorage).persistSessionKey, 'sb-abc-auth-token');
    });

    test('buildAuthOptions:非 Web 時 localStorage 是 SecureSessionStorage', () {
      final o = buildAuthOptions(supabaseUrl: 'https://abc.supabase.co', isWeb: false);
      expect(o.localStorage, isA<SecureSessionStorage>());
    });

    test('buildAuthOptions:Web 時 localStorage 為 null(沿用套件預設)', () {
      expect(buildAuthOptions(supabaseUrl: 'https://abc.supabase.co', isWeb: true).localStorage, isNull);
    });

    test('supabaseSessionKeyFor 取 host 第一段', () {
      expect(supabaseSessionKeyFor('https://imudkbxvkefzafptqhae.supabase.co'), 'sb-imudkbxvkefzafptqhae-auth-token');
    });
  });
}
