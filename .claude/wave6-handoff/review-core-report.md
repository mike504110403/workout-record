# code-review：wave6-core（a475121..wt/wave6/core，c558e4e + 5617899）

（SendMessage 工具在本 session 不可用，落檔回報）

## Spec

對照 brief 八欄逐條查。**1 條發現（minor）**。

### MINOR — brief 目標「section 化的設定主頁」未見分組
`app/lib/features/settings/settings_page.dart:53-107`
brief 目標段：「把設定 tab …做成 **section 化**的設定主頁」。實作是單一扁平 `ListView`，五個入口＋一條 `Divider(height: 1)`＋登出＋ImportRetryTile，沒有 section 標題／`Card` 群組（iOS `SettingsView.swift` 是多個 `Section`）。brief 的 seam 段與驗收標準只列「七項入口」與導頁正確，未硬性要求分組，故列 minor 判斷題。
建議：要嘛加分組標題（個人／功能／其他）對齊 iOS，要嘛大腦裁定「扁平即可」並在 wip 註記措辭落差，不必退工人。

### Spec 通過項（各一行，驗法）
- 七項入口齊備：settings_page.dart:54-105 逐項核對 brief seam 1-7（個人資料/目標設定/我的模板/偏好設定/關於/登出/ImportRetryTile）。
- 登出未弱化：`_confirmSignOut` 與 `signOutButton` key 與 a475121 版**逐字相同**（`git show a475121:...settings_page.dart` 對照），`settings_logout_test.dart` 未進 diff。
- ImportRetryTile 行為一致：widget 檔未動，僅由列表中段移到尾端（brief 明定「位置放列表尾」）；自帶 `checkPermanentlyFailed` FutureBuilder 條件渲染邏輯完全未改。
- 預填鏈：姓名 profile_controller.dart:110-113（user_name→legacy→apple 建議→空，已裁偏離不報）；性別 :115-117、身高 :119-121（kUser*→legacy→預設/空）。
- 儲存失敗路徑：profile_page.dart:70-89（catch→SnackBar、不 pop、finally 解 `_isSaving`）＋ profile_page_test.dart 對應測試。
- 關於頁隱私文案：about_page.dart:80-119 無匯出／刪除帳號宣稱，about_page_test.dart 以 `findsNothing('匯出'/'刪除帳')` 正面守住；符合 repo CLAUDE.md 地雷。
- pubspec 只加一個依賴：yaml +1 行 `package_info_plus: ^9.0.0`；lock 新增條目僅 package_info_plus 9.0.1 及其 transitive（http/platform_interface/win32）。
- 未動 `preferences/`、`router.dart`、`lib/data/`、其他 feature（diff --stat 9 檔全在允許範圍）。
- legacy key 名與 `legacy_prefs_importer.dart:46-50` 實際 key 一致；型別 String/String/double 相符。
- 性別值域對照 iOS `SettingsView.swift:132-136`（男性/女性/不指定）一致。
- 無 scope creep：新增物僅 ProfilePrefsWriter（已裁）、About FutureBuilder error 分支（屬 brief【UI】非同步失敗紀律），未碰禁止清單任一項。

## Standards

**7 條發現：1 blocker（判斷，見說明）、1 major、5 minor。**

### BLOCKER（判斷題，若大腦認定姓名敏感度低可降 MAJOR）— 新 key `user_name` 未納入任何個資清除清單，登出／換帳號會殘留
`app/lib/features/settings/profile/profile_controller.dart:46`（新增 `const kUserNameKey = 'user_name'`）
對照既有契約：
- `lib/features/onboarding/onboarding_controller.dart:16` 註解：「實際清除由 `kOnboardingPersonalDataKeys` 顯式列舉，不做前綴掃描」；清單在 :39-48（含 user_gender / user_height，**無 user_name**）。
- `lib/features/auth/session_controller.dart:378-390` `signOut()` 只清 apple 三 key ＋ `kOnboardingPersonalDataKeys` → 登出後 `user_name` 留在裝置。
- `lib/features/auth/session_controller.dart:281-311` `confirmClearAndContinueLogin()`（換帳號「清除並繼續」，該方法註解自述 security review 2026-08-04 major）清 `kOnboardingPersonalDataKeys` ＋ `kLegacyPrefsPersonalDataKeys`（`legacy_prefs_importer.dart:45-58`）→ **`user_name` 兩份清單都不在，前一位使用者的姓名會殘留給新帳號**，並在新帳號的個人資料頁被當成「既有值」預填（profile_controller.dart:110）。
- 既有測試 `test/features/auth/session_controller_test.dart:155` 甚至明文守住「不在清單內的 user_ 前綴 key 不會被清除」——本波正好新增了一個個資性質的 user_ key 卻沒進清單。
建議修法（擇一，避免 onboarding→settings 反向 import 造成循環）：(a) 把 `kUserNameKey` 常數移到 `onboarding_controller.dart` 並加入 `kOnboardingPersonalDataKeys`；(b) 保留常數位置，在 `session_controller` 的兩處清除點各補一次 remove（較零散）；(c) 新增一份 `kProfilePersonalDataKeys` 由 session_controller 一併迭代。無論哪種，補一條測試：signOut 與 confirmClearAndContinueLogin 後 `prefs.getString('user_name') == null`。
註：這超出「已裁不碰 onboarding_controller 加姓名欄位」的裁示範圍（裁示談的是不無中生有加 onboarding 欄位，不等於免除清除契約），故仍報。

### MAJOR — 姓名「留空存檔」無法真的清空，會被 legacy／登入名重新填回
`profile_controller.dart:87`（`setString(kUserNameKey, name)`，name 為空字串也寫入）＋ `:110-113`（`_firstNonEmpty` 把空字串視為「沒有」→ 落到 legacy_user_name／appleUserName）
行為：使用者清空姓名按儲存 → prefs 存 `''` → 重進頁面又顯示 legacy／登入名，再按一次儲存就把不想要的名字寫回。與同檔身高的處理不一致（:93-97 空值走 `remove()`，註解還特地點名 ledger 首雷「nullable 清空」）。
建議：`name.isEmpty ? prefs.remove(kUserNameKey) : prefs.setString(...)`，並在預填鏈用「key 存在與否」而非「非空字串」判斷是否往下 fallback；補一條測試：清空姓名存檔後重進頁面姓名欄為空（拔掉 remove 必紅）。
（PLAUSIBLE：未實跑，純讀碼推導；現有測試沒有覆蓋這條路徑。）

### MINOR — About 頁 FutureBuilder 的 future 在 build 內建立
`about_page.dart:47-56`（`future: () async {...}()`）
`AboutPage` 是 StatelessWidget，任何 rebuild（主題／MediaQuery 變動、父層重建）都會重新產生 Future，UI 閃回 spinner 再顯示版本。建議改 StatefulWidget 在 `initState` 建 future，或用 `FutureProvider`（與 repo 其他頁面 Riverpod 慣例一致）。

### MINOR（smell: Duplicated Code）— 隱私文案兩份
`about_page.dart:80-118` vs `lib/features/privacy/privacy_consent_page.dart:82-107`：段落標題與條目字串幾乎逐字重複。之後任一份改動（例如接同步後要改「不會上傳雲端」）容易只改一處。建議抽成共用的 `privacy_texts.dart` 常數或共用 widget，兩邊引用。判斷題：目前兩處語境不同（同意頁 vs 關於頁），維持兩份也說得過去。

### MINOR（smell: Feature Envy／Middle Man 邊緣）— `ProfilePrefsWriter.write` 由呼叫端傳 prefs
`profile_controller.dart:68-75`、`:140-149`：`save()` 自己 `ref.read(sharedPreferencesProvider)` 再把 prefs 當第一個位置參數餵給 writer，`save()` 本身除了轉發與 invalidateSelf 沒別的職責。writer 直接持有／自取 prefs（例如 provider 內 `ref.watch`）介面會乾淨一些。抽象層本身已裁准，此條只針對介面形狀，判斷題不阻擋。

### MINOR — 性別選項順序與 iOS 不同
`profile_controller.dart:53`：Flutter 為 `['不指定','男性','女性']`，iOS `SettingsView.swift:132-135` enum 順序為 男性／女性／不指定。值域一致（brief 只要求值域對照），僅呈現順序差異；預設值 `不指定` 與 iOS `?? .notSpecified` 一致。要不要對齊順序是可逆 UI 取捨。

### MINOR — 測試註解語句破碎＋全形逗號混入
`test/features/settings/profile/profile_page_test.dart:145-150`：「…重進一次也不會，比如未來若誰不小心在 build() 裡加了『順手回寫』也會被這裡的第二次斷言逮到。」句子沒接完整；且用了全形「，」，本檔其餘註解一律半形「,」。斷言本身正確有效（直接查 prefs＋pop 後重進二次驗證），只是註解需要重寫一句。

### Standards 通過項（各一行，驗法）
- 登出邏輯與 key：與 a475121 版逐字 diff 比對，無弱化。
- 身高清空用 `remove()` 非 `setDouble(0)`：profile_controller.dart:93-97 讀碼＋`profile_page_test` 儲存測試型別斷言（`getDouble` 178.5）。
- `_prefillIfNeeded` 一次性預填：profile_page.dart:34-47，與 `goal_settings_page.dart:64-71` 既有慣例同形。
- `_HeightParse` 區分 valid(null) / invalid：對齊既有 `_TargetWeightParse`；`_canSave` 擋不合法輸入。
- Riverpod 生命週期已交代：`Notifier`＋非 autoDispose＋save 後 `invalidateSelf()`（profile_controller.dart:36-42 註解），與 goal_settings_controller 一致。
- 測試 harness：settings_page_test 用 in-memory DB＋mock prefs，照 dashboard/goal 慣例；ProviderContainer 皆 `addTearDown(dispose)`。
- 五條導頁測試斷言目的頁 AppBar 標題（非只驗 ListTile 存在），拔 push 必紅的設計成立。
- 繁中硬編文案、無 debug print、無註解掉的死碼、無殘留 TODO（grep diff 全量）。
- 聯絡 email 與 iOS `AboutView.swift:214` 一致，非隨手編造。
- pubspec.lock 只多 package_info_plus 家族，無其他版本漂移。

## 既有問題（一行，不處理）
- 隱私文案（`privacy_consent_page.dart:85-86`，本波關於頁沿用）宣稱收集「應用程式使用數據與操作行為／設備資訊與錯誤報告」，但 `app/lib` 目前 grep 不到任何 analytics／crash SDK（僅 iOS 有 Firebase）——文案-實作落差，源頭非本次改動。

## 總結
Spec 1 條（最嚴重＝minor：「section 化」措辭未落實分組）；Standards 7 條（最嚴重＝blocker：新增個資 key `user_name` 未進 signOut／換帳號清除清單，會跨帳號殘留）。兩軸不互相排序。
