// 容量趨勢圖區塊:肌群篩選(dropdown)+ 時間範圍 picker + fl_chart LineChart
// (面積填色)+ 統計摘要。對應 iOS `Views/Charts/VolumeChartView.swift`。
//
// UI 優化波 2:原本「肌群 chip 列 + 週期分段」兩層篩選並排,改成肌群收進標題列
// 右側的下拉選單(`MenuAnchor`),週期分段保留在圖表上方;資料點 < 2 時不畫
// 孤點,改顯示空狀態。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/metric_tile.dart';
import '../../../core/widgets/section_header.dart';
import '../../settings/preferences/weight_unit.dart';
import '../chart_axis_format.dart';
import '../chart_palette.dart';
import '../trend_need_more_data.dart';
import 'chart_time_range.dart';
import 'volume_aggregation.dart';
import 'volume_chart_spots.dart';
import 'workout_stats_format.dart';

class VolumeChartSection extends StatefulWidget {
  const VolumeChartSection({
    super.key,
    required this.timeRange,
    required this.muscleGroupFilter,
    required this.dataPoints,
    required this.stats,
    required this.onTimeRangeChanged,
    required this.onMuscleGroupFilterChanged,
    this.onOpenPr,
  });

  final ChartTimeRange timeRange;
  final MuscleGroupFilter muscleGroupFilter;
  final List<VolumeDataPoint> dataPoints;
  final VolumeStats stats;
  final ValueChanged<ChartTimeRange> onTimeRangeChanged;
  final ValueChanged<MuscleGroupFilter> onMuscleGroupFilterChanged;

  /// 標題列的「PR」入口(原本是獨立一張入口卡,改成標題列一顆鈕省一整塊高度)。
  /// null 時不顯示,方便不需要 PR 入口的場合單獨使用本區塊。
  final VoidCallback? onOpenPr;

  @override
  State<VolumeChartSection> createState() => _VolumeChartSectionState();
}

class _VolumeChartSectionState extends State<VolumeChartSection> {
  // 篩選後的資料點只在 (dataPoints, filter) 變動時重算:先前同一次 build
  // 會算三次(點數、軸標籤、spots),且每次 rebuild(換單位、切週期)都重跑。
  // 以 dataPoints 的 identity 當快取鍵——controller 每次重新查詢都會產生新 list。
  List<VolumeDataPoint>? _cachedSource;
  MuscleGroupFilter? _cachedFilter;
  List<VolumeDataPoint> _points = const [];

  List<VolumeDataPoint> _pointsFor(List<VolumeDataPoint> source, MuscleGroupFilter filter) {
    if (!identical(_cachedSource, source) || _cachedFilter != filter) {
      _cachedSource = source;
      _cachedFilter = filter;
      _points = chartPointsForFilter(source, filter);
    }
    return _points;
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.muscleGroupFilter;
    final dataPoints = widget.dataPoints;
    // 要畫的點數以「篩選後」為準(見 chartPointsForFilter):篩選特定肌群時,
    // 沒練到該肌群的日子不算資料點。
    final points = _pointsFor(dataPoints, filter);
    final chartPointCount = points.length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: '訓練容量趨勢',
            padding: EdgeInsets.zero,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MuscleGroupMenu(selected: filter, onChanged: widget.onMuscleGroupFilterChanged),
                if (widget.onOpenPr != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _PrEntryButton(onTap: widget.onOpenPr!),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _TimeRangePicker(selected: widget.timeRange, onChanged: widget.onTimeRangeChanged),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 220,
            child: switch (chartPointCount) {
              _ when dataPoints.isEmpty => const EmptyState(
                key: Key('volumeChartEmptyState'),
                icon: Icons.show_chart,
                title: '尚無訓練數據',
                message: '完成訓練後這裡會顯示容量趨勢',
              ),
              0 => EmptyState(
                key: const Key('volumeChartNoMuscleData'),
                icon: Icons.show_chart,
                title: '這段期間沒有${filter.label}的紀錄',
                message: '換個肌群或拉長時間範圍看看',
              ),
              < kMinTrendPoints => const TrendNeedMoreData(key: Key('volumeChartNeedMoreData')),
              _ => _VolumeLineChart(points: points, filter: filter, timeRange: widget.timeRange),
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          _StatsRow(stats: widget.stats),
        ],
      ),
    );
  }
}

/// 標題列的 PR 入口:帶獎盃圖示的精簡文字鈕(取代原本佔一整塊的入口卡)。
class _PrEntryButton extends StatelessWidget {
  const _PrEntryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const Key('prEntryButton'),
      onPressed: onTap,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      icon: Icon(Icons.emoji_events, size: 18, color: context.semanticColors.pr),
      label: const Text('PR'),
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

class _VolumeLineChart extends ConsumerStatefulWidget {
  const _VolumeLineChart({required this.points, required this.filter, required this.timeRange});

  /// 已依 [filter] 篩選過的資料點(軸標籤與 spots 共用同一份,索引才對得上
  /// ——見 `chartPointsForFilter` 的文件註解)。
  final List<VolumeDataPoint> points;
  final MuscleGroupFilter filter;
  final ChartTimeRange timeRange;

  @override
  ConsumerState<_VolumeLineChart> createState() => _VolumeLineChartState();
}

class _VolumeLineChartState extends ConsumerState<_VolumeLineChart> {
  // spots 依 (points, filter, unit) 快取,不在每次 build 重建。
  List<VolumeDataPoint>? _spotsSource;
  MuscleGroupFilter? _spotsFilter;
  WeightUnit? _spotsUnit;
  List<FlSpot> _spots = const [];

  List<FlSpot> _spotsFor(WeightUnit unit) {
    if (!identical(_spotsSource, widget.points) || _spotsFilter != widget.filter || _spotsUnit != unit) {
      _spotsSource = widget.points;
      _spotsFilter = widget.filter;
      _spotsUnit = unit;
      // buildVolumeSpotsFromPoints 回傳值恆 kg(資料層,不動——維持既有 widget test 對
      // 「資料層」的斷言基準);y 軸顯示值在這裡換算,資料本身不變。
      _spots = [
        for (final spot in buildVolumeSpotsFromPoints(widget.points, widget.filter))
          FlSpot(spot.x, kgToDisplay(spot.y, unit)),
      ];
    }
    return _spots;
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(weightUnitProvider);
    final filter = widget.filter;
    final points = widget.points;
    final timeRange = widget.timeRange;
    final color = chartColorFor(context, filter);
    final axisStyle = Theme.of(context).textTheme.labelSmall;
    final spots = _spotsFor(unit);
    // RepaintBoundary:圖表自成一層,外層卡片/清單捲動時不連帶重繪圖表。
    return RepaintBoundary(
      key: const Key('volumeChartRepaintBoundary'),
      child: LineChart(
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
                reservedSize: kYAxisReservedSize,
                getTitlesWidget: (value, meta) =>
                    yAxisTitle(value, meta, style: axisStyle, compactThousands: true),
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
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(formatChartAxisDate(points[index].date, timeRange), style: axisStyle),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
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
      ),
    );
  }
}

/// 肌群篩選下拉:標題列右側一顆帶色點的按鈕,點開列出七個選項。
class _MuscleGroupMenu extends StatelessWidget {
  const _MuscleGroupMenu({required this.selected, required this.onChanged});

  final MuscleGroupFilter selected;
  final ValueChanged<MuscleGroupFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final filter in MuscleGroupFilter.values)
          MenuItemButton(
            key: Key('muscleGroupMenuItem-${filter.name}'),
            leadingIcon: _ColorDot(color: chartColorFor(context, filter)),
            trailingIcon: filter == selected ? const Icon(Icons.check, size: 18) : null,
            onPressed: () => onChanged(filter),
            child: Text(filter.label),
          ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        key: const Key('muscleGroupFilterButton'),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: _ColorDot(color: chartColorFor(context, selected)),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selected.label, key: const Key('muscleGroupFilterLabel')),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 平均/最高/次數三格。每格外包 `FittedBox(scaleDown)`:容量數字可能到五位數,
/// 三等分的窄欄放不下時整格等比縮小,而不是被 ellipsis 截掉數字。
class _StatsRow extends ConsumerWidget {
  const _StatsRow({required this.stats});

  final VolumeStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    final unitLabel = unitSuffix(unit);
    final tiles = [
      MetricTile(
        key: const Key('volumeStatAverage'),
        value: formatVolumeBare(stats.average, unit),
        unit: unitLabel,
        label: '平均容量',
      ),
      MetricTile(
        key: const Key('volumeStatHighest'),
        value: formatVolumeBare(stats.highest, unit),
        unit: unitLabel,
        label: '最高容量',
      ),
      MetricTile(key: const Key('volumeStatCount'), value: '${stats.dataPointCount}', label: '訓練日'),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, tile) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: tile),
          ),
        ],
      ],
    );
  }
}
