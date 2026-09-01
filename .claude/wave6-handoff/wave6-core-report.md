# wave6-core 完成報告

## Commit

`c558e4e` (分支 `wt/wave6/core`,worktree `/Users/mike/Documents/self/workout-record-wt-score`)

```
feat(settings): 波 6 core——設定主頁 section 化、個人資料頁、關於頁

七項入口(個人資料/目標設定/我的模板/偏好設定/關於/登出/ImportRetryTile);
個人資料頁存 SharedPreferences(姓名/性別/身高,既有值→legacy→登入身分建議
→空的預填鏈);關於頁用 package_info_plus 顯示版本,隱私內文對齊本機儲存
現況。姓名 key(user_name)為本波新增——brief 誤植的 kUserNameKey 實際不存
在,已與大腦核對走新增獨立 key(不沿用會被登入流程覆寫的 kAppleUserNameKey)。
```

## git diff --stat

```
 app/lib/features/settings/about/about_page.dart          | 147 +++++++++++++
 app/lib/features/settings/profile/profile_controller.dart| 154 +++++++++++++
 app/lib/features/settings/profile/profile_page.dart      | 173 ++++++++++++++
 app/lib/features/settings/settings_page.dart              |  67 ++++++-
 app/pubspec.lock                                           |  32 +++
 app/pubspec.yaml                                           |   1 +
 app/test/features/settings/about/about_page_test.dart     |  37 ++++
 app/test/features/settings/profile/profile_page_test.dart | 177 +++++++++++++
 app/test/features/settings/settings_page_test.dart        | 138 ++++++++++++
 9 files changed, 921 insertions(+), 5 deletions(-)
```

全部落在 brief 允許改動範圍內(`lib/features/settings/`、`pubspec.yaml`、`test/features/settings/`)。未動 `preferences/` 子目錄、`router.dart`、`lib/data/`、其他 feature。`pubspec.yaml` 只加了 `package_info_plus: ^9.0.0`(實際解析 9.0.1)。

## 測試與 analyze 實際輸出

```
$ flutter analyze
Analyzing app...
No issues found! (ran in 4.5s)

$ flutter test
...
00:21 +510: All tests passed!
```

497(基線)+ 13(新增)= 510,全綠。新增測試分布:
- `test/features/settings/settings_page_test.dart`:6 條
- `test/features/settings/profile/profile_page_test.dart`:5 條
- `test/features/settings/about/about_page_test.dart`:2 條

既有 `settings_logout_test.dart` 未改動,原樣通過(登出行為斷言未弱化)。

## 驗收標準逐條對照

1. **`flutter analyze` → 0 issues**:✅ 見上。
2. **`flutter test` → 全綠(基線 497＋新增)**:✅ 510/510。
3. **測試覆蓋 1:主頁七項入口各自導頁正確**:✅ `settings_page_test.dart` 五條各自 tap 對應入口、斷言目的頁 `AppBar` 標題出現(個人資料/目標設定/訓練模板/偏好設定/關於)。變異驗證:每條測試獨立斷言目的頁真的出現(不是只斷言 ListTile 存在),拔掉任一入口的 `Navigator.push` 該條測試必紅。另補一條「五入口＋登出按鈕同時存在,互不排擠」。
4. **測試覆蓋 2:個人資料 legacy 預填 + 既有值優先**:✅
   - 「legacy 預填」:只種 `legacy_user_name`/`legacy_user_gender`/`legacy_user_height`,斷言三欄帶入 legacy 值。
   - 「既有值優先於 legacy」:kUser*/legacy_* 兩組都種,斷言畫面顯示 kUser* 值、legacy 值不出現。
   - 額外(裁示追加的顯示層建議,已實作):三者皆空時姓名欄用 `kAppleUserNameKey`(登入身分姓名)一次性預填建議,補一條測試覆蓋。
5. **測試覆蓋 3:個人資料儲存 + 失敗路徑**:✅
   - 「儲存」:填三欄按儲存,直接查 `prefs.getString(kUserNameKey)`/`getString(kUserGenderKey)`/`getDouble(kUserHeightKey)` 斷言型別與值正確,且頁面被 pop。
   - 「儲存失敗」:用可覆寫的 `ProfilePrefsWriter`(見下方張力說明)注入拋錯 fake,斷言浮錯 SnackBar 顯示、頁面沒被 pop、欄位與按鈕解除 disable(不卡 loading)。
6. **測試覆蓋 4:登出流程既有斷言全數維持綠**:✅ `settings_logout_test.dart` 未修改,全數通過。
7. **測試覆蓋 5:關於頁版本顯示**:✅ `PackageInfo.setMockInitialValues` mock,斷言 `版本 2.0.0 (6)` 顯示;另補一條斷言隱私內文不含「匯出」「刪除帳」字樣、含「裝置本機」陳述(對應隱私文案紀律)。

## 張力與偏離清單

1. **brief 前提與程式碼不符(已停工回報、已裁示,見對話記錄)**:brief 稱姓名沿用既有 `kUserNameKey`(onboarding_controller.dart:28-33),核對後該 key 不存在,Onboarding 精靈本身沒有姓名欄位。大腦核驗後裁示走「在 `profile_controller.dart` 新增獨立 key `user_name`」,不碰 `onboarding_controller.dart`。已依裁示實作,並在 `profile_controller.dart` 開頭注解記錄始末,供之後讀碼者理解為何這裡有一個乍看像是該進 onboarding 的 key 卻沒有放在那裡。
2. **新增 `ProfilePrefsWriter` 抽象層(brief 未明定,屬實作判斷)**:brief 要求個人資料儲存要有「失敗路徑」測試,但 `SharedPreferences` 是具體類別,測試環境沒有現成方式讓它的寫入拋錯;而 `mockito` 雖然出現在 `pubspec.lock`,查證後**只是transitive 依賴**(沒有任何專案套件把它列為直接/dev 依賴),不能拿來 import——brief 又明定 pubspec 只准加 `package_info_plus`。因此比照 `dashboard_page_test.dart`/`goal_settings_page_test.dart` 既有的「`_ThrowingXxxRepository extends Repository`」慣例,抽了一層薄介面 `ProfilePrefsWriter`(預設實作是真的寫 prefs),測試用 Provider override 注入拋錯版本。這不算違反「不新增依賴」的紀律,但多了一個 brief 沒明講的小型抽象,回報供覆核。
3. **關於頁隱私內文非逐字對照 `AboutView.swift`**:brief 要求「參照 iOS AboutView.swift 內文精神但刪掉與實作不符的句子」。查證後 `AboutView.swift` 自己的 `AboutPrivacyPolicyView` 段落其實沒有直接寫「可透過設定頁匯出/刪除資料」這句(那個具體宣稱其實在另一支更完整的 `Views/Privacy/PrivacyPolicyView.swift`,不是 `AboutView.swift`,見下方「順路發現」)。判斷 brief 的意思是精神指引而非逐字引用,改以 Flutter 版已經上線、經隱私審查的 `privacy_consent_page.dart` 文案(該檔開頭注解:「逐字對照 iOS PrivacyConsentView,該文案已符合資料存本機現狀」)為事實依據改寫關於頁隱私段落,結構(資料收集範圍/儲存方式/使用目的/保護承諾)沿用 `AboutView.swift` 的段落骨架。
4. **About 頁 FutureBuilder 補上 error 處理(非 brief 明講,但屬「非同步失敗路徑一律要處理」紀律的自然延伸)**:實作中發現若不處理 `PackageInfo.fromPlatform()` 的 error 完成狀態,測試環境(無平台 channel)會讓畫面卡在轉圈圈動畫,導致 `pumpAndSettle` 永遠 timeout——這其實是任何呼叫這個 API 卻沒處理錯誤分支的通用陷阱,已補上 try/catch + `ConnectionState.done` 判斷,錯誤時顯示「版本未知」而非無限轉圈。

## 順路發現(範圍外,未處理,僅記錄)

1. iOS 端存在**兩份**隱私政策文案,彼此不一致:`Views/About/AboutView.swift` 內嵌的 `AboutPrivacyPolicyView`(較保守,沒有匯出/刪除宣稱)vs. 獨立檔案 `Views/Privacy/PrivacyPolicyView.swift`(較完整,`PrivacyPolicyView.swift:436-443` 明寫「刪除權」「資料可攜權(以結構化格式匯出您的資料)」,但 iOS 全 App 找不到任何對應的匯出/刪帳號 UI 實作)。這是 iOS 既有的文案-實作落差,本波已避開(關於頁改寫用不到那份文案),但這份 `PrivacyPolicyView.swift` 本身的病灶還在 iOS 端,建議之後處理 App Store 隱私改版(波 7 排定項)時一併核實。
2. `mockito` 目前只以 transitive 依賴身分出現在 `pubspec.lock`(被某個直接依賴的 dev_dependencies 帶入 resolve 圖,但因為是 dev_dependency 不會往上傳播),專案裡沒有任何檔案 import 它、也沒有列在 `pubspec.yaml` 的 `dependencies`/`dev_dependencies`。之後若有工人想沿用 `flutter-tester` skill 建議的 mockito 模式寫測試,會發現實際上不能直接 import——供留意。

## 已知雷內聯核對(brief「禁止事項」段)

- `_resolveUserId` 複本慣例:本波個人資料頁純 SharedPreferences 讀寫,沒有 userId 解析需求,未用到、未新增第七份複本。
- copyWith `??` 語意清 null 的雷:`ProfileFormState` 沒有 `copyWith`(每次 `build()` 直接建新物件);身高「留空清空既有值」改用 `SharedPreferences.remove()` 而非 `setDouble(0)`,已在 `profile_controller.dart` 內聯註解點名這個雷、說明為何這裡不會踩到。
- legacy key 清單以 `legacy_prefs_importer.dart` 實際 key 名為準:動筆前已開檔核對(`legacy_user_name`/`legacy_user_gender`/`legacy_user_height` 確認存在,型別分別是 String/String/double)。
