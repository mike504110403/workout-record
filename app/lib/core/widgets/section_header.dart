import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 區塊標題列:左側標題,右側可選的動作([trailing],例如「查看全部」按鈕)。
///
/// 預設不含水平留白(交給頁面的 [AppSpacing.pageHorizontal]);
/// 需要時可傳入 [padding]。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(vertical: AppSpacing.sm),
  });

  /// 標題文字。
  final String title;

  /// 右側動作(可選)。
  final Widget? trailing;

  /// 外距,預設上下 8。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}
