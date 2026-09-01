// 歷史列表/日曆共用的空狀態(對照 iOS `EmptyHistoryView`)。
import 'package:flutter/material.dart';

class HistoryEmptyState extends StatelessWidget {
  const HistoryEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('historyEmptyState'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            Text('尚無訓練記錄', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '完成你的第一次訓練吧！',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
