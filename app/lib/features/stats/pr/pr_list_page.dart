// PR 排行頁。對應 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/PR/PRView.swift`(不含肌群
// 篩選 chips——brief 範圍只要求「按肌群分組列出」,不含篩選互動)。
//
// 契約:zero-arg const `StatelessWidget`,自帶 Scaffold——大腦 merge 時,
// 工人 A 的 PR 入口直接 `Navigator.push`/`context.push` 到
// `const PrListPage()`,不需要外層再包 Scaffold/AppBar。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  const SizedBox(height: 12),
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

class _PrListBody extends ConsumerWidget {
  const _PrListBody({required this.summaries});

  final List<PRSummary> summaries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (summaries.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(prListControllerProvider.notifier).refresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: const _EmptyPrListState(),
          ),
        ),
      );
    }

    final sections = groupByMuscleGroup(summaries);

    return RefreshIndicator(
      key: const Key('prListRefreshIndicator'),
      onRefresh: () => ref.read(prListControllerProvider.notifier).refresh(),
      child: ListView(
        // 段數固定(依實際肌群數量而定,不是無限增長的資料流),刻意不用
        // ListView.builder 的 lazy 虛擬化——理由同
        // dashboard_page.dart/powerlifting_tab.dart:widget test 用
        // find.byKey 需要所有卡片都已建置進 Element tree。
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (final section in sections) _PrGroupSectionView(section: section),
        ],
      ),
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
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: Text(
            section.label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        for (final summary in section.summaries) PrSummaryCard(summary: summary),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _EmptyPrListState extends StatelessWidget {
  const _EmptyPrListState();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('prListEmptyState'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined, size: 60, color: Colors.orange),
            const SizedBox(height: 16),
            Text('尚無 PR 記錄', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '完成訓練後這裡會顯示你的個人最佳記錄',
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
