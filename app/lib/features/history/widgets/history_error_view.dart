// 列表/日曆共用的載入失敗畫面(對照 pr_list_page.dart 的 error 分支)。
import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';

class HistoryErrorView extends StatelessWidget {
  const HistoryErrorView({super.key, required this.retryButtonKey, required this.onRetry});

  final Key retryButtonKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('載入失敗，請稍後再試'),
          const SizedBox(height: AppSpacing.md),
          FilledButton(key: retryButtonKey, onPressed: onRetry, child: const Text('重試')),
        ],
      ),
    );
  }
}
