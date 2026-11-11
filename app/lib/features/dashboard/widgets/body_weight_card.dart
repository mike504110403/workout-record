// 體重卡:單列「75.0 kg · 近 7 天 ▲0.4」+ 右側新增 icon。
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
    final secondary = AppNumberStyles.body(context).copyWith(color: colors.onSurfaceVariant);

    return AppCard(
      key: const Key('bodyWeightMiniCard'),
      // 單列卡:上下留白收緊,右側 icon 鈕(48)撐出的高度就是列高。
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            // 大字級/窄螢幕放不下時等比縮小,不換行、不溢位。
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (weight != null)
                      Text(
                        formatWeightKg(weight, unit),
                        key: const Key('bodyWeightValue'),
                        style: AppNumberStyles.body(context).copyWith(fontWeight: FontWeight.w600),
                      )
                    else
                      Text('尚未記錄', style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant)),
                    Text('  \u00B7  ', style: secondary),
                    Text(
                      '近 7 天 ${change == null ? '\u2014' : formatWeightChangeArrow(change, unit)}',
                      key: const Key('bodyWeightWeekChange'),
                      style: secondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('quickActionRecordWeight'),
            tooltip: '記錄體重',
            onPressed: onRecord,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
