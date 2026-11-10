// 波 6 跨工人契約檔(大腦定,commit 在 feature/wave6 基底):偏好設定頁的
// 進入點。settings-core 工人(A)在設定頁骨架掛
// `Navigator.push(MaterialPageRoute(builder: (_) => const PreferencesPage()))`
// 入口;preferences 工人(B)把本 stub 換成真身(主題/預設休息秒數/1RM 公式/
// 重量單位四項,含 legacy 預填)。**類名與 zero-arg const 建構子是契約,
// 不得改。**
//
// UI 改版(第 3 波):「重量單位」「主題」已搬到設定主列表(settings_page.dart 的
// 行內 SegmentedButton,同一組 controller、同一套寫入失敗處理);本頁保留休息秒數、
// 1RM 公式與「重置所有設定」(重置仍涵蓋四項,含已搬走的單位與主題)。
// 以下為原註解,「四項」指休息秒數/1RM 公式與搬走前的單位/主題:
//
// 四項全部「選了就立刻寫入生效」(不像 goal_settings_page.dart 那種表單+
// 「儲存」按鈕——這裡是設定語意的即時切換,對齊 iOS 版
// `Views/Settings/GlobalSettingsView.swift` 選了就 `updateSetting` 立即存檔
// 的行為)。每項各自的 `_savingXxx` 只是「這個控制項正在等 prefs 寫入」的
// 短暫 disable,不是整頁 loading——四項互相獨立,不需要共用一個 loading旗標。
//
// 寫入失敗處理:各 controller 的 setXxx() 是「先寫 prefs 成功才更新
// state」,所以失敗時 provider 值維持原值,畫面(直接 watch provider)自然
// 顯示回舊選項,不需要額外復原邏輯——這裡只需要解除該控制項的 loading +
// 跳浮錯,呼叫端(本檔)不需要自己 revert 任何本地狀態。**前提是四個控制項
// 都是「完全受控」(display 值每次 build 都從 provider 值重新算,不留自己的
// 內部狀態)**——SegmentedButton 天生如此;休息秒數改用 `DropdownButton`
// (而非 `DropdownButtonFormField`)正是為了滿足這個前提:FormField 版本的
// `didChange` 會先把 FormField 內部 state 設成使用者剛選的值再回呼
// `onChanged`,`didUpdateWidget` 只在 `initialValue` 變動時才 setValue——寫入
// 失敗時 provider 沒變、`initialValue` 沒變,內部 state 就會停在使用者選過
// 但沒寫入成功的值,畫面顯示與實際偏好不符。`DropdownButton` 每次 rebuild
// 都直接用 `value:` 這個 prop 重算顯示,沒有這層獨立內部狀態,失敗後自然
// 跟著 provider 顯示回舊值。
//
// 外觀(2026-11 視覺驗收修正):底線式 DropdownButton 外包 `InputDecorator`,吃全域
// `inputDecorationTheme` 的 filled 樣式,與其他輸入框一致;仍是受控的
// `DropdownButton`(未改用 FormField),上述受控保證不變。整頁以
// SectionHeader + AppCard 分組。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../workout/workout_ui_shared.dart' show kDefaultRestSeconds;
import 'default_rest_seconds_preference.dart';
import 'formula_explanation_page.dart';
import 'one_rm_formula_preference.dart';
import 'theme_preference.dart';
import 'weight_unit.dart';

/// 預設休息秒數選擇器的值域(30-300 秒,15 秒一階)——brief 給的參考範圍。
/// 產生式建構,區間/階距單一來源,改值域只需要改這一行。
final List<int> _kRestSecondsOptions = [for (var s = 30; s <= 300; s += 15) s];

class PreferencesPage extends ConsumerStatefulWidget {
  const PreferencesPage({super.key});

  @override
  ConsumerState<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends ConsumerState<PreferencesPage> {
  bool _savingRestSeconds = false;
  bool _savingFormula = false;
  bool _resetting = false;

  static const _kWriteErrorMessage = '儲存失敗，請稍後再試';

  /// 統一包住「setSaving(true) → 寫入 → 失敗跳浮錯 → finally setSaving(false)」
  /// ——四個偏好共用同一套錯誤處理,只有 write callback 跟 saving flag 不同。
  Future<void> _guardedWrite({
    required Future<void> Function() write,
    required void Function(bool saving) setSaving,
  }) async {
    setSaving(true);
    try {
      await write();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_kWriteErrorMessage)),
      );
    } finally {
      if (mounted) setSaving(false);
    }
  }

  /// 對齊 iOS `GlobalSettingsManager.resetToDefaults()` 中 Flutter 實際有的
  /// 四項本機偏好(單位 kg、主題跟隨系統、休息 90 秒、公式 Epley)。iOS 另有的
  /// showVolumeInStats / enableHapticFeedback / autoSaveWorkout 在 Flutter
  /// 沒有對應偏好,不處理。只動本機偏好,不碰訓練資料/帳號。
  /// 逐項走各 controller 的 setXxx()(寫 prefs 成功才更新 state),任一項失敗
  /// 就中止並跳浮錯,已重設的項目維持新值。
  Future<void> _confirmAndReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置設定'),
        content: const Text('確定要將所有設定恢復為預設值嗎？'),
        actions: [
          TextButton(
            key: const Key('resetPreferencesCancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('resetPreferencesConfirm'),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _guardedWrite(
      write: () async {
        await ref.read(weightUnitControllerProvider.notifier).setUnit(WeightUnit.kg);
        await ref.read(themeModeControllerProvider.notifier).setThemeMode(ThemeMode.system);
        await ref.read(defaultRestSecondsControllerProvider.notifier).setSeconds(kDefaultRestSeconds);
        await ref.read(oneRmFormulaControllerProvider.notifier).setFormula(OneRmFormula.epley);
      },
      setSaving: (saving) => setState(() => _resetting = saving),
    );
  }

  @override
  Widget build(BuildContext context) {
    final restSeconds = ref.watch(defaultRestSecondsProvider);
    final formula = ref.watch(oneRmFormulaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('偏好設定')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          SectionHeader(title: '預設休息秒數', trailing: _savingIndicator(_savingRestSeconds)),
          AppCard(
            child: InputDecorator(
              // 吃全域 inputDecorationTheme(filled);isEmpty:false 避免 hint 與
              // 下拉內容的 label 浮動邏輯互相干擾(本欄沒有 label)。
              decoration: const InputDecoration(),
              isEmpty: false,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: const Key('defaultRestSecondsDropdown'),
                  isExpanded: true,
                  isDense: true,
                  // 完全受控:value 每次 build 都從 provider 值重算,不留內部狀態
                  // ——寫入失敗時 provider 不變,畫面自然跟著顯示回舊值(見檔頭
                  // 說明)。用 DropdownButton 而非 DropdownButtonFormField 正是
                  // 為了這個受控保證。
                  value: _kRestSecondsOptions.contains(restSeconds) ? restSeconds : null,
                  hint: Text('$restSeconds 秒'),
                  items: [
                    for (final seconds in _kRestSecondsOptions)
                      DropdownMenuItem(value: seconds, child: Text('$seconds 秒')),
                  ],
                  onChanged: _savingRestSeconds
                      ? null
                      : (seconds) {
                          if (seconds == null) return;
                          _guardedWrite(
                            write: () => ref
                                .read(defaultRestSecondsControllerProvider.notifier)
                                .setSeconds(seconds),
                            setSaving: (saving) => setState(() => _savingRestSeconds = saving),
                          );
                        },
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: '1RM 估算公式', trailing: _savingIndicator(_savingFormula)),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<OneRmFormula>(
                    key: const Key('oneRmFormulaSegmentedButton'),
                    segments: [
                      for (final f in OneRmFormula.values)
                        ButtonSegment(value: f, label: Text(f.displayName)),
                    ],
                    selected: {formula},
                    onSelectionChanged: _savingFormula
                        ? null
                        : (selection) => _guardedWrite(
                              write: () => ref
                                  .read(oneRmFormulaControllerProvider.notifier)
                                  .setFormula(selection.first),
                              setSaving: (saving) => setState(() => _savingFormula = saving),
                            ),
                  ),
                ),
                TextButton(
                  key: const Key('formulaExplanationButton'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const FormulaExplanationPage()),
                  ),
                  child: const Text('查看公式說明'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const Key('resetPreferencesButton'),
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                onPressed: _resetting ? null : _confirmAndReset,
                child: const Text('重置所有設定'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 標題列右側的「寫入中」小轉圈;未寫入時回 null(SectionHeader 不顯示 trailing)。
  Widget? _savingIndicator(bool saving) => saving
      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
      : null;
}
