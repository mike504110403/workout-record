// PR 進步趨勢圖(1RM 隨達成日變化)。對照 iOS `PRDetailView.prProgressChart`:
// 主色折線 + 資料點。x 軸用達成日的 epoch 毫秒(真實時間軸,間隔不等距,
// 同 body_weight_chart.dart),y 值為 1RM 依目前單位換算後的顯示值。
//
// 只有一筆資料時 minX == maxX,fl_chart 的刻度/縮放會除以零,所以單點時
// 左右各補 1 天的顯示範圍(資料點仍只有一個)。
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../settings/preferences/weight_unit.dart';
import '../../chart_palette.dart';
import '../pr_detail_calculations.dart';

const _oneDayMs = 24 * 60 * 60 * 1000;

class PrProgressChart extends ConsumerWidget {
  const PrProgressChart({super.key, required this.entriesAsc});

  /// 已依達成日由舊到新排序(見 [PrDetailData.chartAsc])。
  final List<PrDetailEntry> entriesAsc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final color = chartColorFor(context, MuscleGroupFilter.all);

    final spots = [
      for (final e in entriesAsc)
        FlSpot(e.record.achievedAt.millisecondsSinceEpoch.toDouble(), kgToDisplay(e.oneRepMax, unit)),
    ];
    if (spots.isEmpty) return const SizedBox.shrink();

    final minXData = spots.map((s) => s.x).reduce(math.min);
    final maxXData = spots.map((s) => s.x).reduce(math.max);
    final single = minXData == maxXData;
    final minX = single ? minXData - _oneDayMs : minXData;
    final maxX = single ? maxXData + _oneDayMs : maxXData;
    final bottomInterval = math.max((maxX - minX) / 4, _oneDayMs.toDouble());
    DateTime? lastShownDate;

    return SizedBox(
      key: const Key('prProgressChart'),
      height: 200,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm, right: AppSpacing.lg),
        child: LineChart(
          LineChartData(
            minX: minX,
            maxX: maxX,
            lineBarsData: [
              LineChartBarData(spots: spots, color: color, barWidth: 2, dotData: const FlDotData(show: true)),
            ],
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: bottomInterval,
                  getTitlesWidget: (value, meta) {
                    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                    final last = lastShownDate;
                    final sameDay =
                        last != null &&
                        last.year == date.year &&
                        last.month == date.month &&
                        last.day == date.day;
                    if (sameDay) return const SizedBox.shrink();
                    lastShownDate = date;
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${date.month}/${date.day}', style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
