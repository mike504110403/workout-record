// 體重卡:當前體重 + 近 7 天變化 + 「記錄體重」次要入口。
//
// 近 7 天變化由 DashboardController 以既有 BodyWeightRepository.fetchByDateRange
// 算出(區間內最新一筆減最早一筆);不足兩筆算不出時顯示 —。變化只用中性色:
// 對減脂與增肌的人,體重上升/下降的好壞相反,不套 success/warning。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../settings/preferences/weight_unit.dart';
import '../dashboard_format.dart';

class BodyWeightCard extends ConsumerWidget {
  const BodyWeightCard({
    super.key,
    required this.currentWeight,
    required this.weekChange,
    required this.onRecord,
  });

  final double? currentWeight;

  /// 近 7 天變化(kg);null 代表算不出(顯示 —)。
  final double? weekChange;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final weight = currentWeight;
    final change = weekChange;

    return AppCard(
      key: const Key('bodyWeightMiniCard'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '當前體重',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (weight != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(formatWeightKg(weight, unit), style: AppNumberStyles.large(context)),
                    ),
                  )
                else
                  Text(
                    '尚未記錄',
                    style: theme.textTheme.titleLarge?.copyWith(color: colors.onSurfaceVariant),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '近 7 天 ${change == null ? '—' : formatWeightChange(change, unit)}',
                  key: const Key('bodyWeightWeekChange'),
                  style: AppNumberStyles.body(context).copyWith(
                    fontSize: theme.textTheme.bodySmall?.fontSize,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          OutlinedButton.icon(
            key: const Key('quickActionRecordWeight'),
            onPressed: onRecord,
            icon: const Icon(Icons.add),
            label: const Text('記錄體重'),
          ),
        ],
      ),
    );
  }
}
