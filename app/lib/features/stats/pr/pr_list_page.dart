// PR 排行頁。對應 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/PR/PRView.swift`(不含肌群
// 篩選 chips——brief 範圍只要求「按肌群分組列出」,不含篩選互動)。
// UI 優化波 2 另加「依動作名稱搜尋」(pr_grouping.dart `filterSummariesByName`)。
//
// 契約:zero-arg const `StatelessWidget`,自帶 Scaffold——大腦 merge 時,
// 工人 A 的 PR 入口直接 `Navigator.push`/`context.push` 到
// `const PrListPage()`,不需要外層再包 Scaffold/AppBar。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/personal_record.dart';
import 'pr_grouping.dart';
import 'pr_list_controller.dart';
import 'widgets/pr_summary_card.dart';

class PrListPage extends StatelessWidget {
  const PrListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('個人記錄')),
      body: Consumer(
        builder: (context, ref, _) {
          final async = ref.watch(prListControllerProvider);
          return async.when(
            data: (state) => _PrListBody(summaries: state.summaries),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('載入失敗，請稍後再試'),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    key: const Key('prListErrorRetryButton'),
                    onPressed: () => ref.invalidate(prListControllerProvider),
                    child: const Text('重試'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PrListBody extends ConsumerStatefulWidget {
  const _PrListBody({required this.summaries});

  final List<PRSummary> summaries;

  @override
  ConsumerState<_PrListBody> createState() => _PrListBodyState();
}

class _PrListBodyState extends ConsumerState<_PrListBody> {
  final _searchController = TextEditingController();
  String _query = '';

  // 篩選＋分組＋攤平的結果快取:只在查詢字串或來源資料變動時重算,不在每次
  // build(例如鍵盤彈出、重繪)重跑。
  late List<PRSummary> _filtered;
  late List<_PrListItem> _items;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(covariant _PrListBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.summaries, widget.summaries)) _recompute();
  }

  void _recompute() {
    _filtered = filterSummariesByName(widget.summaries, _query);
    _items = _flatten(groupByMuscleGroup(_filtered));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setQuery(String value) => setState(() {
    _query = value;
    _recompute();
  });

  @override
  Widget build(BuildContext context) {
    final summaries = widget.summaries;
    if (summaries.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(prListControllerProvider.notifier).refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: MediaQuery.of(context).size.height * 0.6, child: const _EmptyPrListState()),
        ),
      );
    }

    final filtered = _filtered;

    return Column(
      children: [
        Padding(
          padding: AppSpacing.pagePadding.copyWith(top: AppSpacing.sm, bottom: AppSpacing.sm),
          child: TextField(
            key: const Key('prListSearchField'),
            controller: _searchController,
            onChanged: _setQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜尋動作名稱',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('prListSearchClearButton'),
                      icon: const Icon(Icons.close),
                      tooltip: '清除',
                      onPressed: () {
                        _searchController.clear();
                        _setQuery('');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            key: const Key('prListRefreshIndicator'),
            onRefresh: () => ref.read(prListControllerProvider.notifier).refresh(),
            child: filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.4,
                        child: EmptyState(
                          key: const Key('prListNoMatchState'),
                          icon: Icons.search_off,
                          title: '找不到符合的動作',
                          message: '沒有名稱包含「${_query.trim()}」的 PR 記錄',
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    // 動作數量隨使用時間增長,卡片(含 Riverpod watch 與 1RM 計算)
                    // 改成懶建置,只建可見範圍;分組標題與卡片攤平成同一條清單。
                    // widget test 找下方的卡片要先 scrollUntilVisible。
                    padding: AppSpacing.pagePadding.copyWith(bottom: AppSpacing.xl),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _items.length,
                    itemBuilder: (context, index) => _items[index].build(context),
                  ),
          ),
        ),
      ],
    );
  }
}

/// 攤平後清單的一列:分組標題或單張 PR 卡。
sealed class _PrListItem {
  const _PrListItem();

  Widget build(BuildContext context);
}

class _PrHeaderItem extends _PrListItem {
  const _PrHeaderItem({required this.label, required this.isFirst});

  final String label;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    // 區段之間 lg(16):上一張卡片自帶 bottom margin md(12),非首段標題的上緣
    // 只補 xs(4)就是 16;首段維持 SectionHeader 預設 sm 上緣。標題與下方
    // 卡片的距離維持 sm(8)。(先前非首段再多補 sm,實際間距 12+8+8=28。)
    return SectionHeader(
      key: Key('prGroupSection-$label'),
      title: label,
      padding: EdgeInsets.only(top: isFirst ? AppSpacing.sm : AppSpacing.xs, bottom: AppSpacing.sm),
    );
  }
}

class _PrCardItem extends _PrListItem {
  const _PrCardItem(this.summary);

  final PRSummary summary;

  @override
  Widget build(BuildContext context) => PrSummaryCard(summary: summary);
}

List<_PrListItem> _flatten(List<PrGroupSection> sections) {
  return [
    for (final (i, section) in sections.indexed) ...[
      _PrHeaderItem(label: section.label, isFirst: i == 0),
      for (final summary in section.summaries) _PrCardItem(summary),
    ],
  ];
}

class _EmptyPrListState extends StatelessWidget {
  const _EmptyPrListState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      key: Key('prListEmptyState'),
      icon: Icons.emoji_events_outlined,
      title: '尚無 PR 記錄',
      message: '完成訓練後這裡會顯示你的個人最佳記錄',
    );
  }
}
