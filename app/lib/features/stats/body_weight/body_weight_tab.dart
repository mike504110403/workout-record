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

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/body_weight.dart';
import '../trend_need_more_data.dart';
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
          loading: () =>
              const Center(key: Key('bodyWeightLoadingIndicator'), child: CircularProgressIndicator()),
          error: (error, stackTrace) => _BodyWeightError(
            // `ref.invalidate` 而不是 `.refresh()`——對齊 dashboard_page.dart
            // `dashboardErrorRetryButton` 的既有慣例：invalidate 讓 provider
            // 整個重跑一次 build()/_load()，`.refresh()` 是 controller 自己
            // 對外開放的「資料已存在、只是想重新查一次」方法，語意上不是給
            // 「目前卡在 AsyncError、根本沒有舊資料可以保留」的這個分支用的。
            onRetry: () => ref.invalidate(bodyWeightTabControllerProvider),
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
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('載入失敗，請稍後再試'),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
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

class _BodyWeightContent extends ConsumerStatefulWidget {
  const _BodyWeightContent({required this.state});

  final BodyWeightTabState state;

  @override
  ConsumerState<_BodyWeightContent> createState() => _BodyWeightContentState();
}

class _BodyWeightContentState extends ConsumerState<_BodyWeightContent> {
  // 統計彙總(平均/最高/最低/變化…)只在 state 換新時重算,不在每次 build
  // 重跑。BodyWeightTabState 每次載入都是新物件,以 identity 當快取鍵。
  BodyWeightTabState? _summarySource;
  BodyWeightSummary? _summary;

  BodyWeightSummary _summaryFor(BodyWeightTabState state) {
    if (!identical(_summarySource, state)) {
      _summarySource = state;
      _summary = computeBodyWeightSummary(state.entriesDesc, targetWeight: state.targetWeight);
    }
    return _summary!;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.entriesDesc.isEmpty) {
      return EmptyBodyWeightView(onAdd: () => _openAddForm(context));
    }

    final summary = _summaryFor(state);

    // CustomScrollView + Sliver:歷史記錄會隨使用時間無限增長,清單改成
    // SliverList.builder 懶建置(只建可見範圍),圖表與統計卡是固定的前段
    // sliver。widget test 找下方的列要先 scrollUntilVisible。
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: AppSpacing.pagePadding.copyWith(top: AppSpacing.sm),
          sliver: SliverList.list(
            children: [
              // 「新增」入口收進趨勢卡標題列的一顆小圖示鈕,不再獨佔一整列。
              // 趨勢圖至少 2 筆才畫:單點畫不出趨勢,改顯示空狀態(統計與列表照常顯示)。
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: '體重趨勢',
                      padding: EdgeInsets.zero,
                      trailing: IconButton.filledTonal(
                        key: const Key('addBodyWeightButton'),
                        onPressed: () => _openAddForm(context),
                        icon: const Icon(Icons.add),
                        tooltip: '新增體重',
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    if (state.entriesDesc.length >= kMinTrendPoints)
                      BodyWeightChart(entriesDesc: state.entriesDesc, targetWeight: state.targetWeight)
                    else
                      const SizedBox(
                        height: 200,
                        child: TrendNeedMoreData(key: Key('bodyWeightChartNeedMoreData')),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              BodyWeightStatsGrid(summary: summary),
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: '歷史記錄'),
            ],
          ),
        ),
        BodyWeightRecordList(
          entriesDesc: state.entriesDesc,
          onEdit: (entry) => _openEditForm(context, entry),
          onDelete: (entry) => _deleteEntry(context, ref, entry),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }

  void _openAddForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => const BodyWeightFormSheet(),
    );
  }

  void _openEditForm(BuildContext context, BodyWeight entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刪除失敗，請稍後再試')));
    }
  }
}
