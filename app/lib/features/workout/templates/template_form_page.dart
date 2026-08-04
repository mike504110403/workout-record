// 建立/編輯模板的共用表單頁。對照 iOS
// `WorkoutTemplateViewModel.createTemplate` / `updateTemplate`。
//
// 動作挑選走 exercise_picker_fake.dart 目前提供的暫時替身(見該檔案開頭
// WAVE3-MERGE 標記),真實作由另一支平行工人負責,merge 時大腦換這裡的
// import 即可,函式簽名一致不需要改呼叫邏輯。
//
// 非同步失敗路徑:儲存失敗時停在表單畫面、解除 loading(`_saving = false`)、
// 用 SnackBar 顯示錯誤,不 pop——使用者可以修正後重試,不會弄丟已經填好
// 的內容(對照常備紀律:非同步失敗路徑一律要處理,不 fire-and-forget)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/exercise.dart';
import '../../../data/models/workout_template.dart';
import 'exercise_picker_fake.dart';
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
    setState(() => _exercises.removeAt(index));
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
                      decoration: const InputDecoration(labelText: '組'),
                      onChanged: (value) => _exercises[i].suggestedSets = int.tryParse(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: Key('templateFormRepsField_${_exercises[i].exercise.id}'),
                      initialValue: _exercises[i].suggestedReps?.toString(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '次'),
                      onChanged: (value) => _exercises[i].suggestedReps = int.tryParse(value),
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
