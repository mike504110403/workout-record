// 容量趨勢圖區塊:時間範圍 picker + fl_chart LineChart(面積填色)+ 肌群
// 篩選 chips + 統計摘要。對應 iOS `Views/Charts/VolumeChartView.swift`。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../chart_palette.dart';
import 'chart_time_range.dart';
import 'volume_aggregation.dart';
import 'volume_chart_spots.dart';
import 'workout_stats_format.dart';

class VolumeChartSection extends StatelessWidget {
  const VolumeChartSection({
    super.key,
    required this.timeRange,
    required this.muscleGroupFilter,
    required this.dataPoints,
    required this.stats,
    required this.onTimeRangeChanged,
    required this.onMuscleGroupFilterChanged,
  });

  final ChartTimeRange timeRange;
  final MuscleGroupFilter muscleGroupFilter;
  final List<VolumeDataPoint> dataPoints;
  final VolumeStats stats;
  final ValueChanged<ChartTimeRange> onTimeRangeChanged;
  final ValueChanged<MuscleGroupFilter> onMuscleGroupFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('訓練容量趨勢', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _TimeRangePicker(selected: timeRange, onChanged: onTimeRangeChanged),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: dataPoints.isEmpty
                  ? const _EmptyChart()
                  : _VolumeLineChart(
                      dataPoints: dataPoints,
                      filter: muscleGroupFilter,
                      timeRange: timeRange,
                    ),
            ),
            const SizedBox(height: 16),
            _MuscleGroupChips(selected: muscleGroupFilter, onChanged: onMuscleGroupFilterChanged),
            const SizedBox(height: 16),
            _StatsRow(stats: stats),
          ],
        ),
      ),
    );
  }
}

class _TimeRangePicker extends StatelessWidget {
  const _TimeRangePicker({required this.selected, required this.onChanged});

  final ChartTimeRange selected;
  final ValueChanged<ChartTimeRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ChartTimeRange>(
      key: const Key('chartTimeRangePicker'),
      segments: [
        for (final range in ChartTimeRange.values)
          ButtonSegment(
            value: range,
            label: Text(range.label, key: Key('chartTimeRange-${range.name}')),
          ),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      key: const Key('volumeChartEmptyState'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.show_chart, size: 48, color: mutedColor),
          const SizedBox(height: 12),
          const Text('尚無訓練數據', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '完成訓練後這裡會顯示容量趨勢',
            style: TextStyle(fontSize: 12, color: mutedColor),
          ),
        ],
      ),
    );
  }
}

class _VolumeLineChart extends StatelessWidget {
  const _VolumeLineChart({
    required this.dataPoints,
    required this.filter,
    required this.timeRange,
  });

  final List<VolumeDataPoint> dataPoints;
  final MuscleGroupFilter filter;
  final ChartTimeRange timeRange;

  @override
  Widget build(BuildContext context) {
    final color = chartPalette[filter] ?? Colors.blue;
    // 軸標籤用的日期清單必須跟 spots 用同一套篩選規則(見
    // `chartPointsForFilter` 的文件註解)——肌群篩選模式下沒練到的日子會被
    // 整個跳過,spots 的索引因此是篩選後子集合的連續索引,不是原始
    // [dataPoints] 的索引,這裡的 `points` 必須對得上,不能直接用
    // [dataPoints]。
    final points = chartPointsForFilter(dataPoints, filter);
    final spots = buildVolumeSpots(dataPoints, filter);
    return LineChart(
      LineChartData(
        minY: 0,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => Text(
                value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toStringAsFixed(0),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (points.length / 5).clamp(1, points.isEmpty ? 1 : points.length).ceilToDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    formatChartAxisDate(points[index].date, timeRange),
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        // spots 為空時(篩選的肌群在目前範圍內完全沒有任何一天有記錄,但
        // [dataPoints] 整體不是空的——外層 `dataPoints.isEmpty` 檢查放行到
        // 這裡)不建立 [LineChartBarData]:對齊 iOS 同一種情境下只是畫出空
        // 座標軸、沒有任何 mark 的行為,同時避開空 spots 清單餵給
        // fl_chart 內部 `mostLeftSpot` 等 late 欄位可能未初始化的風險。
        lineBarsData: spots.isEmpty
            ? const []
            : [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  barWidth: 2,
                  color: color,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.1)),
                ),
              ],
      ),
    );
  }
}

class _MuscleGroupChips extends StatelessWidget {
  const _MuscleGroupChips({required this.selected, required this.onChanged});

  final MuscleGroupFilter selected;
  final ValueChanged<MuscleGroupFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in MuscleGroupFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                key: Key('muscleGroupChip-${filter.name}'),
                label: Text(filter.label),
                selected: selected == filter,
                selectedColor: (chartPalette[filter] ?? Colors.blue).withValues(alpha: 0.2),
                checkmarkColor: chartPalette[filter],
                onSelected: (_) => onChanged(filter),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final VolumeStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatItem(
            key: const Key('volumeStatAverage'),
            icon: Icons.bar_chart,
            color: Colors.blue,
            title: '平均容量',
            value: formatVolumeKg(stats.average),
          ),
        ),
        const VerticalDivider(),
        Expanded(
          child: _StatItem(
            key: const Key('volumeStatHighest'),
            icon: Icons.arrow_upward,
            color: Colors.green,
            title: '最高容量',
            value: formatVolumeKg(stats.highest),
          ),
        ),
        const VerticalDivider(),
        Expanded(
          child: _StatItem(
            key: const Key('volumeStatCount'),
            icon: Icons.grid_view,
            color: Colors.orange,
            title: '數據點',
            value: '${stats.dataPointCount}',
          ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(title, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
