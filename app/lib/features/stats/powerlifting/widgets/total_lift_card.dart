// 三項總和 + 三項最佳成績並列卡。對應 iOS `PowerliftingView.totalCard`。
import 'package:flutter/material.dart';

import '../../../../data/models/power_lift_record.dart';
import '../powerlifting_format.dart';

const _liftLabels = {
  PowerLift.squat: '深蹲',
  PowerLift.benchPress: '槓鈴臥推',
  PowerLift.deadlift: '硬舉',
};

class TotalLiftCard extends StatelessWidget {
  const TotalLiftCard({
    super.key,
    required this.totalLifts,
    required this.bestByLift,
  });

  final double totalLifts;
  final Map<PowerLift, PowerLiftRecord?> bestByLift;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('totalLiftCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              '三項總和',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  key: const Key('totalLiftValue'),
                  formatWeight(totalLifts),
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
                const SizedBox(width: 4),
                Text('kg', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final lift in PowerLift.values) _BestLiftColumn(lift: lift, record: bestByLift[lift]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BestLiftColumn extends StatelessWidget {
  const _BestLiftColumn({required this.lift, required this.record});

  final PowerLift lift;
  final PowerLiftRecord? record;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('bestLiftColumn-${lift.name}'),
      children: [
        Text(
          _liftLabels[lift]!,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          record == null ? '--' : formatWeight(record!.oneRepMax),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
