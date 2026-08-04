// 選動作器右上角「+」快速新增自訂動作的小表單(brief 功能規格 4)。對等
// iOS `QuickAddExerciseSheet`。表單刻意精簡:名稱必填、分類必選(預設第一個
// 分類,可改),其餘(英文名稱、類型)選填/有預設值——與 brief「名稱必填、
// 分類選擇、其餘選填」的最小可行表單一致。movementPattern/primaryMuscleGroup
// 這兩個 nullable 欄位不在表單中收集(留 null),不是遺漏而是刻意縮小表單
// 範圍,回報中列為與 iOS 的差異申報項。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/exercise.dart';
import 'exercise_picker_categories.dart';
import 'exercise_picker_controller.dart';

/// 開啟快速新增表單。成功建立時回傳新建的 [Exercise];使用者取消或新增
/// 失敗(表單留在畫面上讓使用者重試,不 pop)時回傳 `null`。
Future<Exercise?> showQuickAddExerciseSheet(BuildContext context) {
  return showModalBottomSheet<Exercise?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _QuickAddExerciseForm(),
  );
}

class _QuickAddExerciseForm extends ConsumerStatefulWidget {
  const _QuickAddExerciseForm();

  @override
  ConsumerState<_QuickAddExerciseForm> createState() => _QuickAddExerciseFormState();
}

class _QuickAddExerciseFormState extends ConsumerState<_QuickAddExerciseForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nameEnController = TextEditingController();
  String _categoryId = kExercisePickerCategories.first.id;
  ExerciseType _type = ExerciseType.freeWeight;

  @override
  void dispose() {
    _nameController.dispose();
    _nameEnController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final controller = ref.read(exercisePickerControllerProvider.notifier);
    final created = await controller.addCustomExercise(
      name: _nameController.text.trim(),
      nameEn: _nameEnController.text,
      categoryId: _categoryId,
      type: _type,
    );

    if (!mounted) return;
    if (created != null) {
      Navigator.of(context).pop(created);
    }
    // 失敗時不 pop——錯誤訊息由下面的 ref.listen 彈 SnackBar,表單留在畫面
    // 上讓使用者可以修改後重試(常備紀律:非同步失敗路徑要處理,不得
    // fire-and-forget)。
  }

  @override
  Widget build(BuildContext context) {
    // 只在 customExerciseError 真的「新出現」時彈一次 SnackBar,不是每次
    // rebuild 都彈——比對前後兩次的錯誤訊息是否相同即可,重試又失敗時錯誤
    // 訊息字串相同不會重彈是可接受的(使用者已經看過同一句錯誤,連續失敗
    // 不需要重複彈窗轟炸)。
    ref.listen<AsyncValue<ExercisePickerState>>(exercisePickerControllerProvider, (
      previous,
      next,
    ) {
      final previousError = previous?.value?.customExerciseError;
      final nextError = next.value?.customExerciseError;
      if (nextError != null && nextError != previousError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(nextError)));
      }
    });

    final isSubmitting =
        ref.watch(exercisePickerControllerProvider).value?.isSubmittingCustomExercise ??
        false;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('新增自訂動作', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('quick_add_name_field'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: '動作名稱'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '請輸入動作名稱' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('quick_add_name_en_field'),
              controller: _nameEnController,
              decoration: const InputDecoration(labelText: '英文名稱(選填)'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('quick_add_category_field'),
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: '分類'),
              items: [
                for (final category in kExercisePickerCategories)
                  DropdownMenuItem(value: category.id, child: Text(category.name)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _categoryId = value);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ExerciseType>(
              key: const Key('quick_add_type_field'),
              initialValue: _type,
              decoration: const InputDecoration(labelText: '類型'),
              items: [
                for (final type in ExerciseType.values)
                  DropdownMenuItem(value: type, child: Text(type.displayName)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('quick_add_submit_button'),
              onPressed: isSubmitting ? null : _submit,
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('新增'),
            ),
          ],
        ),
      ),
    );
  }
}
