// 手動紀錄列表(三項表記錄)+ 1RM 趨勢圖。對應 iOS
// `PowerliftingView.manualRecordsSection` + `ManualRecordRow`。
//
// 空狀態文案沿用 iOS `emptyChartView(message: "尚無三項表記錄\n點擊右上角 +
// 開始記錄")`(介面改版:「新增」改成動作 chip 列右側的「+」鈕,文案跟著改)。
// 圖表至少 2 筆才畫,只有 1 筆時顯示「再記錄一筆就能看到趨勢」。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../data/models/power_lift_record.dart';
import '../../../settings/preferences/weight_unit.dart';
import '../powerlifting_format.dart';
import '../../trend_need_more_data.dart';
import 'one_rm_trend_chart.dart';

class ManualRecordsSection extends ConsumerWidget {
  const ManualRecordsSection({
    super.key,
    required this.records,
    required this.chartRecords,
    required this.currentPR,
    required this.onDelete,
  });

  /// 已依 achievedAt 由新到舊排序(對照 iOS `currentManualRecords`)。
  final List<PowerLiftRecord> records;

  /// 已依 achievedAt 由舊到新排序,給圖表用(對照 iOS `chartData`)。
  final List<PowerLiftRecord> chartRecords;

  final PowerLiftRecord? currentPR;

  /// 刪除單筆紀錄。失敗時拋出的例外由呼叫端(_ManualRecordRow)接住並顯示
  /// SnackBar,這裡不吞例外。
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    return AppCard(
      key: const Key('manualRecordsSection'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: '三項表記錄',
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            trailing: currentPR == null
                ? null
                : _Badge(
                    key: const Key('manualPrBadge'),
                    text: 'PR: ${formatWeight(currentPR!.oneRepMax, unit)} ${unitSuffix(unit)}',
                    color: context.semanticColors.pr,
                  ),
          ),
          if (chartRecords.isEmpty)
            const SizedBox(
              height: 200,
              child: EmptyState(
                key: Key('powerliftingEmptyState'),
                icon: Icons.show_chart,
                title: '尚無三項表記錄',
                message: '點上方的「+」開始記錄',
              ),
            )
          else if (chartRecords.length < kMinTrendPoints)
            const SizedBox(height: 200, child: TrendNeedMoreData(key: Key('powerliftingNeedMoreData')))
          else
            OneRmTrendChart(records: chartRecords),
          if (records.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            // 與 iOS 的刻意差異:iOS 只顯示 .prefix(5),這裡全列——被截掉的
            // 紀錄在 iOS 上永遠刪不到;CRUD 列表全列才能管理(review 裁定保留)。
            for (final record in records) _ManualRecordRow(record: record, onDelete: onDelete, unit: unit),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: AppRadius.chipRadius),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ManualRecordRow extends StatefulWidget {
  const _ManualRecordRow({required this.record, required this.onDelete, required this.unit});

  final PowerLiftRecord record;
  final Future<void> Function(String id) onDelete;
  final WeightUnit unit;

  @override
  State<_ManualRecordRow> createState() => _ManualRecordRowState();
}

class _ManualRecordRowState extends State<_ManualRecordRow> {
  bool _isDeleting = false;

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('刪除紀錄'),
        content: const Text('確定要刪除這筆三項紀錄嗎?此動作無法復原。'),
        actions: [
          TextButton(
            key: const Key('cancelDeletePowerLiftRecordButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('confirmDeletePowerLiftRecordButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await widget.onDelete(widget.record.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刪除失敗，請稍後再試')));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final hasNote = record.note != null && record.note!.trim().isNotEmpty;

    return Card(
      key: Key('manualRecordRow-${record.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatDate(record.achievedAt), style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${formatWeight(record.weight, widget.unit)} ${unitSuffix(widget.unit)} × ${record.reps} 次',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  if (hasNote)
                    Text(
                      record.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '1RM',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                Text(
                  '${formatWeight(record.oneRepMax, widget.unit)} ${unitSuffix(widget.unit)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            IconButton(
              key: Key('deletePowerLiftRecordButton-${record.id}'),
              icon: _isDeleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline),
              onPressed: _isDeleting ? null : _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }
}
