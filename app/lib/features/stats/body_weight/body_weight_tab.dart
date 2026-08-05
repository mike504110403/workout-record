// Stats tab 的「體重」子頁：趨勢圖 + 統計資訊 + 體重紀錄列表（新增/編輯/
// 刪除）。對照 iOS 版 `Views/BodyWeight/BodyWeightView.swift` +
// `Views/Charts/BodyWeightChartView.swift` +
// `ViewModels/BodyWeightViewModel.swift`。
//
// 這個 widget 自帶 provider 串接（見 body_weight_controller.dart 的
// `bodyWeightTabControllerProvider`），不依賴外部殼（stats_page.dart，工人
// A 範圍）傳參——殼只需要把 `BodyWeightTab()` 掛成子頁即可，讀寫資料的責任
// 完全封裝在這個 feature 目錄內。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/body_weight.dart';
import 'body_weight_controller.dart';
import 'body_weight_stats.dart';
import 'widgets/body_weight_chart.dart';
import 'widgets/body_weight_form_sheet.dart';
import 'widgets/body_weight_record_list.dart';
import 'widgets/body_weight_stats_grid.dart';
import 'widgets/empty_body_weight_view.dart';

class BodyWeightTab extends StatelessWidget {
  const BodyWeightTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final asyncState = ref.watch(bodyWeightTabControllerProvider);
        return asyncState.when(
          data: (state) => _BodyWeightContent(state: state),
          loading: () => const Center(
            key: Key('bodyWeightLoadingIndicator'),
            child: CircularProgressIndicator(),
          ),
          error: (error, stackTrace) => _BodyWeightError(
            onRetry: () => ref.read(bodyWeightTabControllerProvider.notifier).refresh(),
          ),
        );
      },
    );
  }
}

class _BodyWeightError extends StatelessWidget {
  const _BodyWeightError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('載入失敗，請稍後再試'),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('bodyWeightErrorRetryButton'),
              onPressed: onRetry,
              child: const Text('重試'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyWeightContent extends ConsumerWidget {
  const _BodyWeightContent({required this.state});

  final BodyWeightTabState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.entriesDesc.isEmpty) {
      return EmptyBodyWeightView(onAdd: () => _openAddForm(context));
    }

    final summary = computeBodyWeightSummary(state.entriesDesc, targetWeight: state.targetWeight);

    // 內容固定幾個區塊、不會無限增長（列表筆數雖會隨紀錄增加，但不是
    // 「數千筆」等級的量級），刻意用 SingleChildScrollView + Column 而不是
    // ListView/ListView.builder 的 lazy 虛擬化——同 dashboard_page.dart 開頭
    // 註解記錄過的理由：虛擬化會讓捲動範圍外的區塊不進 Element tree，
    // widget test 用 find.byKey 找不到還沒被建置的下方項目（這裡也吃過同一
    // 個虧：圖表+統計卡把列表往下推出視窗後，`find.byKey('bodyWeightRow-…')`
    // 直接找不到，不是位置問題而是根本沒建置）。
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('體重紀錄', style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                key: const Key('addBodyWeightButton'),
                icon: const Icon(Icons.add_circle_outline),
                tooltip: '新增紀錄',
                onPressed: () => _openAddForm(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BodyWeightChart(entriesDesc: state.entriesDesc, targetWeight: state.targetWeight),
          const SizedBox(height: 20),
          BodyWeightStatsGrid(summary: summary),
          const SizedBox(height: 20),
          BodyWeightRecordList(
            entriesDesc: state.entriesDesc,
            onEdit: (entry) => _openEditForm(context, entry),
            onDelete: (entry) => _deleteEntry(context, ref, entry),
          ),
        ],
      ),
    );
  }

  void _openAddForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const BodyWeightFormSheet(),
    );
  }

  void _openEditForm(BuildContext context, BodyWeight entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => BodyWeightFormSheet(original: entry),
    );
  }

  // 刪除失敗路徑（例如注入的 throwing repository）：不讓例外往外炸整個
  // widget tree，吃下來改秀 SnackBar——同 dashboard 側對「非同步失敗一律
  // 處理」的紀律。刪除本身沒有獨立的 loading 旗標可解除（不像表單有
  // `_isSaving`），這裡的「解除卡死」體現在:失敗不影響任何畫面狀態、
  // 使用者可以立刻再次嘗試（不像表單那樣需要解除 disable）。
  Future<void> _deleteEntry(BuildContext context, WidgetRef ref, BodyWeight entry) async {
    try {
      await ref.read(bodyWeightTabControllerProvider.notifier).deleteEntry(entry.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刪除失敗，請稍後再試')),
      );
    }
  }
}
