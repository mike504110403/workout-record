// 歷史頁「列表」檢視:日期降冪,按週分組(「本週」「上週」「M/D – M/D」,
// 見 history_week_grouping.dart)。iOS `HistoryListView` 是扁平無分組,這是
// UI 優化波的刻意差異。刪除入口:滑動(`Dismissible`)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/workout.dart';
import '../settings/preferences/weight_unit.dart';
import 'history_list_controller.dart';
import 'history_week_grouping.dart';
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
        final groups = groupWorkoutsByWeek(state.workouts);
        return ListView(
          // 段數/筆數不是無限增長的懶載入資料流(單一使用者本機 SQLite),
          // 刻意用 ListView 而非 ListView.builder——widget test 用
          // find.byKey 需要所有卡片都已建置進 Element tree,對照
          // pr_list_page.dart 同一個理由。
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal,
            0,
            AppSpacing.pageHorizontal,
            AppSpacing.lg,
          ),
          children: [
            for (final (index, group) in groups.indexed) ...[
              SectionHeader(
                // key 用週起日而非標題:跨年時「M/D – M/D」標題可能重複。
                key: Key(
                  'historyWeekHeader-${group.weekStart.year}-${group.weekStart.month}-${group.weekStart.day}',
                ),
                title: group.label,
                padding: EdgeInsets.only(
                  top: index == 0 ? AppSpacing.sm : AppSpacing.lg,
                  bottom: AppSpacing.sm,
                ),
              ),
              for (final workout in group.workouts)
                _HistoryListRow(workout: workout, isDeleting: state.deletingIds.contains(workout.id)),
            ],
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
          borderRadius: AppRadius.cardRadius,
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
      ),
      child: WorkoutHistoryCard(
        workout: workout,
        isDeleting: isDeleting,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => WorkoutDetailPage(workout: workout))),
      ),
    );
  }

  /// 一律回傳 `false`——實際的增減交給 controller state 驅動重新
  /// build(成功刪除後該筆會從 `state.workouts` 消失,`_HistoryListRow`
  /// 隨之整個從樹上移除),不假手 `Dismissible` 自己的「回傳 true 就消失」
  /// 動畫。這樣失敗時卡片會留在原地(不會誤消失),loading 遮罩、錯誤
  /// SnackBar 才有意義。
  Future<bool> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDeleteWorkoutDialog(context, workout, ref.read(weightUnitProvider));
    if (confirmed != true) return false;
    try {
      await ref.read(historyListControllerProvider.notifier).deleteWorkout(workout.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刪除失敗，請稍後再試')));
      }
    }
    return false;
  }
}
