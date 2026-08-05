// 單一動作的 PR 卡片。對應 iOS `PRView.PRCard`(不含肌群標籤——分組標題
// 已經顯示肌群,卡片內不重複)。
import 'package:flutter/material.dart';

import '../../../../data/models/personal_record.dart';
import '../pr_format.dart';

class PrSummaryCard extends StatelessWidget {
  const PrSummaryCard({super.key, required this.summary});

  final PRSummary summary;

  @override
  Widget build(BuildContext context) {
    final pr = summary.currentPR;
    return Card(
      key: Key('prSummaryCard-${summary.exerciseId}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary.exerciseName, style: Theme.of(context).textTheme.titleMedium),
            if (pr != null) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  _StatItem(label: 'PR 重量', value: '${formatWeight(pr.weight)} kg'),
                  const SizedBox(width: 24),
                  _StatItem(label: '次數', value: '${pr.reps} 次'),
                  const SizedBox(width: 24),
                  _StatItem(label: '1RM 估算', value: '${formatWeight(pr.oneRepMax)} kg'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    formatDate(pr.achievedAt),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  if (summary.prHistory.length > 1)
                    Text(
                      '${summary.prHistory.length} 次記錄',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
