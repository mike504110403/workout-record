// 統計資訊卡片：當前體重、目標體重、平均、最高/最低、變化幅度。對照 iOS
// 版 `BodyWeightView.currentWeightCard` + `trendCard`（iOS 只有「變化/平均/
// 記錄」三項，本波依 brief 擴充成完整六項——目標體重、最高、最低是 brief
// 明列但 iOS 尚未串接的欄位，見 iOS `BodyWeightChartView(targetWeight: nil,
// // TODO: Get from user settings)`：這裡把「// TODO」補上，用真正的
// `UserGoalRepository.targetWeight`）。
import 'package:flutter/material.dart';

import '../body_weight_format.dart';
import '../body_weight_stats.dart';

class BodyWeightStatsGrid extends StatelessWidget {
  const BodyWeightStatsGrid({super.key, required this.summary});

  final BodyWeightSummary summary;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      key: const Key('bodyWeightStatsGrid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 1.6,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _StatTile(
          statKey: 'current',
          label: '當前體重',
          value: summary.current,
        ),
        _StatTile(
          statKey: 'target',
          label: '目標體重',
          value: summary.target,
        ),
        _StatTile(
          statKey: 'average',
          label: '平均',
          value: summary.average,
        ),
        _StatTile(
          statKey: 'max',
          label: '最高',
          value: summary.max,
        ),
        _StatTile(
          statKey: 'min',
          label: '最低',
          value: summary.min,
        ),
        _StatTile(
          statKey: 'change',
          label: '變化',
          value: summary.change,
          signed: true,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.statKey,
    required this.label,
    required this.value,
    this.signed = false,
  });

  final String statKey;
  final String label;
  final double? value;

  /// 變化幅度要帶正負號（對照 iOS `BodyWeightStatItem` 的上下箭頭 +
  /// `abs(value)`，這裡簡化成文字直接帶正負號，語意等價：正值代表增加、
  /// 負值代表減少）。
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final displayValue = v == null
        ? '—'
        : signed
            ? '${v > 0 ? '+' : ''}${formatBodyWeightKg(v)}'
            : formatBodyWeightKg(v);

    return Card(
      key: Key('bodyWeightStatCard-$statKey'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              displayValue,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
