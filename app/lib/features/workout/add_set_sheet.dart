// 記組 sheet:重量/次數必填、RPE 選填、暖身組開關、休息秒數(對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Workout/AddSetSheet.swift`)。
// 也用來編輯既有組數(帶入 initial* 參數時,行為對照 iOS `EditSetSheet`——
// iOS 那邊是獨立檔案,這裡刻意收斂成同一個表單少一份重複,呼叫端
// (workout_in_progress_view.dart)決定要不要帶 initial* 值)。
import 'package:flutter/material.dart';

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
  final bool autoStartRestTimer;
}

/// 開啟記組 sheet。使用者取消回傳 `null`。
///
/// [previousWeight]/[previousReps] 是「上一組」的資料,只在新增組數
/// (未提供 initialWeight/initialReps)時用來預填(對照 iOS
/// `let lastSet = exercise.sets.last`)。編輯既有組數時改用 initialWeight/
/// initialReps/initialRpe/initialIsWarmup/initialRestSeconds 帶入該組本身
/// 的資料。
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
}) {
  return showModalBottomSheet<AddSetResult>(
    context: context,
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
    ),
  );
}

class _AddSetForm extends StatefulWidget {
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

  @override
  State<_AddSetForm> createState() => _AddSetFormState();
}

class _AddSetFormState extends State<_AddSetForm> {
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
    final weight = widget.initialWeight ?? widget.previousWeight;
    final reps = widget.initialReps ?? widget.previousReps;
    _weightController = TextEditingController(text: weight != null ? trimZeros(weight) : '');
    _repsController = TextEditingController(text: reps != null ? '$reps' : '');
    _rpeController =
        TextEditingController(text: widget.initialRpe != null ? trimZeros(widget.initialRpe!) : '');
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
      double.tryParse(_weightController.text) != null && int.tryParse(_repsController.text) != null;

  void _save() {
    final weight = double.tryParse(_weightController.text);
    final reps = int.tryParse(_repsController.text);
    if (weight == null || reps == null) return;
    final rpeText = _rpeController.text.trim();
    final rpe = rpeText.isEmpty ? null : double.tryParse(rpeText);
    Navigator.of(context).pop(AddSetResult(
      weight: weight,
      reps: reps,
      rpe: rpe,
      isWarmup: _isWarmup,
      restSeconds: _restSeconds,
      autoStartRestTimer: _autoStartRestTimer,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.exerciseName, style: Theme.of(context).textTheme.titleMedium),
          Text('第 ${widget.setNumber} 組', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            key: const Key('addSetWeightField'),
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '重量 (kg)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('addSetRepsField'),
            controller: _repsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '次數'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (_calculatedVolume > 0)
            Text('容量:${_calculatedVolume.toStringAsFixed(0)}', key: const Key('addSetVolumePreview')),
          const SizedBox(height: 8),
          TextField(
            key: const Key('addSetRpeField'),
            controller: _rpeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            Row(
              children: [
                const Text('休息時間'),
                const Spacer(),
                IconButton(
                  key: const Key('addSetRestMinusButton'),
                  icon: const Icon(Icons.remove),
                  onPressed: _restSeconds <= 0
                      ? null
                      : () => setState(() => _restSeconds = (_restSeconds - 15).clamp(0, 300)),
                ),
                Text('$_restSeconds 秒', key: const Key('addSetRestSecondsValue')),
                IconButton(
                  key: const Key('addSetRestPlusButton'),
                  icon: const Icon(Icons.add),
                  onPressed: _restSeconds >= 300
                      ? null
                      : () => setState(() => _restSeconds = (_restSeconds + 15).clamp(0, 300)),
                ),
              ],
            ),
          if (!_isWarmup)
            SwitchListTile(
              key: const Key('addSetAutoStartRestTimerSwitch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('自動開始休息計時'),
              value: _autoStartRestTimer,
              onChanged: (value) => setState(() => _autoStartRestTimer = value),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const Key('addSetCancelButton'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
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
    );
  }
}
