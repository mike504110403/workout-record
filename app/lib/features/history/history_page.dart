// 歷史 tab 殼:列表／日曆雙檢視(對照 iOS `HistoryView` 的 `ViewMode`
// Picker)。router.dart 的 `/history` route 直接掛這個 zero-arg widget,
// 掛法不變。
//
// 不放「歷史」標題(底部導覽已標示所在分頁),頂端只留一條精簡頂列,右側
// 一個切換 icon(列表↔日曆),內容直接上移。日曆模式下切換 icon 併進月份列。
import 'package:flutter/material.dart';

import 'history_calendar_view.dart';
import 'history_list_view.dart';
import '../../core/theme/app_tokens.dart';

enum HistoryViewMode { list, calendar }

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  HistoryViewMode _viewMode = HistoryViewMode.list;

  void _toggleViewMode() => setState(() {
    _viewMode = _viewMode == HistoryViewMode.list ? HistoryViewMode.calendar : HistoryViewMode.list;
  });

  /// 兩個檢視共用同一個切換鈕(key 不變):列表模式放在頂列,日曆模式併進
  /// 月份列右側——同一時間只會有一個實例。
  Widget _buildToggle() {
    final isList = _viewMode == HistoryViewMode.list;
    return IconButton(
      key: const Key('historyViewModeToggleButton'),
      // icon 與 tooltip 都表示「按下去會去哪」,而非目前所在。
      icon: Icon(isList ? Icons.calendar_month : Icons.view_list),
      tooltip: isList ? '切換為日曆' : '切換為列表',
      visualDensity: VisualDensity.compact,
      onPressed: _toggleViewMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 沒有 AppBar,自己留狀態列安全區;底部由外層殼的導覽列處理。
      body: SafeArea(
        bottom: false,
        child: switch (_viewMode) {
          HistoryViewMode.list => Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Align(alignment: Alignment.centerRight, child: _buildToggle()),
              ),
              const Expanded(child: HistoryListView()),
            ],
          ),
          // 日曆模式不另佔一列:切換鈕交給日曆檢視放進月份列(載入中/錯誤時
          // 由它自己補一條精簡頂列,確保任何狀態都切得回列表)。
          HistoryViewMode.calendar => HistoryCalendarView(modeToggle: _buildToggle()),
        },
      ),
    );
  }
}
