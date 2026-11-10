import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'metric_tile.dart';

/// 多個 [MetricTile] 等分一列(每個 `Expanded`),間距 [spacing]。
///
/// 通常包在 [AppCard] 內:
/// ```dart
/// AppCard(child: MetricRow(tiles: [
///   MetricTile(value: '4', label: '次數'),
///   MetricTile(value: '12.5', label: '總量', unit: 't'),
/// ]))
/// ```
class MetricRow extends StatelessWidget {
  const MetricRow({
    super.key,
    required this.tiles,
    this.spacing = AppSpacing.md,
  });

  /// 要等分的指標。
  final List<MetricTile> tiles;

  /// 相鄰指標的水平間距,預設 12。
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) children.add(SizedBox(width: spacing));
      children.add(Expanded(child: tiles[i]));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
