// PR 詳情頁。對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/PR/PRDetailView.swift`:
// 當前 PR 卡 + 進步趨勢圖(>1 筆才顯示)+ 歷史列表(新到舊)。
//
// 契約:`Navigator.push` 的獨立頁(同 [PrListPage]),自帶 Scaffold。資料由
// [prDetailRecordsProvider] 依 exerciseId 載入(autoDispose,每次進入重查)。
// 重量依 `weightUnitProvider` 換算顯示(儲存恆 kg),1RM 依
// `oneRmFormulaProvider` 重算,細節見 `pr_detail_calculations.dart`。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/preferences/one_rm_formula_preference.dart';
import '../../settings/preferences/weight_unit.dart';
import 'pr_detail_calculations.dart';
import 'pr_detail_controller.dart';
import 'pr_format.dart';
import 'widgets/pr_progress_chart.dart';

class PrDetailPage extends ConsumerWidget {
  const PrDetailPage({super.key, required this.exerciseId, required this.exerciseName});

  final String exerciseId;
  final String exerciseName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(prDetailRecordsProvider(exerciseId));
    final formula = ref.watch(oneRmFormulaProvider);

    return Scaffold(
      appBar: AppBar(title: Text(exerciseName)),
      body: async.when(
        data: (records) {
          final data = buildPrDetailData(records, formula);
          if (data.isEmpty) return const _EmptyPrDetailState();
          return _PrDetailBody(data: data);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('載入失敗，請稍後再試'),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('prDetailErrorRetryButton'),
                onPressed: () => ref.invalidate(prDetailRecordsProvider(exerciseId)),
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrDetailBody extends StatelessWidget {
  const _PrDetailBody({required this.data});

  final PrDetailData data;

  @override
  Widget build(BuildContext context) {
    final current = data.current!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CurrentPrCard(entry: current),
          if (data.chartAsc.length > 1) ...[const SizedBox(height: 24), _ProgressSection(data: data)],
          const SizedBox(height: 24),
          _HistorySection(data: data),
        ],
      ),
    );
  }
}

class _CurrentPrCard extends ConsumerWidget {
  const _CurrentPrCard({required this.entry});

  final PrDetailEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final theme = Theme.of(context);
    final pr = entry.record;
    return Card(
      key: const Key('prDetailCurrentCard'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.orange),
                const SizedBox(width: 8),
                Text('當前 PR', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BigStat(
                  valueKey: const Key('prDetailCurrentWeight'),
                  value: formatWeight(pr.weight, unit),
                  unit: unitSuffix(unit),
                  label: '重量',
                ),
                _BigStat(
                  valueKey: const Key('prDetailCurrentReps'),
                  value: '${pr.reps}',
                  unit: '次',
                  label: '次數',
                ),
                _BigStat(
                  valueKey: const Key('prDetailCurrentOneRm'),
                  value: formatWeight(entry.oneRepMax, unit),
                  unit: unitSuffix(unit),
                  label: '1RM',
                  valueColor: Colors.blue,
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('達成日期：', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                Text(
                  formatDate(pr.achievedAt),
                  key: const Key('prDetailCurrentDate'),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.valueKey,
    required this.value,
    required this.unit,
    required this.label,
    this.valueColor,
  });

  final Key valueKey;
  final String value;
  final String unit;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      children: [
        Text(
          value,
          key: valueKey,
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: valueColor),
        ),
        const SizedBox(height: 4),
        Text(unit, style: muted),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _ProgressSection extends ConsumerWidget {
  const _ProgressSection({required this.data});

  final PrDetailData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final progress = data.progress;
    final theme = Theme.of(context);
    return Column(
      key: const Key('prDetailProgressSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('進步趨勢', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        PrProgressChart(entriesAsc: data.chartAsc),
        if (progress != null) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final positive = progress.deltaKg >= 0;
              final color = positive ? Colors.green : Colors.red;
              final sign = positive ? '+' : '';
              return Row(
                children: [
                  Icon(positive ? Icons.trending_up : Icons.trending_down, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text('總進步：', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  Text(
                    '$sign${formatWeight(progress.deltaKg, unit)} ${unitSuffix(unit)} '
                    '($sign${progress.percent.toStringAsFixed(1)}%)',
                    key: const Key('prDetailProgressText'),
                    style: TextStyle(fontWeight: FontWeight.w600, color: color),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.data});

  final PrDetailData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = data.current?.record.id;
    return Column(
      key: const Key('prDetailHistoryList'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('歷史記錄', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final entry in data.historyDesc)
          _HistoryRow(entry: entry, isCurrent: entry.record.id == currentId),
      ],
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.entry, required this.isCurrent});

  final PrDetailEntry entry;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final theme = Theme.of(context);
    final pr = entry.record;
    return Container(
      key: Key('prDetailHistoryRow-${pr.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.orange.withValues(alpha: 0.1) : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDate(pr.achievedAt),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (isCurrent)
                  Text('當前 PR', style: theme.textTheme.labelSmall?.copyWith(color: Colors.orange)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _DataItem(label: '重量', value: '${formatWeight(pr.weight, unit)} ${unitSuffix(unit)}'),
          ),
          Expanded(
            child: _DataItem(label: '次數', value: '${pr.reps} 次'),
          ),
          Expanded(
            child: _DataItem(
              label: '1RM',
              value: '${formatWeight(entry.oneRepMax, unit)} ${unitSuffix(unit)}',
              highlight: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _DataItem extends StatelessWidget {
  const _DataItem({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
            color: highlight ? Colors.blue : null,
          ),
        ),
      ],
    );
  }
}

class _EmptyPrDetailState extends StatelessWidget {
  const _EmptyPrDetailState();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('prDetailEmptyState'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined, size: 60, color: Colors.orange),
            const SizedBox(height: 16),
            Text('尚無 PR 記錄', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '這個動作還沒有個人最佳記錄',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
