// 數據 tab 殼:三段 segmented control(體重/訓練/三項,標籤文字對齊 iOS
// `StatsView.swift` 的 `Picker` tag 文字)。對應 iOS
// `Views/Stats/StatsView.swift`。
//
// 與 iOS 差異申報:iOS `StatsView` 的 `selectedTab` 預設是 0(體重)。這裡
// 依 brief 明確指示改成預設停在「訓練」(index 1)——Dashboard「查看
// 進度」快速操作 `context.go('/stats')` 進來就是這個子頁,不需要使用者
// 再手動切一次分頁。brief 原文把這個決定描述成「對齊 iOS」,但實際讀過
// iOS 原始碼後(`StatsView.swift:4`)預設值其實是體重(0),不是訓練
// (1)——這裡照 brief 的明確指示(訓練為預設)執行,並在此註記發現的
// 落差,不是我方自行取捨。
//
// WAVE4-MERGE 注意事項(給 merge 時的大腦看):
// 1. **router.dart 分頁失效點目前只掛了訓練統計子頁**——`_AppShellState`
//    (見 router.dart)切到「數據」分頁時只 invalidate
//    `workoutStatsControllerProvider`。等 B(體重)/C(三項)兩位工人的
//    provider 就位後,merge 這裡的 placeholder 換成真實作時,務必回頭在
//    router.dart 的 `_refreshForBranch` 補上那兩個 provider 的
//    invalidate(同一個「切分頁不 dispose、需要主動重新查詢」的理由——見
//    router.dart 檔頭那兩段長註解),不然體重/三項子頁會重演這波修的同一種
//    「切走記新資料、切回看到舊資料」問題。
// 2. **IndexedStack 三子頁是一次全部建置**(`children:` 是 eager list,不是
//    依 index 懶載入)——StatsPage 第一次掛載時,體重/訓練/三項三個子頁的
//    provider 會同時觸發各自的 `build()`,即使使用者當下只看得到其中一個
//    (被蓋住的兩個只是不 paint,不是不存在,見
//    `test/features/stats/stats_page_test.dart` 用
//    `find.byType(..., skipOffstage: false)` 驗證背景子頁仍活著的那條
//    測試)。這是「切分頁保留狀態、不用每次重新查詢」換來的代價——換成懶載入
//    (第一次被選中才建置)可以省掉這個「三個子頁的查詢一次全發」的成本,
//    但會讓使用者第一次切到未曾造訪的分頁時多一次讀取延遲。目前三個子頁
//    的查詢量都不大(單一使用者的本機 SQLite),先不處理;三個子頁都做完、
//    如果實測有感卡頓再考慮改懶載入。
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
  // 標籤文字對齊 iOS StatsView.swift:11-13 的 Picker tag 文字(體重/訓練/
  // 三項),不是「訓練統計」——那是這個子頁在文件/程式碼裡的功能描述,不是
  // 使用者看到的分頁標籤字。
  static const _tabLabels = ['體重', '訓練', '三項'];

  /// 預設停在「訓練」(index 1),見檔頭「與 iOS 差異申報」註記。
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
