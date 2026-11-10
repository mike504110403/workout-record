// workout 內部共用:一列等分的 [MetricTile],每格包 FittedBox。
//
// core 的 [MetricRow] 遇到長數字(5 位數容量、「1小時30分鐘」)會被
// MetricTile 內的 ellipsis 截斷;這裡讓每格在放不下時等比縮小。
// 之後若 core 的 MetricRow 支援縮放,可改回直接用它(見回報「共用元件提案」)。
import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/metric_tile.dart';

class FittedMetricRow extends StatelessWidget {
  const FittedMetricRow({
    super.key,
    required this.tiles,
    this.spacing = AppSpacing.md,
  });

  final List<MetricTile> tiles;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) children.add(SizedBox(width: spacing));
      children.add(
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(fit: BoxFit.scaleDown, child: tiles[i]),
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
