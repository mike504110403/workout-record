// 體重趨勢圖。對照 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Charts/BodyWeightChartView.swift`：
// 平滑曲線（isCurved，對齊 iOS `.interpolationMethod(.catmullRom)`）、藍色
// 漸層面積（上藍下透明）、資料點標記、綠色虛線目標體重水平線（無目標不畫）。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../data/models/body_weight.dart';
import '../body_weight_stats.dart';

class BodyWeightChart extends StatelessWidget {
  const BodyWeightChart({
    super.key,
    required this.entriesDesc,
    this.targetWeight,
  });

  /// 新到舊排序（沿用 `BodyWeightTabState.entriesDesc` 既有順序）——本
  /// widget 內部負責轉成升序再畫圖，呼叫端不需要事先反轉。
  final List<BodyWeight> entriesDesc;

  /// 目標體重；null 時不畫目標線（對照 iOS `targetWeight: Double?` 的
  /// `if let target = targetWeight` 判斷）。
  final double? targetWeight;

  @override
  Widget build(BuildContext context) {
    // 畫圖前先轉成 measuredAt 由舊到新——`entriesDesc` 是新到舊（列表用的
    // 既有順序），若這裡漏掉這一步、直接拿原始順序畫圖，折線的左右方向會
    // 完全反過來（widget test 的「排序反轉必紅」變異案例就是在驗證這個
    // 轉換確實發生）。
    final ascending = sortBodyWeightsAscending(entriesDesc);
    // x 值用 `measuredAt` 的毫秒時間戳，不是陣列索引——對齊 iOS
    // `BodyWeightChartView` 用 `Chart { LineMark(x: .value("日期",
    // point.date), ...) }` 讓 X 軸真的是時間軸：兩筆紀錄間隔一天跟間隔一個
    // 月在圖上要是不同的水平距離，用索引（0, 1, 2, …）會讓資料點永遠等距
    // 排列，量測間隔失真（review 打回項目：「不等距種子 → spots x 值反映
    // 真實間隔」測試就是在守這件事）。
    final spots = [
      for (final entry in ascending)
        FlSpot(entry.measuredAt.millisecondsSinceEpoch.toDouble(), entry.weight),
    ];

    final target = targetWeight;

    return SizedBox(
      key: const Key('bodyWeightChart'),
      height: 220,
      child: Padding(
        padding: const EdgeInsets.only(right: 16, top: 16),
        child: LineChart(
          LineChartData(
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: Colors.blue,
                barWidth: 2.5,
                dotData: const FlDotData(),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.blue.withValues(alpha: 0.3),
                      Colors.blue.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
            // 目標線只在有目標時放進 list——沒有目標時 `horizontalLines`
            // 維持空 list（不是「放一條 alpha:0 的線」之類的偽隱藏），
            // widget test 直接斷言這個 list 的長度來驗證「無目標不畫線」。
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                if (target != null)
                  HorizontalLine(
                    y: target,
                    color: Colors.green,
                    strokeWidth: 2,
                    dashArray: const [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: const TextStyle(color: Colors.green, fontSize: 11),
                      labelResolver: (line) => '目標 ${line.y.toStringAsFixed(1)} kg',
                    ),
                  ),
              ],
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              // X 軸月/日標籤——對齊 iOS `BodyWeightChartView.chartXAxis`
              // 的 `AxisValueLabel(format: .dateTime.month().day())`。
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${date.month}/${date.day}', style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 40),
              ),
            ),
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }
}
