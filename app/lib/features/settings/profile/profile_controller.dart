// 個人資料頁(姓名/性別/身高)的讀寫控制。三欄只存 SharedPreferences,不進
// Drift——目前沒有其他頁面消費這三個值(dashboard/stats 只消費
// UserGoal.weeklyWorkoutGoal/targetWeight,見 goal_settings_controller.dart),
// 不需要跨表關聯或 userId 解析(`_resolveUserId` 複本慣例本檔用不到)。
//
// 姓名 key(2026-09-01 波 6 core brief 回報,大腦裁示):brief 原稱姓名沿用
// `kUserNameKey`,開檔核對後 onboarding_controller.dart 當時沒有這個 key,
// Onboarding 精靈本身從未收集姓名。裁示走「新增獨立 key」,不沿用
// session_controller.dart 的 `kAppleUserNameKey`(那是登入身分姓名,每次登入
// `_persistSession()` 會覆寫,拿來存個人資料頁編輯值會被登入流程靜默蓋掉)。
// 修復輪(review BLOCKER)後 `kUserNameKey`/`kProfileFilledOnceKey` 定義搬到
// onboarding_controller.dart、納入 `kOnboardingPersonalDataKeys`(登出/換帳號
// 清除清單),本檔單向 import。性別/身高沿用既有 `kUserGenderKey`/
// `kUserHeightKey`。
//
// 預填順序(brief 明定,三欄一致):既有 kUser* 值 → legacy_user_* → 空。
// 姓名額外一層顯示層建議(裁示追加):user_name 與 legacy_user_name 都空時,
// 用 `sessionControllerProvider` 的 `appleUserName`(登入身分姓名)當一次性
// 預填建議——只影響初始文字,不會回寫 kAppleUserNameKey 或 user_name;使用
// 者真的按下「儲存」才會把當下欄位文字寫進 user_name。
//
// 清空語義(2026-09-01 波 6 core review 修復輪,MAJOR):上面的預填鏈只回答
// 「沒存過時顯示什麼建議」,沒回答「使用者明確清空過之後呢」——姓名/身高
// 清空存檔後 stored 值是 null,下一次 build() 又被判定成「沒有」,legacy/
// apple 建議把舊值帶回來,「清空」意圖被悄悄撤銷。目標語義:預填是一次性的
// ——[kProfileFilledOnceKey] 旗標由 `save()` 成功存檔時設為 true,`build()`
// 看到旗標就不再諮詢 legacy_*/apple 建議,姓名/身高只看 stored 值本身(空就
// 是空)。旗標不因值改回非空而清掉(語意是「這個人已主動存過檔,之後的輸入
// 含刻意清空才是唯一真相」)。旗標在 [kOnboardingPersonalDataKeys] 內,登出/
// 換帳號時與個資一起清掉,新帳號重新走預填。性別不需要這層:
// `SegmentedButton` 一定選中其一,沒有「清空」狀態。
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
import '../../onboarding/onboarding_controller.dart'
    show kProfileFilledOnceKey, kUserGenderKey, kUserHeightKey, kUserNameKey;

const kLegacyUserNameKey = 'legacy_user_name';
const kLegacyUserGenderKey = 'legacy_user_gender';
const kLegacyUserHeightKey = 'legacy_user_height';

/// 性別選項值域,對照 iOS `ProfileView.Gender`(SettingsView.swift:132-135)——順序
/// 同 iOS(男性/女性/不指定),三個中文字面值本身就是儲存值。
const kProfileGenderOptions = ['男性', '女性', '不指定'];

/// 沒有任何既有/legacy 值時的預設性別(對應 iOS `?? .notSpecified`)。
const kProfileDefaultGender = '不指定';

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

    // 無條件 watch:即使旗標 true 不採用 appleName,登出/換帳號時
    // appleUserId/appleUserName 變動仍要觸發 rebuild,否則舊帳號的快取 state
    // 會殘留(非 autoDispose)。
    ref.watch(sessionControllerProvider.select((s) => s.appleUserId));
    final appleName = ref.watch(sessionControllerProvider.select((s) => s.appleUserName));

    // 預填一次性:存過檔(旗標 true)後只看 stored 值,不再諮詢 legacy/apple。
    final filledOnce = prefs.getBool(kProfileFilledOnceKey) ?? false;

    final storedName = prefs.getString(kUserNameKey);
    final String name;
    if (filledOnce) {
      name = storedName ?? '';
    } else {
      final legacyName = prefs.getString(kLegacyUserNameKey);
      name = _firstNonEmpty([storedName, legacyName, appleName]) ?? '';
    }

    final storedGender = prefs.getString(kUserGenderKey);
    final legacyGender = prefs.getString(kLegacyUserGenderKey);
    final gender = _firstValidGender([storedGender, legacyGender]) ?? kProfileDefaultGender;

    final storedHeight = prefs.getDouble(kUserHeightKey);
    final heightCm = filledOnce ? storedHeight : (storedHeight ?? prefs.getDouble(kLegacyUserHeightKey));

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
