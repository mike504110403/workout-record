import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';

/// 指標方塊:大數字 + 小標籤,可選單位與趨勢。數字使用 tabular figures。
///
/// 不含卡片外框(要卡片請包 [AppCard]),方便放進 [MetricRow] 或其他容器。
///
/// ```dart
/// MetricTile(value: '12,500', label: '本週總量', unit: 'kg', trend: '+8%')
/// ```
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.trend,
    this.trendColor,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  /// 主要數字(已格式化的字串)。
  final String value;

  /// 小標籤,顯示在數字下方。
  final String label;

  /// 單位(可選),以較小字級接在數字後。
  final String? unit;

  /// 趨勢文字(可選),例如 `+8%`;顯示在標籤下方。
  final String? trend;

  /// 趨勢文字顏色;預設 onSurfaceVariant。
  final Color? trendColor;

  /// 內容對齊方式,預設靠左。
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: value, style: AppNumberStyles.large(context)),
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (trend != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            trend!,
            style: AppNumberStyles.body(context).copyWith(
              fontSize: theme.textTheme.labelMedium?.fontSize,
              fontWeight: FontWeight.w600,
              color: trendColor ?? colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
