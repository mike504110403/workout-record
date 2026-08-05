// 把 [VolumeDataPoint] 轉成 fl_chart 的 [FlSpot] 清單。獨立成純函式(不吃
// BuildContext),讓 widget test 可以直接斷言「資料層」(spots 的數量/數值)
// ,不必逐像素驗證圖表——對照 brief 的驗收要求。
import 'package:fl_chart/fl_chart.dart';

import 'chart_time_range.dart';
import '../chart_palette.dart';
import 'volume_aggregation.dart';

/// [buildVolumeSpots] 實際畫進圖表的資料點子集合——x 軸標籤(見
/// `volume_chart_section.dart` 的 bottom titles)要用同一份清單,索引才對
/// 得上 spots 的 x 值。
///
/// `all` 模式:全部資料點都畫。篩選特定肌群時:只有
/// `muscleGroupVolumes[muscleGroup] > 0`(當天真的練到該肌群)的資料點才
/// 畫——對齊 iOS `VolumeChartView.swift:106`
/// (`if let volume = point.muscleGroupVolumes[muscleGroup], volume > 0`),
/// 沒練到的日子整個跳過,不是落底畫一個 y=0 的點。
///
/// r2 review 打回記錄:先前這裡「沒練到就畫 0」,除了跟 iOS 行為不符,也跟
/// `calculateVolumeStats` 的「平均/最高只算有練到的日子」自相矛盾(一個算式
/// 排除沒練到的日子、另一個卻把它畫成 0 拉低視覺上的曲線觀感),已改為
/// 整點跳過、x 軸用篩選後子集合的連續索引。
List<VolumeDataPoint> chartPointsForFilter(List<VolumeDataPoint> dataPoints, MuscleGroupFilter filter) {
  if (filter == MuscleGroupFilter.all) return dataPoints;
  final muscleGroup = filter.primaryMuscleGroup!;
  return [
    for (final point in dataPoints)
      if ((point.muscleGroupVolumes[muscleGroup] ?? 0) > 0) point,
  ];
}

/// x 軸用資料點在(篩選後子集合)清單裡的索引(0..n-1),不是實際日期
/// 時間戳——用索引當 x 軸能讓折線均勻分布,不會因為訓練日之間有空檔(或
/// 篩選跳過了沒練到的日子)在圖上出現長段空白。
List<FlSpot> buildVolumeSpots(List<VolumeDataPoint> dataPoints, MuscleGroupFilter filter) {
  final points = chartPointsForFilter(dataPoints, filter);
  return [
    for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), volumeForFilter(points[i], filter)),
  ];
}

/// x 軸日期短標籤(對照 iOS `ChartTimeRange.dateFormat`:週/月/3月用
/// `MM/dd`,年用 `yyyy/MM`)。
String formatChartAxisDate(DateTime date, ChartTimeRange range) {
  if (range == ChartTimeRange.year) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}';
  }
  return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
}
