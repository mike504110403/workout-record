// 體重趨勢圖。對照 iOS 版
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Charts/BodyWeightChartView.swift`：
// 平滑曲線（isCurved，對齊 iOS `.interpolationMethod(.catmullRom)`）、藍色
// 漸層面積（上藍下透明）、資料點標記、綠色虛線目標體重水平線（無目標不畫）。
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../data/models/body_weight.dart';
import '../body_weight_stats.dart';

/// 一天的毫秒數，X 軸標籤的最小刻度間隔——見 `_bottomTitleInterval`。
const _oneDayMs = 24 * 60 * 60 * 1000;

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

    // review 打回 S1:X 軸標籤短跨度重複——沒有明確指定 `interval` 時,
    // fl_chart 會依圖表寬度自行切出刻度間隔,資料點全部集中在一週內這種
    // 短時間跨度時,自動算出的間隔可能小於一天,同一天的多個刻度會各自
    // 顯示一次「M/d」文字,畫面上出現重複標籤。這裡強制刻度間隔至少一天
    // （`_oneDayMs`），並隨資料橫跨的總時間範圍等比放大（`range / 4`,約
    // 四個刻度）,兩者取大,減少候選刻度數。
    //
    // 但光靠 `interval` 不夠——實測 fl_chart 除了照 interval 等距切出的
    // 刻度之外,還會額外補一個貼齊 `maxX`(資料最後一筆)的邊界刻度確保
    // 範圍終點有刻度可看,這個邊界刻度常常跟前一個 interval 刻度落在同一
    // 天,單靠拉大 interval 治不了這種「邊界刻度」重複。改成在
    // `getTitlesWidget` 裡用一個閉包變數 `lastShownDate` 追蹤「上一個真的
    // 畫出來的刻度是哪一天」——fl_chart 依 x 遞增順序逐一呼叫這個
    // callback,同一天的後續刻度直接回傳 `SizedBox.shrink()`(佔位但不畫
    // 文字),確保畫面上任何時刻看到的日期標籤都是唯一的。
    final xs = spots.map((s) => s.x);
    final rangeMs = spots.isEmpty ? 0.0 : (xs.reduce(math.max) - xs.reduce(math.min));
    final bottomInterval = math.max(rangeMs / 4, _oneDayMs.toDouble());
    DateTime? lastShownDate;

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
                  interval: bottomInterval,
                  getTitlesWidget: (value, meta) {
                    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                    final last = lastShownDate;
                    final isSameDayAsLastShown =
                        last != null && last.year == date.year && last.month == date.month && last.day == date.day;
                    if (isSameDayAsLastShown) {
                      return const SizedBox.shrink();
                    }
                    lastShownDate = date;
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
