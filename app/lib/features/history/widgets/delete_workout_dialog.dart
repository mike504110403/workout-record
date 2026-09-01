// 刪除訓練的共用確認對話框——列表項滑動刪除、詳情頁刪除按鈕兩處入口共用
// 同一份(對照 body_weight_record_list.dart 的 `_confirmDelete` 慣例)。
import 'package:flutter/material.dart';

import '../../../data/models/workout.dart';
import '../history_format.dart';

/// 顯示刪除確認對話框,回傳 `true`=確認刪除、`false`/`null`=取消
/// (含使用者點背景或系統返回關閉)。呼叫端一律把 `!= true` 視為取消,不
/// 執行刪除。
Future<bool?> showDeleteWorkoutDialog(BuildContext context, Workout workout) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('deleteWorkoutDialog'),
      title: const Text('刪除這筆訓練紀錄？'),
      content: Text('${formatHistoryDate(workout.startedAt)} · ${formatVolumeKg(workout.totalVolume)}'),
      actions: [
        TextButton(
          key: const Key('deleteWorkoutCancelButton'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('deleteWorkoutConfirmButton'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            '刪除',
            style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
          ),
        ),
      ],
    ),
  );
}
