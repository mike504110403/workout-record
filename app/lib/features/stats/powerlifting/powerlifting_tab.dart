// Stats tab 的「經典三項」子頁。對應 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Views/Powerlifting/PowerliftingView.swift`。
//
// 契約:zero-arg const `StatelessWidget`,自足自帶 provider——外層是
// `StatelessWidget`(供大腦 merge 時用 `const PowerliftingTab()` 直接嵌入
// stats_page.dart 的分頁內容),內部用 `Consumer` 讀取
// `powerliftingControllerProvider`,不需要呼叫端額外包 ProviderScope 或傳
// 任何參數進來。
//
// 這個子頁被嵌入外層 Stats 分頁殼(TabBarView)裡,沒有自己的 AppBar——
// 「右上角 +」(對照 iOS `.toolbar { ... Image(systemName: "plus") }`)這裡
// 改成子頁內容最上方、靠右對齊的圖示按鈕,視覺上仍是這塊子頁內容的右上角,
// 不額外疊一層 AppBar 造成雙層工具列。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'powerlifting_controller.dart';
import 'widgets/add_power_lift_record_sheet.dart';
import 'widgets/lift_picker.dart';
import 'widgets/manual_records_section.dart';
import 'widgets/system_estimate_section.dart';
import 'widgets/total_lift_card.dart';

class PowerliftingTab extends StatelessWidget {
  const PowerliftingTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final async = ref.watch(powerliftingControllerProvider);
        return async.when(
          data: (state) => _PowerliftingContent(state: state),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('載入失敗，請稍後再試'),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('powerliftingErrorRetryButton'),
                  onPressed: () => ref.invalidate(powerliftingControllerProvider),
                  child: const Text('重試'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PowerliftingContent extends ConsumerWidget {
  const _PowerliftingContent({required this.state});

  final PowerliftingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(powerliftingControllerProvider.notifier);

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: SingleChildScrollView(
        // 內容固定幾個區塊、不會無限增長,理由同
        // dashboard_page.dart:虛擬化的 ListView 會讓捲動範圍外的區塊不進
        // Element tree,widget test 用 find.byKey 會找不到。
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('經典三項', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  key: const Key('addPowerLiftRecordButton'),
                  icon: const Icon(Icons.add),
                  onPressed: () => _showAddSheet(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TotalLiftCard(totalLifts: state.totalLiftsValue, bestByLift: state.bestByLift),
            const SizedBox(height: 16),
            Center(
              child: LiftPicker(selected: state.selectedLift, onSelected: notifier.selectLift),
            ),
            const SizedBox(height: 16),
            ManualRecordsSection(
              records: state.currentManualRecords,
              chartRecords: state.chartData,
              currentPR: state.currentManualPR,
              onDelete: notifier.deleteManualRecord,
            ),
            const SizedBox(height: 16),
            SystemEstimateSection(
              summaries: state.currentSystemSummaries,
              best: state.currentSystemPR,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const AddPowerLiftRecordSheet(),
    );
  }
}
