import 'package:flutter/material.dart';

import '../../../data/models/exercise.dart';

/// 刪除自定義動作前的確認對話框;使用者確認才回傳 true。
///
/// 文案要讓使用者知道:歷史訓練與模板裡的紀錄不受影響(軟刪除語義,見
/// custom_exercises_controller.dart 檔頭)。
Future<bool> confirmDeleteExercise(BuildContext context, Exercise exercise) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('刪除動作'),
      content: Text('確定要刪除「${exercise.name}」嗎?\n之後選動作時不會再出現,既有的訓練紀錄與模板不受影響。'),
      actions: [
        TextButton(
          key: const Key('customExerciseDeleteCancelButton'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('customExerciseDeleteConfirmButton'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('刪除', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  return confirmed == true;
}
