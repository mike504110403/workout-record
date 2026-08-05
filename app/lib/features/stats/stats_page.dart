// 數據 tab 殼:三段 segmented control(體重/訓練統計/三項)。對應 iOS
// `Views/Stats/StatsView.swift`。
//
// 與 iOS 差異申報:iOS `StatsView` 的 `selectedTab` 預設是 0(體重)。這裡
// 依 brief 明確指示改成預設停在「訓練統計」(index 1)——Dashboard「查看
// 進度」快速操作 `context.go('/stats')` 進來就是這個子頁,不需要使用者
// 再手動切一次分頁。brief 原文把這個決定描述成「對齊 iOS」,但實際讀過
// iOS 原始碼後(`StatsView.swift:4`)預設值其實是體重(0),不是訓練統計
// (1)——這裡照 brief 的明確指示(訓練統計為預設)執行,並在此註記發現的
// 落差,不是我方自行取捨。
import 'package:flutter/material.dart';

import 'placeholders/body_weight_tab.dart';
import 'placeholders/powerlifting_tab.dart';
import 'workout_stats/workout_stats_tab.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  static const _tabLabels = ['體重', '訓練統計', '三項'];

  /// 預設停在「訓練統計」(index 1),見檔頭「與 iOS 差異申報」註記。
  int _selectedIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('數據')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<int>(
              key: const Key('statsSegmentedControl'),
              segments: [
                for (var i = 0; i < _tabLabels.length; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(_tabLabels[i], key: Key('statsSegment-$i')),
                  ),
              ],
              selected: {_selectedIndex},
              onSelectionChanged: (values) => setState(() => _selectedIndex = values.first),
            ),
          ),
          // IndexedStack(而非直接依 index 切換 build 出來的單一 widget)讓
          // 三個子頁的內部狀態(尤其是訓練統計子頁背後 controller/provider
          // 的資料)在使用者切分頁時保留,不會每次切回去都重新查詢——對照
          // dashboard 分頁用 StatefulShellRoute.indexedStack 保留分頁狀態
          // 的精神,只是這裡是頁內三段,不是 router 分頁。
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                BodyWeightTab(),
                WorkoutStatsTab(),
                PowerliftingTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
