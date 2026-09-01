// 歷史 tab 殼:列表／日曆雙檢視 toggle(對照 iOS `HistoryView` 的
// `ViewMode` Picker)。router.dart 的 `/history` route 直接掛這個
// zero-arg widget,掛法不變。
import 'package:flutter/material.dart';

import 'history_calendar_view.dart';
import 'history_list_view.dart';

enum HistoryViewMode { list, calendar }

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  HistoryViewMode _viewMode = HistoryViewMode.list;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('歷史')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<HistoryViewMode>(
              key: const Key('historyViewModeSegmentedControl'),
              segments: const [
                ButtonSegment(
                  value: HistoryViewMode.list,
                  label: Text('列表', key: Key('historyViewModeSegment-list')),
                  icon: Icon(Icons.list),
                ),
                ButtonSegment(
                  value: HistoryViewMode.calendar,
                  label: Text('日曆', key: Key('historyViewModeSegment-calendar')),
                  icon: Icon(Icons.calendar_month),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (values) => setState(() => _viewMode = values.first),
            ),
          ),
          Expanded(
            child: switch (_viewMode) {
              HistoryViewMode.list => const HistoryListView(),
              HistoryViewMode.calendar => const HistoryCalendarView(),
            },
          ),
        ],
      ),
    );
  }
}
