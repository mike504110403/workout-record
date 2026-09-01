// 歷史頁「列表」檢視:扁平、日期降冪、無分組 header(對照 iOS
// `HistoryListView`)。刪除入口:滑動(`Dismissible`)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/workout.dart';
import 'history_list_controller.dart';
import 'widgets/delete_workout_dialog.dart';
import 'widgets/history_empty_state.dart';
import 'widgets/history_error_view.dart';
import 'widgets/workout_history_card.dart';
import 'workout_detail_page.dart';

class HistoryListView extends ConsumerWidget {
  const HistoryListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyListControllerProvider);
    return async.when(
      data: (state) {
        if (state.workouts.isEmpty) {
          return const HistoryEmptyState();
        }
        return ListView(
          // 段數/筆數不是無限增長的懶載入資料流(單一使用者本機 SQLite),
          // 刻意用 ListView 而非 ListView.builder——widget test 用
          // find.byKey 需要所有卡片都已建置進 Element tree,對照
          // pr_list_page.dart 同一個理由。
          padding: const EdgeInsets.all(16),
          children: [
            for (final workout in state.workouts)
              _HistoryListRow(workout: workout, isDeleting: state.deletingIds.contains(workout.id)),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => HistoryErrorView(
        retryButtonKey: const Key('historyListErrorRetryButton'),
        onRetry: () => ref.invalidate(historyListControllerProvider),
      ),
    );
  }
}

class _HistoryListRow extends ConsumerWidget {
  const _HistoryListRow({required this.workout, required this.isDeleting});

  final Workout workout;
  final bool isDeleting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key('historyWorkoutDismissible-${workout.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmAndDelete(context, ref),
      background: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.only(bottom: 12),
        child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
      ),
      child: WorkoutHistoryCard(
        workout: workout,
        isDeleting: isDeleting,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => WorkoutDetailPage(workout: workout)),
        ),
      ),
    );
  }

  /// 一律回傳 `false`——實際的增減交給 controller state 驅動重新
  /// build(成功刪除後該筆會從 `state.workouts` 消失,`_HistoryListRow`
  /// 隨之整個從樹上移除),不假手 `Dismissible` 自己的「回傳 true 就消失」
  /// 動畫。這樣失敗時卡片會留在原地(不會誤消失),loading 遮罩、錯誤
  /// SnackBar 才有意義。
  Future<bool> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDeleteWorkoutDialog(context, workout);
    if (confirmed != true) return false;
    try {
      await ref.read(historyListControllerProvider.notifier).deleteWorkout(workout.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('刪除失敗，請稍後再試')),
        );
      }
    }
    return false;
  }
}
