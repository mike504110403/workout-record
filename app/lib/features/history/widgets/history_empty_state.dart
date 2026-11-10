// 歷史列表/日曆共用的空狀態(對照 iOS `EmptyHistoryView`)。
import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';

class HistoryEmptyState extends StatelessWidget {
  const HistoryEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      key: Key('historyEmptyState'),
      icon: Icons.history,
      title: '尚無訓練記錄',
      message: '完成你的第一次訓練吧！',
    );
  }
}
