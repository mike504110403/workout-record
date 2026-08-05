// 容量趨勢圖的時間範圍選項。對照 iOS
// `ios/.../Sources/Models/ChartModels.swift` 的 `ChartTimeRange`(週/月/3月/
// 年,天數與預設值原樣搬移)。
enum ChartTimeRange {
  week(7, '週'),
  month(30, '月'),
  threeMonths(90, '3月'),
  year(365, '年');

  const ChartTimeRange(this.days, this.label);

  final int days;
  final String label;
}

/// 預設時間範圍,對齊 iOS `VolumeChartViewModel.selectedTimeRange = .month`。
const kDefaultChartTimeRange = ChartTimeRange.month;
