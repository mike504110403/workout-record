// 建立/編輯模板的共用表單頁。對照 iOS
// `WorkoutTemplateViewModel.createTemplate` / `updateTemplate`。
//
// 動作挑選走 exercise_picker 的 `showExercisePicker`(波 3 第一段兩支平行
// 分支議定的接縫;模板分支開發期間用同簽名 fake 頂替,merge 時已由大腦
// 換接真實作,fake 檔案同時移除)。
//
// 非同步失敗路徑:儲存失敗時停在表單畫面、解除 loading(`_saving = false`)、
// 用 SnackBar 顯示錯誤,不 pop——使用者可以修正後重試,不會弄丟已經填好
// 的內容(對照常備紀律:非同步失敗路徑一律要處理,不 fire-and-forget)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/exercise.dart';
import '../../../data/models/workout_template.dart';
import '../exercise_picker/exercise_picker_sheet.dart';
import 'templates_controller.dart';

/// 表單內部用的暫存動作項目:動作本身 + 使用者輸入的建議組數/次數。
class TemplateFormExerciseDraft {
  TemplateFormExerciseDraft({
    required this.exercise,
    this.suggestedSets,
    this.suggestedReps,
  });

  final Exercise exercise;
  int? suggestedSets;
  int? suggestedReps;
}

/// [existing] 為 null 代表建立新模板;非 null 代表編輯。呼叫端(
/// templates_list_page.dart)負責在導頁前就擋掉系統模板,不把它傳進來
/// ——這裡的 assert 只是最後一道防線。
class TemplateFormPage extends ConsumerStatefulWidget {
  const TemplateFormPage({super.key, this.existing});

  final WorkoutTemplate? existing;

  @override
  ConsumerState<TemplateFormPage> createState() => _TemplateFormPageState();
}

class _TemplateFormPageState extends ConsumerState<TemplateFormPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late List<TemplateFormExerciseDraft> _exercises;
  bool _saving = false;

  // minor 修復:組數/次數欄位先前打非數字字元會被 int.tryParse 靜默吃成
  // null,使用者毫無感覺。改成:非數字時顯示 inline 錯誤、且不覆寫既有的
  // suggestedSets/suggestedReps(避免亂打字元把它清掉),有錯誤時擋下儲存。
  // key 用 exercise.id——同一個模板裡動作不重複(_pickExercises 已去重),
  // 可以安全當穩定鍵。
  final Map<String, String> _setsErrors = {};
  final Map<String, String> _repsErrors = {};

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    assert(widget.existing?.isSystem != true, '系統模板不可編輯,呼叫端應該先擋下');
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _descriptionController = TextEditingController(text: widget.existing?.description ?? '');
    _exercises = [
      for (final templateExercise in widget.existing?.exercises ?? const <TemplateExercise>[])
        if (templateExercise.exercise != null)
          TemplateFormExerciseDraft(
            exercise: templateExercise.exercise!,
            suggestedSets: templateExercise.suggestedSets,
            suggestedReps: templateExercise.suggestedReps,
          ),
    ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickExercises() async {
    final picked = await showExercisePicker(context, multiSelect: true);
    if (picked == null || picked.isEmpty) return;
    setState(() {
      final existingIds = _exercises.map((draft) => draft.exercise.id).toSet();
      for (final exercise in picked) {
        if (existingIds.contains(exercise.id)) continue;
        _exercises.add(TemplateFormExerciseDraft(exercise: exercise));
      }
    });
  }

  void _removeExercise(int index) {
    final exerciseId = _exercises[index].exercise.id;
    setState(() {
      _exercises.removeAt(index);
      _setsErrors.remove(exerciseId);
      _repsErrors.remove(exerciseId);
    });
  }

  /// 組數/次數輸入框共用的 onChanged 邏輯:空字串視為「使用者主動清空」,
  /// 合法非負整數才寫回 [assign];非數字或負數只記 inline 錯誤,不動
  /// 既有的值(不再靜默把亂打的字元變成 null)。
  void _handleNumericInput({
    required String exerciseId,
    required String value,
    required Map<String, String> errors,
    required void Function(int?) assign,
  }) {
    setState(() {
      if (value.isEmpty) {
        assign(null);
        errors.remove(exerciseId);
        return;
      }
      final parsed = int.tryParse(value);
      if (parsed == null || parsed < 0) {
        errors[exerciseId] = '請輸入 0 或正整數';
      } else {
        assign(parsed);
        errors.remove(exerciseId);
      }
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請輸入模板名稱')));
      return;
    }
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請至少選擇一個動作')));
      return;
    }
    if (_setsErrors.isNotEmpty || _repsErrors.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請修正組數/次數欄位裡的錯誤輸入')));
      return;
    }

    setState(() => _saving = true);
    try {
      final exercises = [
        for (var i = 0; i < _exercises.length; i++)
          TemplateExercise(
            // id/templateId 是佔位值:TemplateRepository.create/update 寫入
            // 時一律用自己重新指派的值(templateId 一律取自模板本身,
            // orderIndex 一律取自清單位置),不讀這兩個欄位——見
            // template_repository.dart 的 create()/update() 實作。
            id: '',
            templateId: '',
            exerciseId: _exercises[i].exercise.id,
            exercise: _exercises[i].exercise,
            orderIndex: i,
            suggestedSets: _exercises[i].suggestedSets,
            suggestedReps: _exercises[i].suggestedReps,
          ),
      ];
      final descriptionText = _descriptionController.text.trim();
      final description = descriptionText.isEmpty ? null : descriptionText;
      final controller = ref.read(templatesControllerProvider.notifier);
      if (_isEditing) {
        await controller.updateTemplate(
          existing: widget.existing!,
          name: name,
          description: description,
          exercises: exercises,
        );
      } else {
        await controller.createTemplate(
          name: name,
          description: description,
          exercises: exercises,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditing ? '更新模板失敗:$e' : '建立模板失敗:$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '編輯模板' : '新增模板'),
        actions: [
          TextButton(
            key: const Key('templateFormSaveButton'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('儲存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('templateFormNameField'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: '名稱'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('templateFormDescriptionField'),
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: '描述(選填)'),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('動作', style: TextStyle(fontWeight: FontWeight.bold)),
              TextButton(
                key: const Key('templateFormAddExerciseButton'),
                onPressed: _pickExercises,
                child: const Text('新增動作'),
              ),
            ],
          ),
          for (var i = 0; i < _exercises.length; i++)
            Padding(
              key: Key('templateFormExerciseRow_${_exercises[i].exercise.id}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(_exercises[i].exercise.name)),
                  Expanded(
                    child: TextFormField(
                      key: Key('templateFormSetsField_${_exercises[i].exercise.id}'),
                      initialValue: _exercises[i].suggestedSets?.toString(),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '組',
                        errorText: _setsErrors[_exercises[i].exercise.id],
                      ),
                      onChanged: (value) => _handleNumericInput(
                        exerciseId: _exercises[i].exercise.id,
                        value: value,
                        errors: _setsErrors,
                        assign: (parsed) => _exercises[i].suggestedSets = parsed,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: Key('templateFormRepsField_${_exercises[i].exercise.id}'),
                      initialValue: _exercises[i].suggestedReps?.toString(),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '次',
                        errorText: _repsErrors[_exercises[i].exercise.id],
                      ),
                      onChanged: (value) => _handleNumericInput(
                        exerciseId: _exercises[i].exercise.id,
                        value: value,
                        errors: _repsErrors,
                        assign: (parsed) => _exercises[i].suggestedReps = parsed,
                      ),
                    ),
                  ),
                  IconButton(
                    key: Key('templateFormRemoveExerciseButton_${_exercises[i].exercise.id}'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeExercise(i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
