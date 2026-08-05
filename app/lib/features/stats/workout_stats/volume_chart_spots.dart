// 把 [VolumeDataPoint] 轉成 fl_chart 的 [FlSpot] 清單。獨立成純函式(不吃
// BuildContext),讓 widget test 可以直接斷言「資料層」(spots 的數量/數值)
// ,不必逐像素驗證圖表——對照 brief 的驗收要求。
import 'package:fl_chart/fl_chart.dart';

import 'chart_time_range.dart';
import '../chart_palette.dart';
import 'volume_aggregation.dart';

/// x 軸用資料點在清單裡的索引(0..n-1),不是實際日期時間戳——[dataPoints]
/// 已經照日期升冪排序、且只包含「當天有訓練」的日子,用索引當 x 軸能讓折線
/// 均勻分布,不會因為訓練日之間有空檔而在圖上出現長段空白。
List<FlSpot> buildVolumeSpots(List<VolumeDataPoint> dataPoints, MuscleGroupFilter filter) {
  return [
    for (var i = 0; i < dataPoints.length; i++) FlSpot(i.toDouble(), volumeForFilter(dataPoints[i], filter)),
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
