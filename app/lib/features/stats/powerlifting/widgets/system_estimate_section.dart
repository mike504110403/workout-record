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

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
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
    final accent = Theme.of(context).colorScheme.tertiary;
    return AppCard(
      key: const Key('systemEstimateSection'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題「訓練推估」照 iOS 畫面實際顯示字(PowerliftingView.swift:198);
          // 「系統推估」只是該段 MARK 註解用詞(code review 對齊)。
          SectionHeader(
            title: '訓練推估',
            padding: EdgeInsets.zero,
            trailing: best == null
                ? null
                : Container(
                    key: const Key('systemEstimateBadge'),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: AppRadius.chipRadius,
                    ),
                    child: Text(
                      '推估: ${formatWeight(best.oneRepMax, unit)} ${unitSuffix(unit)}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: accent, fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '根據您的訓練記錄推算',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          if (summaries.isEmpty)
            // 明指目前選取的動作(切換深蹲/臥推/硬舉時文案跟著變),
            // 不是泛稱「尚無訓練數據」。
            EmptyState(
              key: const Key('systemEstimateEmptyState'),
              icon: Icons.insights_outlined,
              title: '尚無${powerLiftLabel(lift)}的訓練紀錄',
              message: '開始訓練後系統會自動計算',
            )
          else
            for (final summary in summaries)
              if (summary.currentPR != null)
                _SystemRecordRow(summary: summary, formula: formula, accent: accent, unit: unit),
        ],
      ),
    );
  }
}

class _SystemRecordRow extends StatelessWidget {
  const _SystemRecordRow({
    required this.summary,
    required this.formula,
    required this.accent,
    required this.unit,
  });

  final PRSummary summary;
  final OneRmFormula formula;
  final Color accent;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final entry = currentPrEntry(summary, formula)!;
    final pr = entry.record;
    return Card(
      key: Key('systemRecordRow-${summary.exerciseId}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
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
                Text('推估', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: accent)),
                Text(
                  '${formatWeight(entry.oneRepMax, unit)} ${unitSuffix(unit)}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: accent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
