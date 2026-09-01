# 波 6 — preferences 工人(B)完成報告

## Commit

`8180b40` — `feat(settings): 波6——偏好設定頁四項真身(重量單位/主題/預設休息秒數/1RM公式)`
分支 `wt/wave6/prefs`,worktree `/Users/mike/Documents/self/workout-record-wt-prefs`。

## git diff --stat

```
 .../default_rest_seconds_preference.dart           |  56 +++++
 .../preferences/one_rm_formula_preference.dart     |  74 ++++++
 .../settings/preferences/preferences_page.dart     | 163 ++++++++++++-
 .../settings/preferences/theme_preference.dart     |  86 +++++++
 .../features/settings/preferences/weight_unit.dart |  61 ++++-
 .../default_rest_seconds_preference_test.dart      |  74 ++++++
 .../one_rm_formula_preference_test.dart            |  67 +++++
 .../preferences/preferences_page_test.dart         | 270 +++++++++++++++++++++
 .../preferences/theme_preference_test.dart         |  85 +++++++
 .../settings/preferences/weight_unit_test.dart     |  69 ++++++
 10 files changed, 997 insertions(+), 8 deletions(-)
```

## 實際輸出

`flutter analyze`(worktree `app/` 下):
```
Analyzing app...
No issues found! (ran in 1.0s)
```

`flutter test`(全量):
```
00:24 +532: All tests passed!
```
基線 497 + 新增 35 = 532,對得上。新增測試檔獨立跑一次:
`flutter test test/features/settings/preferences/` → `+35`,全綠。

## 驗收標準逐條對照

1. **`flutter analyze` → 0 issues** ✅;**`flutter test` → 全綠(497+新增)** ✅(532/532)。
2. 六個測試類別逐項對照(四項偏好各自獨立 fixture,不混測):
   - **無任何值→預設正確**:kg / system / 90 秒 / epley,四項各一條 provider-level 測試 + 一條 widget 頂層 pump 整體驗證(`preferences_page_test.dart` 「無任何 prefs 值」)。✅
   - **只有 legacy key→預填生效**:重量單位(`legacy_weight_unit`)、1RM 公式(`legacy_one_rm_formula`)、休息秒數(`legacy_default_rest_time`)各一條;主題因有兩個 legacy 來源,`legacy_theme` 與 `legacy_is_dark_mode` 分開各一條(共 5 條)。**變異驗證**(逐項拔 legacy fallback,跑對應測試确認變紅,驗完立刻還原,見下方「變異驗證紀錄」)。✅
   - **既有新 key 優先於 legacy(兩組都種)**:四項各一條。✅
   - **頁面改值→prefs 寫入+provider 值即時反映**:四項各一條 provider-level(`setXxx()`)+ 四項各一條 widget-level(點選 UI 控制項)。**變異驗證**(逐項拔寫入,provider-level 與 widget-level 測試均變紅,驗完還原)。✅
   - **legacy 值域畸形→落安全預設不炸**:`legacy_weight_unit='stone'`→kg;`legacy_theme='sepia'`→system(含「即使 `legacy_is_dark_mode` 也在仍不退回」的額外一條,驗證 brief 第 2 項的判斷);`legacy_default_rest_time`=0 與 -30 兩條→90;`legacy_one_rm_formula='oconner'`→epley。✅
   - **契約回歸**:`weightUnitProvider` 無任何 prefs 值時回 kg,獨立命名測試案例「契約回歸」。✅
3. **期望值自己實跑確認**:全部用 `flutter test` 實際執行確認,非憑空推算;規格與實測無不符之處。✅

## 變異驗證紀錄(拔 fallback / 拔寫入,驗完已還原,`git diff` 乾淨)

| 項目 | 拔的內容 | 對應測試變紅 | 已還原 |
| --- | --- | --- | --- |
| 重量單位 | `_container()`build() 的 legacy fallback | `只有 legacy_weight_unit="lb"` | ✅ |
| 重量單位 | `setUnit()` 寫入+state | `setUnit()` provider 測試 + widget「點選重量單位」測試 | ✅ |
| 主題 | `_resolveLegacyThemeMode` 整段(兩個 legacy 來源) | `只有 legacy_theme`、`只有 legacy_is_dark_mode=true`、`=false` 三條同時變紅 | ✅ |
| 主題 | `setThemeMode()` 寫入+state | provider 測試 + widget「點選主題」測試 | ✅ |
| 預設休息秒數 | legacy fallback 分支 | `只有 legacy_default_rest_time=120` | ✅ |
| 預設休息秒數 | `setSeconds()` 寫入+state | provider 測試 + widget「選擇休息秒數」測試 | ✅ |
| 1RM 公式 | legacy fallback 分支 | `只有 legacy_one_rm_formula="brzycki"` | ✅ |
| 1RM 公式 | `setFormula()` 寫入+state | provider 測試 + widget「點選 1RM 公式」測試 | ✅ |

還原後重跑 `flutter analyze`(0 issues)+ `flutter test`(532/532 全綠)、`grep -rn "MUTATION-TEST-TEMP" lib/` 確認乾淨。

## 張力偏離

無。過程中兩個需要自行判斷、brief 沒有明文釘死的地方,決策與理由記在下面「設計決策」,不算規則與現實互斥的張力。

## 設計決策(非張力,供大腦 review 對照)

1. **主題 legacy 雙來源優先權**:`legacy_theme` 有值就用(值域對不上直接落 system,**不**退回 `legacy_is_dark_mode`);`legacy_theme` 完全沒有才看 `legacy_is_dark_mode`。理由:`legacy_theme` 是較新版本才有的欄位,若這欄位存在但壞了,不該拿更舊的訊號去猜——已用一條額外測試鎖住「legacy_theme 畸形時不退回 is_dark_mode」這個行為。
2. **`weightUnitProvider` 契約型別維持**:內部改成 `Provider<WeightUnit>((ref) => ref.watch(weightUnitControllerProvider))`,真正的持久化狀態在新增的 `WeightUnitController`(`NotifierProvider<WeightUnitController, WeightUnit>`)。C 工人只認 `weightUnitProvider` 名稱與型別,不需要知道背後多了一層。
3. **寫入失敗處理的測試 seam**:四個 controller 各自的 `setXxx()` 是 public method,失敗測試用「子類別覆寫單一方法拋例外」+ `xxxControllerProvider.overrideWith(() => _ThrowingXxxController())`,跟 `dashboard_page_test.dart` 的 `_ThrowingBodyWeightRepository extends BodyWeightRepository` 是同一套慣例,沒有引入新的 mock 套件(注意到 `mockito` 已是依賴,但這個慣例更貼近本專案既有寫法,沒有用它)。
4. **休息秒數 UI 選成 `DropdownButtonFormField<int>`**(30-300,15 秒一階,19 個選項),不是 SegmentedButton——19 個選項用 SegmentedButton 橫向會爆版。測試上第一輪踩到選單超出預設測試視窗高度、`tap` 打偏(修正前誤判成功,`provider` 實際沒變)的坑,已改用 `ensureVisible` 先捲到再點,已在測試檔內聯註解。
5. **換帳號快取生命週期**:核對 `.claude/decisions/2026-08-04-帳號隔離採換帳號清本機資料.md` 與 `legacy_prefs_importer.dart` 的 `kLegacyPrefsPersonalDataKeys` 清單——四項偏好的新 key 與 legacy key 都不在換帳號清除範圍內(裝置層級設定,非個資),所以四個 controller 刻意不 watch `sessionControllerProvider`,理由寫在各檔案的 class doc 裡。

## 順路發現

無(範圍內未挖到擋驗收的既有問題;`one_rm_calculator.dart` 目前只有 Epley 一種公式實作、無 formula 參數,不是「問題」,是既有事實,已在 `one_rm_formula_preference.dart` 檔頭註解說明——本波只交付偏好狀態,不含 Brzycki/Lander 計算本體,brief 範圍本就不含)。

## 三個新 provider 名稱與型別清單(供大腦接線)

除既有契約 `weightUnitProvider`(型別不變,`Provider<WeightUnit>`)外,本波新增:

| Provider | 型別 | 檔案 | 用途/接線點(本波未接) |
| --- | --- | --- | --- |
| `themeModeProvider` | `Provider<ThemeMode>` | `theme_preference.dart` | 大腦接 `app.dart` 的 `MaterialApp.themeMode` |
| `defaultRestSecondsProvider` | `Provider<int>` | `default_rest_seconds_preference.dart` | 大腦接 `workout_ui_shared.dart` 的 `kDefaultRestSeconds` 呼叫端 |
| `oneRmFormulaProvider` | `Provider<OneRmFormula>` | `one_rm_formula_preference.dart` | 大腦接 `one_rm_calculator.dart` 呼叫端(**注意**:該檔目前只有 Epley 實作,接線前可能需要先補 Brzycki/Lander 計算本體或決定範圍) |

各自背後的寫入端(設定頁用,大腦/其他工人如需要也可以直接用):
`weightUnitControllerProvider`(`NotifierProvider<WeightUnitController, WeightUnit>`)、
`themeModeControllerProvider`(`NotifierProvider<ThemeModeController, ThemeMode>`)、
`defaultRestSecondsControllerProvider`(`NotifierProvider<DefaultRestSecondsController, int>`)、
`oneRmFormulaControllerProvider`(`NotifierProvider<OneRmFormulaController, OneRmFormula>`)。

Prefs key 對照表:

| 偏好 | 新 key | legacy key(來源) |
| --- | --- | --- |
| 重量單位 | `weight_unit` | `legacy_weight_unit` |
| 主題 | `theme_mode` | `legacy_theme` + `legacy_is_dark_mode`(雙來源,優先權見上) |
| 預設休息秒數 | `default_rest_seconds` | `legacy_default_rest_time` |
| 1RM 公式 | `one_rm_formula` | `legacy_one_rm_formula` |
