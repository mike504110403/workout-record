// 空狀態。對照 iOS 版 `BodyWeightView.EmptyBodyWeightView`：圖示 + 「尚未
// 記錄體重」標題 + 說明文字 + 新增按鈕。
import 'package:flutter/material.dart';

class EmptyBodyWeightView extends StatelessWidget {
  const EmptyBodyWeightView({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('emptyBodyWeightView'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.monitor_weight_outlined, size: 60, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text('尚未記錄體重', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '開始記錄你的體重變化',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('emptyBodyWeightAddButton'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('記錄第一筆體重'),
            ),
          ],
        ),
      ),
    );
  }
}
