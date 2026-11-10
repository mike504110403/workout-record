// 單一動作的 PR 卡片。對應 iOS `PRView.PRCard`(不含肌群標籤——分組標題
// 已經顯示肌群,卡片內不重複)。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../data/models/personal_record.dart';
import '../../../settings/preferences/one_rm_formula_preference.dart';
import '../../../settings/preferences/weight_unit.dart';
import '../pr_detail_calculations.dart';
import '../pr_detail_page.dart';
import '../pr_format.dart';

class PrSummaryCard extends ConsumerWidget {
  const PrSummaryCard({super.key, required this.summary});

  final PRSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final formula = ref.watch(oneRmFormulaProvider);
    // 與詳情頁同一套口徑:依偏好公式對 prHistory 重算 1RM 挑當前 PR,
    // 不用儲存值(寫入當下的公式結果),否則換公式後卡片與詳情頁數字不一致。
    final current = currentPrEntry(summary, formula);
    final pr = current?.record;
    return Card(
      key: Key('prSummaryCard-${summary.exerciseId}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 對照 iOS `PRView` 的 NavigationLink -> PRDetailView。
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) =>
                PrDetailPage(exerciseId: summary.exerciseId, exerciseName: summary.exerciseName),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(summary.exerciseName, style: Theme.of(context).textTheme.titleMedium),
              if (pr != null) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    _StatItem(label: 'PR 重量', value: '${formatWeight(pr.weight, unit)} ${unitSuffix(unit)}'),
                    const SizedBox(width: AppSpacing.xl),
                    _StatItem(label: '次數', value: '${pr.reps} 次'),
                    const SizedBox(width: AppSpacing.xl),
                    _StatItem(
                      label: '1RM 估算',
                      value: '${formatWeight(current!.oneRepMax, unit)} ${unitSuffix(unit)}',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      formatDate(pr.achievedAt),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    if (summary.prHistory.length > 1)
                      Text(
                        '${summary.prHistory.length} 次記錄',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
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
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
