// 系統推估區。對應 iOS `PowerliftingView.systemEstimatedSection` +
// `SystemRecordRow`。
//
// 差異(見 powerlifting_calculations.dart 開頭注解):iOS 攤平每一筆歷史
// PersonalRecord 逐筆列出;這裡改用 `PersonalRecordRepository.getPRSummary`
// 已經按動作分組好的 `PRSummary`(每個匹配動作一列,顯示其歷史最高
// currentPR)——資料層沒有暴露「未分組的原始歷史清單 + join 動作名稱」的
// 既有方法,重新造一份等價於 iOS 的攤平清單不符合「照搬既有方法」的
// 指示,改用既有 `getPRSummary` 是更貼近既有資料層形狀的等價實作。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/personal_record.dart';
import '../../../../data/models/power_lift_record.dart';
import '../../../settings/preferences/one_rm_formula_preference.dart';
import '../../../settings/preferences/weight_unit.dart';
import '../../pr/pr_detail_calculations.dart';
import '../powerlifting_calculations.dart';
import '../powerlifting_format.dart';

class SystemEstimateSection extends ConsumerWidget {
  const SystemEstimateSection({super.key, required this.summaries, required this.lift});

  /// 動作名稱匹配目前選取三項動作的 PRSummary 清單(可能對到多個實際動作,
  /// 例如「臥推」同時匹配「槓鈴臥推」與「上斜臥推」)。
  final List<PRSummary> summaries;

  /// 目前選取的三項動作(用來在 [summaries] 中取推估最高者)。
  final PowerLift lift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    // 1RM 依偏好公式重算,與 PR 清單/詳情頁同口徑(見 currentPrEntry)。
    final formula = ref.watch(oneRmFormulaProvider);
    final best = bestSystemEstimate(summaries, lift, formula: formula);
    final orange = Colors.orange;
    return Card(
      key: const Key('systemEstimateSection'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 標題「訓練推估」照 iOS 畫面實際顯示字(PowerliftingView.swift:198);
                // 「系統推估」只是該段 MARK 註解用詞(code review 對齊)。
                Text('訓練推估', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (best != null)
                  Container(
                    key: const Key('systemEstimateBadge'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '推估: ${formatWeight(best.oneRepMax, unit)} ${unitSuffix(unit)}',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: orange, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '根據您的訓練記錄推算',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (summaries.isEmpty)
              _EmptySystemEstimateState(orange: orange)
            else
              for (final summary in summaries)
                if (summary.currentPR != null)
                  _SystemRecordRow(summary: summary, formula: formula, orange: orange, unit: unit),
          ],
        ),
      ),
    );
  }
}

class _EmptySystemEstimateState extends StatelessWidget {
  const _EmptySystemEstimateState({required this.orange});

  final Color orange;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('systemEstimateEmptyState'),
      height: 120,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined, size: 32, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              '尚無訓練數據\n開始訓練後系統會自動計算',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemRecordRow extends StatelessWidget {
  const _SystemRecordRow({required this.summary, required this.formula, required this.orange, required this.unit});

  final PRSummary summary;
  final OneRmFormula formula;
  final Color orange;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final entry = currentPrEntry(summary, formula)!;
    final pr = entry.record;
    return Card(
      key: Key('systemRecordRow-${summary.exerciseId}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(summary.exerciseName, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${formatWeight(pr.weight, unit)} ${unitSuffix(unit)} × ${pr.reps} 次 · ${formatDate(pr.achievedAt)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('推估', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: orange)),
                Text(
                  '${formatWeight(entry.oneRepMax, unit)} ${unitSuffix(unit)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: orange),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
