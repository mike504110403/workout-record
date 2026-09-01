// 個人資料頁(姓名/性別/身高)的讀寫控制。三欄只存 SharedPreferences,不進
// Drift——目前沒有其他頁面消費這三個值(dashboard/stats 只消費
// UserGoal.weeklyWorkoutGoal/targetWeight,見 goal_settings_controller.dart),
// 不需要跨表關聯或 userId 解析(`_resolveUserId` 複本慣例本檔用不到)。
//
// 姓名 key(2026-09-01 波 6 core brief 回報,大腦裁示):brief 原稱姓名沿用
// `kUserNameKey`,定義在 onboarding_controller.dart:28-33——開檔核對後那個
// key 不存在,Onboarding 精靈本身從未收集姓名。裁示走「在本檔新增獨立
// key」,不碰 onboarding_controller.dart(那邊不該無中生有加姓名欄位)、也
// 不沿用 session_controller.dart 的 `kAppleUserNameKey`(那是登入身分姓名,
// 每次登入 `_persistSession()` 會覆寫,拿來存個人資料頁編輯值會被登入流程
// 靜默蓋掉)。性別/身高照 brief 沿用既有 `kUserGenderKey`/`kUserHeightKey`
// (onboarding_controller.dart)。
//
// 預填順序(brief 明定,三欄一致):既有 kUser* 值 → legacy_user_* → 空。
// 姓名額外一層顯示層建議(裁示追加):user_name 與 legacy_user_name 都空時,
// 用 `sessionControllerProvider` 的 `appleUserName`(登入身分姓名)當一次性
// 預填建議——只影響初始文字,不會回寫 kAppleUserNameKey 或 user_name;使用
// 者真的按下「儲存」才會把當下欄位文字寫進 user_name。
//
// 清空語義(2026-09-01 波 6 core review 修復輪,MAJOR):上面的預填鏈只回答
// 「user_name 沒有值時要顯示什麼建議」,但沒回答「使用者明確清空過一次之後
// 呢」——姓名/身高原本用 `_firstNonEmpty`/`?? legacyHeight` 判斷「沒有」,
// 清空存檔後 stored 值變成空字串/null,下一次 build() 又被判定成「沒有」,
// legacy/apple 建議因此把舊值原封不動帶回來,使用者的「清空」意圖被悄悄
// 撤銷。目標語義(已裁):使用者明確存過一次檔之後,legacy/apple 建議鏈永久
// 停用,之後只看 stored 值本身(空就是空,不會再被建議填回)——用
// [kProfileFilledOnceKey] 這個旗標實作「一次性消費」:`save()` 每次成功
// 存檔都會設為 true,`build()` 一旦看到這個旗標,姓名/身高就不再諮詢
// legacy_*/apple 建議,直接以 stored 值(可能是 null/空)為準。旗標設下去
// 之後不會再清掉(即使之後又把值改回非空)——語意是「這個使用者的個人資料頁
// 已經被主動存過檔,從此以後這個人自己的輸入(含刻意清空)才是唯一真相」,
// 不是每次清空才切換,避免只用「值是否為空」這種脆弱訊號反推使用者意圖。
// 性別維持原本邏輯不受影響:`SegmentedButton` 一定選中三個選項之一,沒有
// 「清空」這個狀態可以表達,不需要這層一次性消費語義。
//
// 性別 legacy 值域:legacy_user_gender 是 iOS ProfileView.Gender 的
// rawValue("男性"/"女性"/"不指定",直接複製過來的中文字串),跟本頁
// `kProfileGenderOptions` 剛好同一組字面值,不需要轉換;若值不在值域內
// (資料損毀或未來 iOS 改字串)一律當「沒有」處理,回退空值鏈的下一環。
//
// 儲存失敗注入點:SharedPreferences 是具體類別,不像 Repository 有介面可以
// 在測試裡輕鬆做「模擬寫入失敗」的 fake,直接上 mock 套件需要新增 pubspec
// 依賴(brief 限定只能加 package_info_plus)。抽 [ProfilePrefsWriter] 這層
// 薄介面,測試比照 dashboard_page_test.dart `_ThrowingBodyWeightRepository`
// 的既有慣例,用 Provider override 注入會拋例外的 fake,不需要新依賴。
//
// 快取生命週期:`Notifier`(非 `AsyncNotifier`)——SharedPreferences 讀取是
// 同步 API,build() 不需要 loading/error 狀態。不是 autoDispose;`save()`
// 成功後 `ref.invalidateSelf()`,理由同 goal_settings_controller.dart:使用
// 者存檔返回、不重開 app 又進頁,build() 不會重跑,不 invalidate 表單會用
// 「存檔前」的舊快取 prefill。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/session_controller.dart' show sessionControllerProvider;
import '../../auth/shared_preferences_provider.dart';
import '../../onboarding/onboarding_controller.dart' show kUserGenderKey, kUserHeightKey;

/// 個人資料頁姓名欄的 key——onboarding_controller.dart 沒有對應的既有 key
/// (見本檔開頭注解),獨立新增。
const kUserNameKey = 'user_name';

const kLegacyUserNameKey = 'legacy_user_name';
const kLegacyUserGenderKey = 'legacy_user_gender';
const kLegacyUserHeightKey = 'legacy_user_height';

/// 「legacy/apple 建議一次性消費」旗標——姓名/身高清空語義的核心,見本檔
/// 開頭注解。`save()` 存檔成功即設 true,`build()` 看到 true 就不再諮詢
/// legacy_*/apple 建議鏈。
const kProfileFilledOnceKey = 'profile_filled_once';

/// 性別選項值域,對照 iOS `ProfileView.Gender`(SettingsView.swift)——三個
/// 中文字面值本身就是儲存值,不是額外的 enum 對照表。
const kProfileGenderOptions = ['不指定', '男性', '女性'];

const _kDefaultGender = '不指定';

class ProfileFormState {
  const ProfileFormState({required this.name, required this.gender, required this.heightCm});

  final String name;
  final String gender;
  final double? heightCm;
}

/// 個人資料頁存檔的實際寫入動作——抽成可覆寫介面只為了測試注入失敗,見
/// 本檔開頭注解。
abstract class ProfilePrefsWriter {
  Future<void> write(
    SharedPreferences prefs, {
    required String name,
    required String gender,
    required double? heightCm,
  });
}

class _RealProfilePrefsWriter implements ProfilePrefsWriter {
  const _RealProfilePrefsWriter();

  @override
  Future<void> write(
    SharedPreferences prefs, {
    required String name,
    required String gender,
    required double? heightCm,
  }) async {
    // 姓名同身高一樣,留空存檔要移除 key、不是寫一個空字串佔位(2026-09-01
    // review 修復輪 MAJOR——見本檔開頭注解的清空語義說明)。單用 remove()
    // 本身還不夠(legacy fallback 一樣會把空 key 判定成「沒有」而回填),
    // 真正擋住回填的是下面的 [kProfileFilledOnceKey] 旗標,這裡的 remove()
    // 只是讓「清空」在 prefs 裡誠實地表現成「沒有值」,兩者搭配才完整。
    if (name.isEmpty) {
      await prefs.remove(kUserNameKey);
    } else {
      await prefs.setString(kUserNameKey, name);
    }
    await prefs.setString(kUserGenderKey, gender);
    // 身高允許清空回未設定(留空存檔):nullable 欄位的「清空」不能用
    // copyWith 的 `??` 語意表達(ledger 首雷,見 ~/.claude/ledgers/
    // workout-record.md)——這裡沒有 copyWith,但同樣的道理適用於「留空該
    // 移除 key,不是寫入某個佔位數值」,所以用 remove() 而非 setDouble(0)。
    if (heightCm != null) {
      await prefs.setDouble(kUserHeightKey, heightCm);
    } else {
      await prefs.remove(kUserHeightKey);
    }
    // 一次性消費旗標:存過一次檔之後,legacy/apple 建議鏈永久停用(本檔
    // 開頭注解)。每次成功存檔都重設為 true(已經是 true 也無妨,冪等)。
    await prefs.setBool(kProfileFilledOnceKey, true);
  }
}

final profilePrefsWriterProvider = Provider<ProfilePrefsWriter>(
  (ref) => const _RealProfilePrefsWriter(),
);

class ProfileController extends Notifier<ProfileFormState> {
  @override
  ProfileFormState build() {
    final prefs = ref.watch(sharedPreferencesProvider);

    final storedName = prefs.getString(kUserNameKey);
    final legacyName = prefs.getString(kLegacyUserNameKey);
    final appleName = ref.watch(sessionControllerProvider.select((s) => s.appleUserName));
    final name = _firstNonEmpty([storedName, legacyName, appleName]) ?? '';

    final storedGender = prefs.getString(kUserGenderKey);
    final legacyGender = prefs.getString(kLegacyUserGenderKey);
    final gender = _firstValidGender([storedGender, legacyGender]) ?? _kDefaultGender;

    final storedHeight = prefs.getDouble(kUserHeightKey);
    final legacyHeight = prefs.getDouble(kLegacyUserHeightKey);
    final heightCm = storedHeight ?? legacyHeight;

    return ProfileFormState(name: name, gender: gender, heightCm: heightCm);
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String? _firstValidGender(List<String?> values) {
    for (final value in values) {
      if (value != null && kProfileGenderOptions.contains(value)) return value;
    }
    return null;
  }

  Future<void> save({required String name, required String gender, required double? heightCm}) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await ref.read(profilePrefsWriterProvider).write(
          prefs,
          name: name,
          gender: gender,
          heightCm: heightCm,
        );
    ref.invalidateSelf();
  }
}

final profileControllerProvider = NotifierProvider<ProfileController, ProfileFormState>(
  ProfileController.new,
);
