// 三項總和 + 三項最佳成績並列卡。對應 iOS `PowerliftingView.totalCard`。
//
// 三個動作都還沒有手動紀錄時,不顯示「總和 0.0 kg」大字(0 不是成績,是尚未
// 開始),改顯示空狀態引導新增。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/metric_row.dart';
import '../../../../core/widgets/metric_tile.dart';
import '../../../../data/models/power_lift_record.dart';
import '../../../settings/preferences/weight_unit.dart';
import '../powerlifting_format.dart';

class TotalLiftCard extends ConsumerWidget {
  const TotalLiftCard({super.key, required this.totalLifts, required this.bestByLift});

  final double totalLifts;
  final Map<PowerLift, PowerLiftRecord?> bestByLift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasAnyRecord = bestByLift.values.any((record) => record != null);

    if (!hasAnyRecord) {
      return const AppCard(
        key: Key('totalLiftCard'),
        child: EmptyState(
          key: Key('totalLiftEmptyState'),
          icon: Icons.fitness_center,
          title: '還沒有三項紀錄',
          message: '記錄三項後,這裡會顯示總和',
        ),
      );
    }

    return AppCard(
      key: const Key('totalLiftCard'),
      child: Column(
        children: [
          Text('三項總和', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                key: const Key('totalLiftValue'),
                formatWeight(totalLifts, unit),
                style: AppNumberStyles.display(context).copyWith(color: colorScheme.primary),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(unitSuffix(unit), style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          MetricRow(
            tiles: [
              for (final lift in PowerLift.values)
                MetricTile(
                  key: Key('bestLiftColumn-${lift.name}'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  value: bestByLift[lift] == null ? '--' : formatWeight(bestByLift[lift]!.oneRepMax, unit),
                  label: powerLiftLabel(lift),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
