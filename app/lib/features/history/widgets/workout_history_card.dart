// 單筆訓練的摘要卡——列表檢視、日曆檢視「當天訓練清單」共用同一份(對照
// iOS `WorkoutHistoryCard`)。顯示欄位依 brief 規格:日期、總容量、時長、
// 動作數(不含組數——組數留給詳情頁的完整 summary)。
import 'package:flutter/material.dart';

import '../../../data/models/workout.dart';
import '../history_format.dart';

class WorkoutHistoryCard extends StatelessWidget {
  const WorkoutHistoryCard({
    super.key,
    required this.workout,
    required this.onTap,
    this.isDeleting = false,
  });

  final Workout workout;
  final VoidCallback onTap;

  /// true 時在卡片上蓋一層 loading 遮罩、停用點擊——對應
  /// `HistoryListController.deletingIds` 追蹤中的這一筆(見該檔案文件注
  /// 解:刪除失敗時這個旗標會被移除,遮罩隨之解除,不會卡死)。
  final bool isDeleting;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('historyWorkoutCard-${workout.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          ListTile(
            onTap: isDeleting ? null : onTap,
            title: Text(formatHistoryDate(workout.startedAt)),
            subtitle: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 14),
                const SizedBox(width: 4),
                Text(formatDurationMinutes(workout.duration)),
                const SizedBox(width: 16),
                const Icon(Icons.fitness_center, size: 14),
                const SizedBox(width: 4),
                Text('${workout.totalExercises} 個動作'),
              ],
            ),
            trailing: Text(
              formatVolumeKg(workout.totalVolume),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
            ),
          ),
          if (isDeleting)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    key: Key('historyWorkoutDeletingIndicator-${workout.id}'),
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
