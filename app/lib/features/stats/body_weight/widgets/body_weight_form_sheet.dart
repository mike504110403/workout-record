// 新增/編輯體重的 bottom sheet。
//
// **與 dashboard 側 `AddBodyWeightSheet` 的關係（brief 明定的差異申報）**：
// `features/dashboard/widgets/add_body_weight_sheet.dart` 只收「體重」一個
// 欄位（`recordBodyWeight(double weight)`，measuredAt 內部固定寫死
// `DateTime.now()`），沒有日期時間選擇、沒有備註欄位、也不支援帶入既有值
// 做編輯。Stats 版體重紀錄需要完整對齊 iOS
// `AddBodyWeightSheet.swift`（日期時間選擇 + 備註 + 可編輯既有紀錄），能力
// 不足以重用——依 brief 指示不改 dashboard 那份（它服務 Dashboard 快速記錄
// 的最小場景，改了會影響工人 A/其他既有測試的範圍），改在本目錄自建這份
// 同時服務新增與編輯兩種模式（[original] 為 null 代表新增）。
//
// 寫入路徑的 try/catch/finally 與「pop 放在寫入成功之後」的設計，沿用
// dashboard 版 `add_body_weight_sheet.dart` 已驗證過的慣例（見該檔案開頭
// 註解）：避免 `_isSaving` 卡死、避免 widget test 的 pumpAndSettle 跟
// bottom sheet 關閉動畫的 Future resolve 時機打架。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/body_weight.dart';
import '../body_weight_controller.dart';
import '../body_weight_format.dart';

class BodyWeightFormSheet extends ConsumerStatefulWidget {
  const BodyWeightFormSheet({super.key, this.original});

  /// null = 新增模式；非 null = 編輯模式，表單以這筆紀錄的既有值為初始值。
  final BodyWeight? original;

  @override
  ConsumerState<BodyWeightFormSheet> createState() => _BodyWeightFormSheetState();
}

class _BodyWeightFormSheetState extends ConsumerState<BodyWeightFormSheet> {
  late final TextEditingController _weightController;
  late final TextEditingController _noteController;
  late DateTime _selectedDate;
  bool _isSaving = false;

  bool get _isEditing => widget.original != null;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    _weightController = TextEditingController(
      text: original != null ? _stripTrailingZero(original.weight) : '',
    );
    _noteController = TextEditingController(text: original?.note ?? '');
    _selectedDate = original?.measuredAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _weightController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 體重輸入框的初始文字——`70.0` 這種整數體重顯示成 `70`，比較貼近使用者
  /// 實際輸入的樣子（避免編輯既有紀錄時看到多餘的 `.0`）。
  String _stripTrailingZero(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  double? get _parsedWeight {
    final value = double.tryParse(_weightController.text);
    if (value == null || value <= 0) return null;
    return value;
  }

  // `initialEntryMode: .input` 而不是預設的 calendar/dial——理由是可測試性:
  // 預設的日曆格子／時鐘轉盤要靠座標手勢或不穩定的「找數字文字」去點選,
  // widget test 很容易因為月份格線佈局、12/24 小時制轉盤角度算法而 flaky。
  // 換成文字輸入模式後,widget test 可以直接用 `tester.enterText` 打一組
  // 確定的日期/時間字串,決定性、不依賴畫面座標。這是純粹的可測試性考量,
  // 使用者體感上兩種模式都是 Flutter 內建元件、都有「切換回日曆/轉盤」的
  // 圖示可以點,不影響功能對等。
  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (!mounted) return;

    setState(() {
      _selectedDate = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _selectedDate.hour,
        time?.minute ?? _selectedDate.minute,
      );
    });
  }

  // 寫入路徑包 try/catch/finally——理由同 dashboard 版
  // `add_body_weight_sheet.dart` 開頭註解：controller 拋錯時（DB 寫入失敗、
  // userId 解析不到）若沒有這層保護，`_isSaving` 會永遠卡在 true，欄位與
  // 按鈕全部 disable、也沒有任何錯誤提示。失敗時秀 SnackBar；finally 裡
  // 確認 widget 還 mounted 才 setState（避免 pop 之後畫面已卸載還呼叫
  // setState 噴 exception）。
  Future<void> _save() async {
    final weight = _parsedWeight;
    if (weight == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final noteText = _noteController.text.trim();
      final note = noteText.isEmpty ? null : noteText;
      final controller = ref.read(bodyWeightTabControllerProvider.notifier);
      final original = widget.original;
      if (original == null) {
        await controller.addEntry(weight: weight, measuredAt: _selectedDate, note: note);
      } else {
        await controller.updateEntry(
          original: original,
          weight: weight,
          measuredAt: _selectedDate,
          note: note,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditing ? '更新失敗，請稍後再試' : '儲存失敗，請稍後再試')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isEditing ? '編輯體重紀錄' : '記錄體重', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            key: const Key('bodyWeightFormWeightField'),
            controller: _weightController,
            autofocus: !_isEditing,
            enabled: !_isSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '體重 (kg)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('bodyWeightFormDateButton'),
            onPressed: _isSaving ? null : _pickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(formatBodyWeightDateTime(_selectedDate)),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('bodyWeightFormNoteField'),
            controller: _noteController,
            enabled: !_isSaving,
            decoration: const InputDecoration(labelText: '備註（選填）'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // 對照 iOS `AddBodyWeightSheet` 工具列的「取消」按鈕——單純
              // 關閉表單、不寫入任何資料，不需要經過 controller。
              Expanded(
                child: OutlinedButton(
                  key: const Key('bodyWeightFormCancelButton'),
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const Key('bodyWeightFormSaveButton'),
                  onPressed: _parsedWeight != null && !_isSaving ? _save : null,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? '更新' : '儲存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
