// 波 6 跨工人契約檔(大腦定,commit 在 feature/wave6 基底):偏好設定頁的
// 進入點。settings-core 工人(A)在設定頁骨架掛
// `Navigator.push(MaterialPageRoute(builder: (_) => const PreferencesPage()))`
// 入口;preferences 工人(B)把本 stub 換成真身(主題/預設休息秒數/1RM 公式/
// 重量單位四項,含 legacy 預填)。**類名與 zero-arg const 建構子是契約,
// 不得改。**
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
// 跳浮錯,呼叫端(本檔)不需要自己 revert 任何本地狀態。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'default_rest_seconds_preference.dart';
import 'one_rm_formula_preference.dart';
import 'theme_preference.dart';
import 'weight_unit.dart';

/// 預設休息秒數選擇器的值域(30-300 秒,15 秒一階)——brief 給的參考範圍。
const _kRestSecondsOptions = [
  30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180, 195, 210, 225, 240, 255, 270, 285, 300,
];

class PreferencesPage extends ConsumerStatefulWidget {
  const PreferencesPage({super.key});

  @override
  ConsumerState<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends ConsumerState<PreferencesPage> {
  bool _savingWeightUnit = false;
  bool _savingTheme = false;
  bool _savingRestSeconds = false;
  bool _savingFormula = false;

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

  @override
  Widget build(BuildContext context) {
    final weightUnit = ref.watch(weightUnitProvider);
    final themeMode = ref.watch(themeModeProvider);
    final restSeconds = ref.watch(defaultRestSecondsProvider);
    final formula = ref.watch(oneRmFormulaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('偏好設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle(context, '重量單位', _savingWeightUnit),
          const SizedBox(height: 8),
          SegmentedButton<WeightUnit>(
            key: const Key('weightUnitSegmentedButton'),
            segments: const [
              ButtonSegment(value: WeightUnit.kg, label: Text('公斤 (kg)')),
              ButtonSegment(value: WeightUnit.lb, label: Text('磅 (lb)')),
            ],
            selected: {weightUnit},
            onSelectionChanged: _savingWeightUnit
                ? null
                : (selection) => _guardedWrite(
                      write: () => ref
                          .read(weightUnitControllerProvider.notifier)
                          .setUnit(selection.first),
                      setSaving: (saving) => setState(() => _savingWeightUnit = saving),
                    ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, '主題', _savingTheme),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            key: const Key('themeModeSegmentedButton'),
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('跟隨系統')),
              ButtonSegment(value: ThemeMode.light, label: Text('淺色')),
              ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
            ],
            selected: {themeMode},
            onSelectionChanged: _savingTheme
                ? null
                : (selection) => _guardedWrite(
                      write: () => ref
                          .read(themeModeControllerProvider.notifier)
                          .setThemeMode(selection.first),
                      setSaving: (saving) => setState(() => _savingTheme = saving),
                    ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, '預設休息秒數', _savingRestSeconds),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: const Key('defaultRestSecondsDropdown'),
            initialValue: _kRestSecondsOptions.contains(restSeconds) ? restSeconds : null,
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
          const SizedBox(height: 24),
          _buildSectionTitle(context, '1RM 估算公式', _savingFormula),
          const SizedBox(height: 8),
          SegmentedButton<OneRmFormula>(
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
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, bool saving) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (saving) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }
}
