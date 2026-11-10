import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 空狀態畫面:圖示 + 標題 + 說明 + 可選主按鈕,置中顯示。
///
/// 提供 [actionLabel] 與 [onAction] 時顯示一顆 `FilledButton`。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  /// 上方大圖示。
  final IconData icon;

  /// 標題。
  final String title;

  /// 說明文字(可選)。
  final String? message;

  /// 主按鈕文字;需與 [onAction] 同時提供才會顯示按鈕。
  final String? actionLabel;

  /// 主按鈕回呼。
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colors.onSurfaceVariant),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
