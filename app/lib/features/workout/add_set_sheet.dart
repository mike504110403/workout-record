// 記組 sheet:主區只有重量/次數(大字輸入 + 兩側 −/+ stepper),RPE 選填、
// 暖身組開關、休息秒數、自動計時收進預設收合的「進階選項」(對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/AddSetSheet.swift`)。
// 也用來編輯既有組數(帶入 initial* 參數時,行為對照 iOS `EditSetSheet`——
// iOS 那邊是獨立檔案,這裡刻意收斂成同一個表單少一份重複,呼叫端
// (workout_in_progress_view.dart)決定要不要帶 initial* 值)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/weight_format.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_tokens.dart';
import '../settings/preferences/weight_unit.dart';
import 'workout_ui_shared.dart';

class AddSetResult {
  const AddSetResult({
    required this.weight,
    required this.reps,
    this.rpe,
    required this.isWarmup,
    required this.restSeconds,
    required this.autoStartRestTimer,
  });

  /// 一律 kg(儲存值)——sheet 內部負責把使用者輸入的當前顯示單位值換算成
  /// kg 才 pop 出去,呼叫端不需要知道使用者用的是 kg 還是 lb。
  final double weight;
  final int reps;
  final double? rpe;
  final bool isWarmup;
  final int restSeconds;

  /// 對照 iOS `AddSetSheet.swift:18,126`「自動開始休息計時」開關(預設
  /// 開)。**與 iOS 刻意的行為差異**:iOS 那顆開關的 `@State` 值從未被讀取
  /// 或傳進 `onSave`(`onSave: (Double, Int, Double?, Int) -> Void` 簽名裡
  /// 沒有它的位置)——是 iOS 端一顆點了沒有任何效果的死開關。我們補這顆
  /// UI 時直接接上真行為(關閉時存組後不自動啟動休息計時器),不複製
  /// iOS 這個「看起來能點但沒用」的缺陷。暖身組永遠不啟動計時器,這顆開關
  /// 只在非暖身組時顯示、生效。
  ///
  /// **只有新增組路徑會消費這個值**(`workout_in_progress_view.dart`
  /// `_openAddSetSheet`:`if (!result.isWarmup && result.autoStartRestTimer)`
  /// 才啟動計時器)。編輯既有組路徑(`_editSet`)呼叫 [showAddSetSheet] 時
  /// 傳 `showAutoStartRestTimer: false`,表單根本不渲染這顆開關——編輯一組
  /// 已經記錄過的資料不該觸發新的休息倒數,不能讓使用者在編輯 sheet 看到
  /// 一顆點了沒用的開關(code review r2 major:重蹈 iOS 那個死開關的覆轍)。
  final bool autoStartRestTimer;
}

/// 重量 stepper 的單次步進(依顯示單位):kg 2.5、lb 5。
double addSetWeightStep(WeightUnit unit) => unit == WeightUnit.lb ? 5 : 2.5;

/// 次數 stepper 的單次步進。
const int kAddSetRepsStep = 1;

/// 開啟記組 sheet。使用者取消回傳 `null`。
///
/// [previousWeight]/[previousReps] 是「上一組」的資料,只在新增組數
/// (未提供 initialWeight/initialReps)時用來預填(對照 iOS
/// `let lastSet = exercise.sets.last`)。編輯既有組數時改用 initialWeight/
/// initialReps/initialRpe/initialIsWarmup/initialRestSeconds 帶入該組本身
/// 的資料。
///
/// [showAutoStartRestTimer] 控制要不要渲染「自動開始休息計時」開關(見
/// [AddSetResult.autoStartRestTimer] 文件)——新增組路徑(預設 `true`)才有
/// 意義,編輯既有組路徑(`workout_in_progress_view.dart` `_editSet`)傳
/// `false` 整顆隱藏,不留一個點了沒用的開關。
Future<AddSetResult?> showAddSetSheet(
  BuildContext context, {
  required String exerciseName,
  required int setNumber,
  double? previousWeight,
  int? previousReps,
  double? initialWeight,
  int? initialReps,
  double? initialRpe,
  bool initialIsWarmup = false,
  int initialRestSeconds = kDefaultRestSeconds,
  bool showAutoStartRestTimer = true,
}) {
  return showModalBottomSheet<AddSetResult>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddSetForm(
      exerciseName: exerciseName,
      setNumber: setNumber,
      previousWeight: previousWeight,
      previousReps: previousReps,
      initialWeight: initialWeight,
      initialReps: initialReps,
      initialRpe: initialRpe,
      initialIsWarmup: initialIsWarmup,
      initialRestSeconds: initialRestSeconds,
      showAutoStartRestTimer: showAutoStartRestTimer,
    ),
  );
}

class _AddSetForm extends ConsumerStatefulWidget {
  const _AddSetForm({
    required this.exerciseName,
    required this.setNumber,
    this.previousWeight,
    this.previousReps,
    this.initialWeight,
    this.initialReps,
    this.initialRpe,
    this.initialIsWarmup = false,
    this.initialRestSeconds = kDefaultRestSeconds,
    this.showAutoStartRestTimer = true,
  });

  final String exerciseName;
  final int setNumber;
  final double? previousWeight;
  final int? previousReps;
  final double? initialWeight;
  final int? initialReps;
  final double? initialRpe;
  final bool initialIsWarmup;
  final int initialRestSeconds;
  final bool showAutoStartRestTimer;

  @override
  ConsumerState<_AddSetForm> createState() => _AddSetFormState();
}

class _AddSetFormState extends ConsumerState<_AddSetForm> {
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;
  late final TextEditingController _rpeController;
  late bool _isWarmup;
  late int _restSeconds;

  /// 對照 iOS「自動開始休息計時」開關,預設開(見 [AddSetResult.autoStartRestTimer]
  /// 文件的刻意差異說明)。不隨 initial* 參數帶入——編輯既有組數時這顆開關
  /// 沒有對應的持久化欄位可回填,每次開啟表單都從預設值開始。
  bool _autoStartRestTimer = true;

  @override
  void initState() {
    super.initState();
    // initialWeight/previousWeight 是 kg(儲存值)——預填輸入框前先換算成
    // 當前顯示單位(kgToDisplay),編輯既有組數時才不會顯示錯的數字。
    final unit = ref.read(weightUnitProvider);
    final weight = widget.initialWeight ?? widget.previousWeight;
    _weightController = TextEditingController(
      text: weight != null ? trimZeros(kgToDisplay(weight, unit)) : '',
    );
    final reps = widget.initialReps ?? widget.previousReps;
    _repsController = TextEditingController(text: reps != null ? '$reps' : '');
    _rpeController = TextEditingController(
      text: widget.initialRpe != null ? trimZeros(widget.initialRpe!) : '',
    );
    _isWarmup = widget.initialIsWarmup;
    _restSeconds = widget.initialRestSeconds;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _rpeController.dispose();
    super.dispose();
  }

  double get _calculatedVolume {
    final w = double.tryParse(_weightController.text);
    final r = int.tryParse(_repsController.text);
    if (w == null || r == null) return 0;
    return w * r;
  }

  bool get _canSave =>
      double.tryParse(_weightController.text) != null &&
      int.tryParse(_repsController.text) != null;

  /// 重量 −/+:輸入框為空或不是數字時視為 0;下限 0;結果四捨五入到
  /// 小數 2 位避免浮點尾數(例如 102.60000000000001)。
  void _stepWeight(int direction, WeightUnit unit) {
    final current = double.tryParse(_weightController.text) ?? 0;
    final next = current + direction * addSetWeightStep(unit);
    final rounded = (next * 100).round() / 100;
    setState(
      () => _weightController.text = trimZeros(rounded < 0 ? 0 : rounded),
    );
  }

  /// 次數 −/+:輸入框為空或不是整數時視為 0;下限 0。
  void _stepReps(int direction) {
    final current = int.tryParse(_repsController.text) ?? 0;
    final next = current + direction * kAddSetRepsStep;
    setState(() => _repsController.text = '${next < 0 ? 0 : next}');
  }

  void _save() {
    final enteredWeight = double.tryParse(_weightController.text);
    final reps = int.tryParse(_repsController.text);
    if (enteredWeight == null || reps == null) return;
    final rpeText = _rpeController.text.trim();
    final rpe = rpeText.isEmpty ? null : double.tryParse(rpeText);
    // 使用者輸入視為當前顯示單位的值,反向換算成 kg 才是 AddSetResult 的
    // 契約值(儲存一律 kg)。
    final unit = ref.read(weightUnitProvider);
    final weightKg = displayToKg(enteredWeight, unit);
    Navigator.of(context).pop(
      AddSetResult(
        weight: weightKg,
        reps: reps,
        rpe: rpe,
        isWarmup: _isWarmup,
        restSeconds: _restSeconds,
        autoStartRestTimer: _autoStartRestTimer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(weightUnitProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // 編輯既有組且該組帶有進階欄位的值(RPE/暖身)時預設展開,否則使用者
    // 看不到這些已設定的值;新增組一律收合。
    final startExpanded = widget.initialRpe != null || widget.initialIsWarmup;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.exerciseName, style: theme.textTheme.titleMedium),
            Text(
              '第 ${widget.setNumber} 組',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _NumberStepper(
              label: '重量 (${unitSuffix(unit)})',
              controller: _weightController,
              fieldKey: const Key('addSetWeightField'),
              minusKey: const Key('addSetWeightMinusButton'),
              plusKey: const Key('addSetWeightPlusButton'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: () => setState(() {}),
              onMinus: () => _stepWeight(-1, unit),
              onPlus: () => _stepWeight(1, unit),
            ),
            const SizedBox(height: AppSpacing.lg),
            _NumberStepper(
              label: '次數',
              controller: _repsController,
              fieldKey: const Key('addSetRepsField'),
              minusKey: const Key('addSetRepsMinusButton'),
              plusKey: const Key('addSetRepsPlusButton'),
              keyboardType: TextInputType.number,
              onChanged: () => setState(() {}),
              onMinus: () => _stepReps(-1),
              onPlus: () => _stepReps(1),
            ),
            if (_calculatedVolume > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                // _calculatedVolume 是「當前顯示單位」的值;formatWeight 吃 kg,
                // 先換回 kg 再依單位格式化(保留 1 位小數,例如 562.5 kg)。
                '容量 ${formatWeight(displayToKg(_calculatedVolume, unit), unit)}',
                key: const Key('addSetVolumePreview'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            ExpansionTile(
              key: const Key('addSetAdvancedTile'),
              initiallyExpanded: startExpanded,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text('進階選項', style: theme.textTheme.titleSmall),
              children: [
                TextField(
                  key: const Key('addSetRpeField'),
                  controller: _rpeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'RPE(選填)'),
                ),
                SwitchListTile(
                  key: const Key('addSetWarmupSwitch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('暖身組'),
                  value: _isWarmup,
                  onChanged: (value) => setState(() => _isWarmup = value),
                ),
                if (!_isWarmup)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('休息時間'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          key: const Key('addSetRestMinusButton'),
                          tooltip: '減少休息時間',
                          icon: const Icon(Icons.remove),
                          onPressed: _restSeconds <= 0
                              ? null
                              : () => setState(
                                  () => _restSeconds = (_restSeconds - 15)
                                      .clamp(0, 300),
                                ),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(
                            '$_restSeconds 秒',
                            key: const Key('addSetRestSecondsValue'),
                            textAlign: TextAlign.center,
                            style: AppNumberStyles.body(context),
                          ),
                        ),
                        IconButton.filledTonal(
                          key: const Key('addSetRestPlusButton'),
                          tooltip: '增加休息時間',
                          icon: const Icon(Icons.add),
                          onPressed: _restSeconds >= 300
                              ? null
                              : () => setState(
                                  () => _restSeconds = (_restSeconds + 15)
                                      .clamp(0, 300),
                                ),
                        ),
                      ],
                    ),
                  ),
                if (!_isWarmup && widget.showAutoStartRestTimer)
                  SwitchListTile(
                    key: const Key('addSetAutoStartRestTimerSwitch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自動開始休息計時'),
                    value: _autoStartRestTimer,
                    onChanged: (value) =>
                        setState(() => _autoStartRestTimer = value),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const Key('addSetCancelButton'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const Key('addSetSaveButton'),
                    onPressed: _canSave ? _save : null,
                    child: const Text('儲存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 大字輸入 + 兩側 −/+ 的數值 stepper(重量、次數共用)。
class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.controller,
    required this.fieldKey,
    required this.minusKey,
    required this.plusKey,
    required this.keyboardType,
    required this.onChanged,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final Key minusKey;
  final Key plusKey;
  final TextInputType keyboardType;
  final VoidCallback onChanged;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const buttonStyleSize = Size(56, 56);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            IconButton.filledTonal(
              key: minusKey,
              tooltip: '減少$label',
              style: IconButton.styleFrom(minimumSize: buttonStyleSize),
              icon: const Icon(Icons.remove),
              onPressed: onMinus,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: controller,
                keyboardType: keyboardType,
                textAlign: TextAlign.center,
                style: AppNumberStyles.display(context),
                decoration: const InputDecoration(hintText: '0'),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            IconButton.filledTonal(
              key: plusKey,
              tooltip: '增加$label',
              style: IconButton.styleFrom(minimumSize: buttonStyleSize),
              icon: const Icon(Icons.add),
              onPressed: onPlus,
            ),
          ],
        ),
      ],
    );
  }
}
