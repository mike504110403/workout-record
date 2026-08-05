// 1RM 趨勢圖(fl_chart LineChart + 藍色點標記)。對應 iOS
// `PowerliftingView.manualRecordsSection` 裡的 Swift Charts `Chart`。
//
// x 軸刻意用「索引」而非實際日期的 epoch 值——[records] 已由呼叫端保證依
// achievedAt 由舊到新排序,索引本身就等價於時間順序,不需要處理連續時間
// 刻度的縮放/去重複雜度,底部標籤仍照 achievedAt 顯示實際日期文字。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../data/models/power_lift_record.dart';
import '../powerlifting_format.dart';

class OneRmTrendChart extends StatelessWidget {
  const OneRmTrendChart({super.key, required this.records});

  /// 已依 achievedAt 由舊到新排序(呼叫端保證,見
  /// `powerlifting_calculations.dart` 的 `chartRecordsForLift`)。
  final List<PowerLiftRecord> records;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < records.length; i++) FlSpot(i.toDouble(), records[i].oneRepMax),
    ];

    return SizedBox(
      key: const Key('oneRmTrendChart'),
      height: 200,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 16),
        child: LineChart(
          LineChartData(
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                color: Colors.blue,
                barWidth: 2,
                dotData: const FlDotData(show: true),
              ),
            ],
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 || index >= records.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        formatDate(records[index].achievedAt),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
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
