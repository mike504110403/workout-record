// 新增三項紀錄的 bottom sheet。對應 iOS `AddPowerLiftRecordSheet.swift`。
//
// 寫入與畫面刷新在彈窗還開著時就 await 完成、成功才 pop——理由與
// `features/dashboard/widgets/add_body_weight_sheet.dart` 相同(避免
// pumpAndSettle 跟 sheet 關閉轉場動畫的 Future resolve 時機打架)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/preferences/weight_unit.dart';
import '../../../workout/one_rm_calculator.dart';
import '../powerlifting_controller.dart';

class AddPowerLiftRecordSheet extends ConsumerStatefulWidget {
  const AddPowerLiftRecordSheet({super.key});

  @override
  ConsumerState<AddPowerLiftRecordSheet> createState() => _AddPowerLiftRecordSheetState();
}

class _AddPowerLiftRecordSheetState extends ConsumerState<AddPowerLiftRecordSheet> {
  final _weightController = TextEditingController();
  final _repsController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isSaving = false;

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 輸入框裡的原始值——當前顯示單位(kg 或 lb),不是儲存單位。
  double? get _parsedWeight {
    final value = double.tryParse(_weightController.text);
    if (value == null || value <= 0) return null;
    return value;
  }

  int? get _parsedReps {
    final value = int.tryParse(_repsController.text);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// 預覽用 1RM——直接用當前顯示單位的輸入值算(公式對 weight 是線性齊次,
  /// 用顯示單位算出來的結果換算回 kg 再換算回顯示單位是同一個數字,不需要
  /// 先轉 kg 再轉回來)。
  double? get _previewOneRepMax {
    final weight = _parsedWeight;
    final reps = _parsedReps;
    if (weight == null || reps == null) return null;
    return calculateOneRepMax(weight: weight, reps: reps);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final weight = _parsedWeight;
    final reps = _parsedReps;
    if (weight == null || reps == null || _isSaving) return;

    // 使用者輸入視為當前顯示單位的值,反向換算成 kg 才是入庫值(儲存一律
    // kg——見 weight_unit.dart 契約)。
    final unit = ref.read(weightUnitProvider);
    final weightKg = displayToKg(weight, unit);

    setState(() => _isSaving = true);
    try {
      final note = _noteController.text.trim();
      await ref.read(powerliftingControllerProvider.notifier).addManualRecord(
            weight: weightKg,
            reps: reps,
            achievedAt: _date,
            note: note.isEmpty ? null : note,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('儲存失敗，請稍後再試')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(weightUnitProvider);
    final canSave = _parsedWeight != null && _parsedReps != null && !_isSaving;
    final preview = _previewOneRepMax;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('新增紀錄', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            key: const Key('powerLiftWeightField'),
            controller: _weightController,
            autofocus: true,
            enabled: !_isSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: '重量 (${unitSuffix(unit)})'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('powerLiftRepsField'),
            controller: _repsController,
            enabled: !_isSaving,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '次數'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          ListTile(
            key: const Key('powerLiftDatePickerTile'),
            contentPadding: EdgeInsets.zero,
            title: const Text('日期'),
            trailing: Text('${_date.year}/${_date.month}/${_date.day}'),
            onTap: _isSaving ? null : _pickDate,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('powerLiftNoteField'),
            controller: _noteController,
            enabled: !_isSaving,
            decoration: const InputDecoration(labelText: '備註（選填）'),
            maxLines: 2,
          ),
          if (preview != null) ...[
            const SizedBox(height: 12),
            Text(
              '推估 1RM：${preview.toStringAsFixed(1)} ${unitSuffix(unit)}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('savePowerLiftRecordButton'),
              onPressed: canSave ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('儲存'),
            ),
          ),
        ],
      ),
    );
  }
}
