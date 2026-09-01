# code-reviewer 回報｜wave6-prefs（8180b40，範圍 a475121..wt/wave6/prefs，10 檔）

## Spec（1 條發現）

**MINOR — brief seam「換帳號情境不留跨帳號快取」被以設計決策 5 再解釋，但工人「張力偏離：無」低估了它**
- 位置：weight_unit.dart:55-64、theme_preference.dart:52-56、default_rest_seconds_preference.dart:24-27、one_rm_formula_preference.dart:41-45（四處 class doc 都寫「刻意不 watch sessionControllerProvider」）
- **特別查證點 (1) 結論：歸類站得住，不是漏列個資。** 證據三處：`legacy_prefs_importer.dart:43-44` 註解明文「`legacy_weight_unit`/`legacy_theme` 等 App 設定類 key 不算個資,刻意不在這份清單裡」；`kLegacyPrefsPersonalDataKeys`（importer:45-60）確實不含四項偏好；`session_controller.dart:286-311` 的 `confirmClearAndContinueLogin` 只清 Drift＋onboarding 個資＋legacy 個資清單＋匯入統計；決策文件「實作補充」節同調。新 key（weight_unit/theme_mode/default_rest_seconds/one_rm_formula）與既有 legacy 設定 key 同性質，不進清除清單是刻意且正確。
- 但 brief 條文字面是「不留跨帳號快取」，工人把它反解成「跨帳號共用才對」——結論我同意，歸類應該是「張力偏離」而非「設計決策」。建議大腦明示追認一句，別讓它以未裁狀態流進 merge。
- 附帶風險（PLAUSIBLE，現況 no-op）：controller 用 `ref.watch(sharedPreferencesProvider)`，只有 prefs **instance** 被換掉才重 build。若日後有人把這四個 key 加進清除清單，`prefs.remove()` 不會觸發 rebuild，provider 會留著舊 state 靜默失效。建議在四個檔的 class doc 補一句「日後列入清除清單須同步 invalidate」。

Spec 通過項（各一行，驗法）：
- 契約不可改條款 — 逐行 diff：enum `WeightUnit` 名／`fromStorageString`／`storageString`／`kLbPerKg = 2.20462262185`／`kgToDisplay`／`displayToKg`／`unitSuffix` **一字未動**；weight_unit.dart 的 +61/-8 全是新增 key 常數＋Controller＋provider body＋註解改寫（**查證點 (3) 結論：沒動換算函式或係數**）。
- `weightUnitProvider` 仍 `Provider<WeightUnit>` 同名（weight_unit.dart:106）；`PreferencesPage` 類名與 `const PreferencesPage({super.key})` 保留（改 ConsumerStatefulWidget 不影響呼叫端 `const PreferencesPage()`）。
- 四項 prefs key／legacy 預填／安全預設 — 對照 importer:204-250（key 名＋migrateString/Int/Bool 的型別保證）與 iOS `User.swift:59-62`（epley/brzycki/lander）、`:85-88`（light/dark/system）、`GlobalSettingsManager.swift:11-14`（預設 kg/system/epley/90）；`kDefaultRestSeconds = 90`（workout_ui_shared.dart:18）。映射無誤、無值域缺口。
- **查證點 (2) 主題雙來源優先權** — `theme_preference.dart:44-55` 實際行為（legacy_theme 存在即用、畸形落 system、**不**退回 legacy_is_dark_mode；完全沒有才看 is_dark_mode）與檔頭 8-14 註解宣稱**一致**，且 theme_preference_test.dart 有專門一條鎖住「sepia + is_dark_mode=true 仍落 system」。
- 「不做消費端接線」— `git diff --name-only` 僅 preferences/ 5 實作＋5 測試；settings_page.dart／router.dart／lib/data／pubspec／app.dart 零改動。（`default_rest_seconds_preference.dart:11` import `kDefaultRestSeconds` 只是拿常數當 fallback，非接線，brief 第 25 行明文要求核對該常數。）
- 驗收 2 的六類測試 — 四項各自獨立 fixture、無混測；契約回歸案例獨立命名存在。
- 禁止事項：無 push／merge／切分支（git log 只在 wt/wave6/prefs）；worktree status 乾淨（變異已還原）。
- 多做（scope creep）：無。

## Standards（6 條發現）

**MAJOR — 休息秒數 dropdown 在寫入失敗後不會退回舊顯示值，與檔頭宣稱矛盾**
- `preferences_page.dart:118-137`（`DropdownButtonFormField<int>`），矛盾對象是同檔 12-16 行「畫面(直接 watch provider)自然顯示回舊選項,不需要額外復原邏輯」。
- 證據（Flutter SDK `/opt/homebrew/share/flutter/packages/flutter/lib/src/material/dropdown.dart:1992-2007`）：`_DropdownButtonFormFieldState.didChange` 會先把內部 FormField state 設成使用者選的值再回呼 `onChanged`；`didUpdateWidget` **只在 `initialValue` 變動時**才 `setValue`。寫入失敗 → provider 維持 90 → `initialValue` 沒變 → 內部值停在 180 → 畫面顯示「180 秒」而實際偏好是 90。SegmentedButton 三項是全受控（`selected` 直接吃 provider），**不受影響**，宣稱只對那三項成立。
- 測試沒鎖住：`preferences_page_test.dart:245-258` 只斷言 provider 值＋浮錯＋無 spinner，因此綠。
- 建議修法：改用受控 `DropdownButton<int>`（value 直接綁 provider），或給該 FormField 加 `key: ValueKey(restSeconds)` 強制重建；並補一條「失敗後 dropdown 顯示 90 秒」的斷言。
- 不確定性：唯讀未實跑，結論由 SDK 原始碼推導（**PLAUSIBLE，把握高**）。派回時請工人先寫該斷言驗證會紅，再修。

**MINOR** — `default_rest_seconds_preference.dart:22` 註解混入簡體「负数秒数没有任何合理意义」，違繁中紀律（全 diff 只此一處）。→ 改繁體。
**MINOR** — `preferences_page.dart:24-27` 19 個秒數字面值硬寫，改區間時易漏改。→ `[for (var s = 30; s <= 300; s += 15) s]`。
**MINOR** — `preferences_page_test.dart:104/145` 用 `find.text('90 秒'/'120 秒')` + `findsWidgets` 弱斷言（hint 與選單項同文字，分不出來源）。→ 直接斷言 widget 的 `initialValue`/`hint`。
**MINOR（判斷題 / Duplicated Code）** — 四個 preference 檔的 `build()`（新 key → legacy → default）與 `setXxx()` 骨架高度雷同。各自 legacy 規則不同、明寫較可讀，**建議不動**，僅登記。
**MINOR（判斷題 / Duplicated Code）** — `weight_unit_test.dart:29-38` 兩條測試內容完全相同（無值→kg／契約回歸→kg）。brief 驗收 6 明文要求獨立契約回歸案例，屬刻意重複，僅登記。

Standards 通過項（各一行，驗法）：
- Riverpod 慣例 — `extends Notifier<T>` + `NotifierProvider` 與 session_controller:142／onboarding_status:22／privacy_consent_controller:28 同型；`ref.watch(sharedPreferencesProvider)` 照 onboarding_status 既有慣例。
- harness 慣例 — per-file `_container()` helper 與 privacy_consent_controller_test.dart:12 同型（repo 既有寫法，非重複味道）；`_Throwing*Controller` override 對照 dashboard_page_test.dart:77 `_ThrowingBodyWeightRepository` 同一套。
- 失敗路徑 UI（三項 SegmentedButton）— `_guardedWrite` try/finally 解除 loading＋`mounted` 檢查；文案 `'儲存失敗，請稍後再試'` 與 goal_settings_page.dart:55／add_body_weight_sheet.dart:59 一致。
- 邊界／不受信輸入 — 秒數 `_isValidRestSeconds` 擋 null/0/負；三個字串 key 未知值一律落安全預設；importer 的 migrate* 保證型別，`getInt`/`getBool` 型別衝突風險可忽略。
- 危險味道 — 無 print/debugPrint/TODO/FIXME/MUTATION 殘留、無註解掉的程式碼。
- 命名／註解風格與既有檔案一致。

既有問題（一行）：`one_rm_calculator.dart` 只有 Epley 實作，選 Brzycki/Lander 無計算本體——工人已註明，接線前需大腦裁示，非本波造成。

**總結：Spec 1 條（最嚴重＝MINOR，「換帳號不留跨帳號快取」的解釋性偏離，判定結論成立、只缺大腦追認）；Standards 6 條（最嚴重＝MAJOR，休息秒數 dropdown 失敗路徑顯示值不回退，與檔頭宣稱矛盾且測試未鎖）。**
