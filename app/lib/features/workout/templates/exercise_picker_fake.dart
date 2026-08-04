// WAVE3-MERGE: merge 時由大腦換接 exercise_picker 真實作
//
// 波 3 拆成兩段式、第一段內又分兩支平行工人:①動作選擇器(exercise-picker
// 工人獨立實作)+ ③模板管理(這個目錄)。兩支分支議定的段間接縫是這個檔案
// 的函式簽名:
//
//   Future<List<Exercise>?> showExercisePicker(BuildContext, {bool multiSelect})
//
// ③(模板管理)不實作真正的動作選擇器,只用這個最小可行的暫時替身頂替,
// 讓模板建立/編輯的動作挑選流程可以獨立開發、獨立測試,不用等①落地。
// 大腦 merge 兩支分支時,把 template_form_page.dart 裡 import 這個檔案的
// 那一行換成真正的 exercise_picker.dart 即可——函式簽名一致,呼叫端
// (template_form_page.dart)完全不用改。
//
// 這個替身刻意做到「夠用但不做多的」:列出全部啟用中的動作(不分類、不
// 搜尋),支援單選/多選,選好按確認回傳清單、取消回傳 null——只是為了讓
// 模板 CRUD 的整條流程有東西可以組裝、可以測,不是要做出一個像樣的動作
// 選擇器 UX。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/exercise.dart';
import '../../../data/providers.dart';

/// 見檔案開頭說明。回傳 null 代表使用者取消;回傳空清單代表「確定選 0 個」
/// (呼叫端目前的表單流程不會允許這麼做,但函式本身不擋)。
Future<List<Exercise>?> showExercisePicker(
  BuildContext context, {
  bool multiSelect = false,
}) {
  return showModalBottomSheet<List<Exercise>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ExercisePickerFakeSheet(multiSelect: multiSelect),
  );
}

class _ExercisePickerFakeSheet extends ConsumerStatefulWidget {
  const _ExercisePickerFakeSheet({required this.multiSelect});

  final bool multiSelect;

  @override
  ConsumerState<_ExercisePickerFakeSheet> createState() => _ExercisePickerFakeSheetState();
}

class _ExercisePickerFakeSheetState extends ConsumerState<_ExercisePickerFakeSheet> {
  final Set<String> _selectedIds = {};
  late Future<List<Exercise>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(exerciseRepositoryProvider).fetchAll();
  }

  void _toggle(Exercise exercise) {
    setState(() {
      if (widget.multiSelect) {
        if (_selectedIds.contains(exercise.id)) {
          _selectedIds.remove(exercise.id);
        } else {
          _selectedIds.add(exercise.id);
        }
      } else {
        _selectedIds
          ..clear()
          ..add(exercise.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('選擇動作(暫時替身,見 exercise_picker_fake.dart)'),
          leading: TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          leadingWidth: 72,
          actions: [
            TextButton(
              key: const Key('exercisePickerFakeConfirm'),
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () async {
                      final exercises = await _future;
                      final selected =
                          exercises.where((e) => _selectedIds.contains(e.id)).toList();
                      if (context.mounted) Navigator.of(context).pop(selected);
                    },
              child: const Text('確認'),
            ),
          ],
        ),
        body: FutureBuilder<List<Exercise>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final exercises = snapshot.data!;
            return ListView.builder(
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final exercise = exercises[index];
                final selected = _selectedIds.contains(exercise.id);
                return CheckboxListTile(
                  key: Key('exercisePickerFakeItem_${exercise.id}'),
                  value: selected,
                  title: Text(exercise.name),
                  onChanged: (_) => _toggle(exercise),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
