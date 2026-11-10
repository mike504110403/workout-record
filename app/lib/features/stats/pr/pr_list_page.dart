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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setQuery(String value) => setState(() => _query = value);

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

    final filtered = filterSummariesByName(summaries, _query);
    final sections = groupByMuscleGroup(filtered);

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
                : ListView(
                    // 段數固定(依實際肌群數量而定,不是無限增長的資料流),刻意不用
                    // ListView.builder 的 lazy 虛擬化——理由同
                    // dashboard_page.dart/powerlifting_tab.dart:widget test 用
                    // find.byKey 需要所有卡片都已建置進 Element tree。
                    padding: AppSpacing.pagePadding.copyWith(bottom: AppSpacing.xl),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [for (final section in sections) _PrGroupSectionView(section: section)],
                  ),
          ),
        ),
      ],
    );
  }
}

class _PrGroupSectionView extends StatelessWidget {
  const _PrGroupSectionView({required this.section});

  final PrGroupSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('prGroupSection-${section.label}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.label),
        for (final summary in section.summaries) PrSummaryCard(summary: summary),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
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
