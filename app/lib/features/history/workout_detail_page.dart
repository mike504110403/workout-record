// 訓練詳情頁——`Navigator.push` 獨立頁,不掛 route(照波 4 `PrListPage`
// 慣例,見 router.dart:233-236 注釋)。對照 iOS `WorkoutDetailView`。
//
// 吃呼叫端已經組裝好的完整 [Workout](`fetchAll`/`fetchByDateRange` 都已
// `_hydrate` 好 exercises/sets),不再自己另外查詢一次——歷史列表/日曆頁
// 本來就手上有完整資料,沒有必要為了同一份資料多打一次 DB。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/metric_row.dart';
import '../../core/widgets/metric_tile.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/workout.dart';
import '../../data/providers.dart';
import '../../core/theme/app_text_styles.dart';
import '../settings/preferences/weight_unit.dart';
import 'edit/workout_edit_page.dart';
import 'history_calendar_controller.dart';
import 'history_format.dart';
import 'history_list_controller.dart';
import 'widgets/delete_workout_dialog.dart';

class WorkoutDetailPage extends ConsumerStatefulWidget {
  const WorkoutDetailPage({super.key, required this.workout});

  final Workout workout;

  @override
  ConsumerState<WorkoutDetailPage> createState() => _WorkoutDetailPageState();
}

class _WorkoutDetailPageState extends ConsumerState<WorkoutDetailPage> {
  bool _isDeleting = false;

  /// 顯示中的訓練。初值來自呼叫端組好的快照(見檔頭注釋);編輯返回後由
  /// [_openEdit] 以 `fetchById` 重讀覆蓋——編輯頁寫穿 DB,快照不重讀會
  /// 停在舊值(WAVE5 merge 接線,review MINOR-7)。
  late Workout _workout = widget.workout;

  /// 推入編輯頁;返回後重讀本頁資料,並讓列表/日曆失效(編輯改動 summary
  /// 後,同分頁返回不經 router 的 branch-switch 失效點,要在這裡補)。
  /// 重讀失敗或查無此筆(理論上不會:編輯頁刪不掉 workout 本體)時保留
  /// 原快照,不擋使用者。
  Future<void> _openEdit(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => WorkoutEditPage(workoutId: _workout.id)));
    if (!mounted) return;
    ref.invalidate(historyListControllerProvider);
    ref.invalidate(historyCalendarControllerProvider);
    try {
      final refreshed = await ref.read(workoutRepositoryProvider).fetchById(_workout.id);
      if (!mounted || refreshed == null) return;
      setState(() => _workout = refreshed);
    } catch (_) {
      // 重讀失敗保留原快照;列表/日曆已 invalidate,返回上一頁仍會拿到新資料。
    }
  }

  @override
  Widget build(BuildContext context) {
    final workout = _workout;
    return Scaffold(
      appBar: AppBar(
        title: const Text('訓練詳情'),
        actions: [
          IconButton(
            key: const Key('workoutDetailEditButton'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: '編輯',
            onPressed: _isDeleting ? null : () => _openEdit(context),
          ),
          IconButton(
            key: const Key('workoutDetailDeleteButton'),
            icon: _isDeleting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_outline),
            tooltip: '刪除',
            onPressed: _isDeleting ? null : () => _confirmAndDelete(context, workout),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding.copyWith(top: AppSpacing.sm, bottom: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SummaryCard(workout: workout),
            // 只有 1 個動作時,分布永遠是 100%,卡片沒有資訊量 → 至少 2 個動作才顯示。
            if (workout.exercises.length >= 2) ...[
              const SizedBox(height: AppSpacing.lg),
              _VolumeBreakdownCard(workout: workout),
            ],
            const SizedBox(height: AppSpacing.lg),
            _ExerciseDetailList(workout: workout),
          ],
        ),
      ),
    );
  }

  /// 刪除:確認對話框 → 呼叫跟列表/滑動刪除同一個
  /// `HistoryListController.deleteWorkout`(單一刪除邏輯,見該檔案文件
  /// 注解)→ 成功 pop 回列表;失敗解除 `_isDeleting`(按鈕恢復可按)並秀
  /// SnackBar,停留在詳情頁——非同步失敗一律要處理,不 fire-and-forget。
  Future<void> _confirmAndDelete(BuildContext context, Workout workout) async {
    final confirmed = await showDeleteWorkoutDialog(context, workout, ref.read(weightUnitProvider));
    if (confirmed != true) return;
    setState(() => _isDeleting = true);
    try {
      await ref.read(historyListControllerProvider.notifier).deleteWorkout(workout.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!context.mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刪除失敗，請稍後再試')));
    }
  }
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final theme = Theme.of(context);
    return AppCard(
      key: const Key('workoutDetailSummaryCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(formatHistoryDate(workout.startedAt), style: theme.textTheme.titleMedium),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    formatHistoryWeekday(workout.startedAt),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              Text(
                formatVolumeKg(workout.totalVolume, unit),
                key: const Key('workoutDetailTotalVolume'),
                style: AppNumberStyles.medium(context).copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          MetricRow(
            tiles: [
              MetricTile(
                key: const Key('workoutDetailDuration'),
                label: '時長',
                value: '${workout.duration ?? 0}',
                unit: '分鐘',
              ),
              MetricTile(
                key: const Key('workoutDetailTotalSets'),
                label: '總組數',
                value: '${workout.totalSets}',
                unit: '組',
              ),
              MetricTile(
                key: const Key('workoutDetailTotalExercises'),
                label: '動作數',
                value: '${workout.totalExercises}',
                unit: '個',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 容量分布卡:各動作容量佔比。用 [nonWarmupExerciseVolume](排除暖身組)
/// 現算每個動作的容量,不信任 `WorkoutExercise.totalVolume` 欄位——同
/// `WorkoutRepository.completeWorkout` 文件注解:該欄位沒有任何寫入路徑會
/// 即時維護。分母用 `workout.totalVolume`(訓練層級欄位,`completeWorkout`
/// 完成訓練時已正確計算並落地,可信任)。
class _VolumeBreakdownCard extends ConsumerWidget {
  const _VolumeBreakdownCard({required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final totalVolume = workout.totalVolume;
    return AppCard(
      key: const Key('workoutDetailVolumeBreakdownCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '容量分布',
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          ),
          for (final exercise in workout.exercises)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(child: Text(workoutExerciseDisplayName(exercise))),
                  Text(formatVolumeKg(nonWarmupExerciseVolume(exercise), unit)),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    formatPercentage(
                      totalVolume > 0 ? nonWarmupExerciseVolume(exercise) / totalVolume * 100 : 0,
                    ),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 動作明細:每組的組號、重量、次數、容量。簡潔為先,直接平鋪不做展開/
/// 摺疊(brief:「可展開摺疊或直接平鋪,簡潔為先」)。
class _ExerciseDetailList extends ConsumerWidget {
  const _ExerciseDetailList({required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    return Column(
      key: const Key('workoutDetailExerciseList'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '動作明細'),
        for (final exercise in workout.exercises)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              key: Key('workoutDetailExercise-${exercise.id}'),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workoutExerciseDisplayName(exercise),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // 表頭:對照 iOS WorkoutDetailView.swift:283-296(組/重量/次數/
                  // 休息/容量),欄寬與下方每組列一致。
                  Padding(
                    key: Key('workoutDetailSetHeader-${exercise.id}'),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: DefaultTextStyle.merge(
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      child: const Row(
                        children: [
                          SizedBox(width: 56, child: Text('組')),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text('重量')),
                          Expanded(child: Text('次數')),
                          Expanded(child: Text('休息')),
                          Expanded(child: Text('容量', textAlign: TextAlign.end)),
                        ],
                      ),
                    ),
                  ),
                  for (final set in exercise.sets)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          // review 打回 MINOR-4:暖身組不排進容量分布卡的加總
                          // (`_VolumeBreakdownCard` 用 `nonWarmupExerciseVolume`
                          // 排除暖身組),這裡平鋪列出每一組時如果不標記,使用者
                          // 會拿這裡的各組容量手動加總、發現跟分布卡對不上——
                          // 加「(暖身)」標記(照 workout_summary_sheet.dart:118
                          // 既有慣例)。
                          //
                          // review 打回 r2 MINOR-A:這裡原本是裸 `Text`,暖身列
                          // 的「(暖身)」讓這一格比其他列寬,後面的重量/次數/
                          // 容量三欄跟著位移,整個表格對不齊。改回固定寬度容器
                          // 包住(對照修復前 `SizedBox(width: 28)` 的做法,寬度
                          // 加大到能放下「#10 (暖身)」不換行;超長內容用
                          // ellipsis 兜底,不讓極端情況撐開欄寬)。
                          SizedBox(
                            width: 56,
                            child: Text(
                              '#${set.setNumber}${set.isWarmup ? ' (暖身)' : ''}',
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          // review 打回 MINOR-3:改用 formatWeightKg,不直印
                          // double(避免「60.0 kg」這種不必要的浮點尾綴)。
                          Expanded(child: Text(formatWeightKg(set.weight, unit))),
                          Expanded(child: Text('${set.reps} 次')),
                          // 休息時間:對照 iOS WorkoutDetailView.swift:328-340,
                          // 有值顯示 formatRestSeconds、無值顯示「-」。
                          Expanded(
                            child: Text(
                              set.restSeconds != null ? formatRestSeconds(set.restSeconds!) : '-',
                              key: Key('workoutDetailRest_${set.id}'),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(child: Text(formatVolumeKg(set.volume, unit), textAlign: TextAlign.end)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
