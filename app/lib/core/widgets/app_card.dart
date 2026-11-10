import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 統一卡片:套用主題的 filled 卡片樣式(surfaceContainer、圓角 16、無陰影)。
///
/// - [padding] 預設 16([AppSpacing.lg])。
/// - 提供 [onTap] 時整張卡片可點擊(帶 ink 回饋,並自動裁切圓角)。
///
/// ```dart
/// AppCard(onTap: openDetail, child: Text('深蹲'))
/// ```
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  /// 卡片內容。
  final Widget child;

  /// 點擊回呼;為 null 時卡片不可點擊。
  final VoidCallback? onTap;

  /// 內距,預設四邊 16。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Card(
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}
