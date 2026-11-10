// 自定義動作的新增/編輯表單。對照 iOS `Views/Exercise/CustomExerciseFormView.swift`
// 的「基本資訊(名稱/類型/分類)+ 動作分析(主要肌群/動作模式)+ 說明 + 刪除」。
//
// 與 iOS 的差異(回報申報項):
// - iOS 的「目標肌群(多選)」+ `MuscleGroupPickerView` 對應 `targetMuscles`,
//   Flutter 的 Exercise 模型/Drift/Supabase schema 都沒有這個欄位 → 不做。
// - iOS 編輯存檔時漏寫 categoryId(改了分類存不進去),這裡編輯會一併存分類。
//
// 分類改變時自動帶出主要肌群(對照 iOS `mapCategoryToPrimaryMuscleGroup`);之後
// 使用者仍可手動改。建立模式初始就依預設分類帶出主要肌群,選動作器的肌群搜尋
// 才搜得到。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/seed_data.dart';
import '../../../data/models/exercise.dart';
import '../../workout/exercise_picker/exercise_picker_categories.dart';
import 'custom_exercises_controller.dart';
import 'delete_exercise_dialog.dart';

/// 分類 → 主要肌群(六個展示分類各對應一個)。
PrimaryMuscleGroup? primaryMuscleGroupForCategory(String categoryId) {
  switch (categoryId) {
    case SeedCategoryIds.chest:
      return PrimaryMuscleGroup.chest;
    case SeedCategoryIds.back:
      return PrimaryMuscleGroup.back;
    case SeedCategoryIds.legs:
      return PrimaryMuscleGroup.legs;
    case SeedCategoryIds.shoulders:
      return PrimaryMuscleGroup.shoulders;
    case SeedCategoryIds.arms:
      return PrimaryMuscleGroup.arms;
    case SeedCategoryIds.core:
      return PrimaryMuscleGroup.core;
  }
  return null;
}

/// 新增([existing] 為 null)或編輯。儲存/刪除成功時 pop 並回傳 true。
class CustomExerciseFormPage extends ConsumerStatefulWidget {
  const CustomExerciseFormPage({super.key, this.existing});

  final Exercise? existing;

  @override
  ConsumerState<CustomExerciseFormPage> createState() => _CustomExerciseFormPageState();
}

class _CustomExerciseFormPageState extends ConsumerState<CustomExerciseFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _categoryId;
  late ExerciseType _type;
  PrimaryMuscleGroup? _primaryMuscleGroup;
  MovementPattern? _movementPattern;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _descriptionController = TextEditingController(text: e?.description ?? '');
    _categoryId = e?.categoryId ?? kExercisePickerCategories.first.id;
    _type = e?.type ?? ExerciseType.freeWeight;
    _primaryMuscleGroup = e != null
        ? e.primaryMuscleGroup
        : primaryMuscleGroupForCategory(_categoryId);
    _movementPattern = e?.movementPattern;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(customExercisesControllerProvider.notifier);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await controller.create(
          name: _nameController.text,
          categoryId: _categoryId,
          type: _type,
          primaryMuscleGroup: _primaryMuscleGroup,
          movementPattern: _movementPattern,
          description: _descriptionController.text,
        );
      } else {
        await controller.updateExercise(
          existing,
          name: _nameController.text,
          categoryId: _categoryId,
          type: _type,
          primaryMuscleGroup: _primaryMuscleGroup,
          movementPattern: _movementPattern,
          description: _descriptionController.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${_isEdit ? '儲存' : '新增'}動作失敗,請稍後再試';
      });
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _busy) return;
    if (!await confirmDeleteExercise(context, existing)) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(customExercisesControllerProvider.notifier).deleteExercise(existing);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '刪除動作失敗,請稍後再試';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 既有動作的分類不在六個展示分類內(例如舊資料)時補一個項目,避免
    // DropdownButtonFormField 的 initialValue 不在 items 內而 assert。
    final categories = [
      ...kExercisePickerCategories,
      if (!kExercisePickerCategories.any((c) => c.id == _categoryId))
        ExercisePickerCategory(id: _categoryId, name: '其他'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '編輯動作' : '新增動作'),
        actions: [
          TextButton(
            key: const Key('customExerciseSaveButton'),
            onPressed: _busy ? null : _save,
            child: const Text('儲存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('customExerciseNameField'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: '動作名稱'),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => ref
                  .read(customExercisesControllerProvider.notifier)
                  .validateName(value ?? '', excludeId: widget.existing?.id),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ExerciseType>(
              key: const Key('customExerciseTypeField'),
              initialValue: _type,
              decoration: const InputDecoration(labelText: '動作類型'),
              items: [
                for (final type in ExerciseType.values)
                  DropdownMenuItem(value: type, child: Text(type.displayName)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('customExerciseCategoryField'),
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: '分類'),
              items: [
                for (final category in categories)
                  DropdownMenuItem(value: category.id, child: Text(category.name)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _categoryId = value;
                  // 對照 iOS:換分類時依分類帶出主要肌群(非六個展示分類則不動)。
                  final mapped = primaryMuscleGroupForCategory(value);
                  if (mapped != null) _primaryMuscleGroup = mapped;
                });
              },
            ),
            const SizedBox(height: 12),
            // 主要肌群會被分類連動改值,所以用 ValueKey 綁當前值強制重建
            // (DropdownButtonFormField 的 initialValue 只在建立時讀一次)。
            DropdownButtonFormField<PrimaryMuscleGroup?>(
              key: ValueKey('customExerciseMuscleField_${_primaryMuscleGroup?.value}'),
              initialValue: _primaryMuscleGroup,
              decoration: const InputDecoration(labelText: '主要肌群'),
              items: [
                const DropdownMenuItem(value: null, child: Text('未選擇')),
                for (final group in PrimaryMuscleGroup.values)
                  DropdownMenuItem(value: group, child: Text(group.displayName)),
              ],
              onChanged: (value) => setState(() => _primaryMuscleGroup = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MovementPattern?>(
              key: const Key('customExercisePatternField'),
              initialValue: _movementPattern,
              decoration: const InputDecoration(labelText: '動作模式'),
              items: [
                const DropdownMenuItem(value: null, child: Text('未選擇')),
                for (final pattern in MovementPattern.values)
                  DropdownMenuItem(value: pattern, child: Text(pattern.displayName)),
              ],
              onChanged: (value) => setState(() => _movementPattern = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('customExerciseDescriptionField'),
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: '說明(選填)', alignLabelWithHint: true),
              minLines: 3,
              maxLines: 6,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('customExerciseFormError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_isEdit) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const Key('customExerciseDeleteButton'),
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('刪除動作', style: TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
