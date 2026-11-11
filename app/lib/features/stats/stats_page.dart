// 數據 tab 殼:三段 segmented control(訓練/體重/三項,標籤文字對齊 iOS
// `StatsView.swift` 的 `Picker` tag 文字)。對應 iOS
// `Views/Stats/StatsView.swift`。
//
// 與 iOS 差異申報:iOS `StatsView` 的順序是 體重/訓練/三項、預設 selectedTab = 0
// (體重)。Dashboard「查看進度」快速操作 `context.go('/stats')` 進來希望直接
// 看到訓練統計,先前的做法是保留 iOS 順序、把預設停在中間的「訓練」(index 1)
// ——預設值與第一個分段不一致,使用者會看到 segmented control 的選取落在中間。
// UI 優化波 2 改成「把訓練移到第一位、預設 index 0」:預設選取＝第一個分段,
// 同時 Dashboard 進來仍直接是訓練統計。
//
// 分頁失效:router.dart `_refreshForBranch` 切到「數據」分頁時已同時
// invalidate 訓練/體重/三項三個子頁的 provider(「切分頁不 dispose、需要
// 主動重新查詢」的理由見 router.dart 檔頭長註解)。
//
// IndexedStack 三子頁「第一次被選中才建置」(介面改版):原本 `children:` 是
// eager list,StatsPage 一掛載三個子頁的 provider 就同時觸發 `build()` 查詢,
// 即使使用者只看得到其中一個。現在未造訪過的子頁以 `SizedBox.shrink()` 占位,
// 選中過一次後才換成真子頁並一直保留(已建過的狀態不丟,切回來不用重新查詢);
// router.dart 對未建置 provider 的 `ref.invalidate` 是 no-op,不會誤觸發建置。
//
// 介面改版:拿掉「數據」AppBar 標題(底部導覽已標示所在分頁),三段分段鈕
// 直接頂在狀態列安全區下方。
import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'body_weight/body_weight_tab.dart';
import 'powerlifting/powerlifting_tab.dart';
import 'workout_stats/workout_stats_tab.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  // 標籤文字對齊 iOS StatsView.swift:11-13 的 Picker tag 文字(體重/訓練/
  // 三項),不是「訓練統計」——那是這個子頁在文件/程式碼裡的功能描述,不是
  // 使用者看到的分頁標籤字。順序見檔頭「與 iOS 差異申報」:訓練排第一。
  static const _tabLabels = ['訓練', '體重', '三項'];

  /// 預設選取第一個分段(訓練)。
  int _selectedIndex = 0;

  /// 已被選中過(因此已建置)的分段;預設只有第一個。
  final Set<int> _visited = {0};

  static const _tabs = <Widget>[WorkoutStatsTab(), BodyWeightTab(), PowerliftingTab()];

  void _select(int index) {
    setState(() {
      _selectedIndex = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 不放 AppBar:分頁名稱由底部導覽標示。SafeArea 只吃頂部(底部由外層
    // 殼的導覽列處理),狀態列安全區照留。
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: AppSpacing.pagePadding.copyWith(top: AppSpacing.sm, bottom: AppSpacing.sm),
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
                onSelectionChanged: (values) => _select(values.first),
              ),
            ),
            // IndexedStack(而非直接依 index 切換 build 出來的單一 widget)讓
            // 已建過的子頁內部狀態(尤其是 controller/provider 的資料)在使用者
            // 切分頁時保留,不會每次切回去都重新查詢。
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    _visited.contains(i) ? _tabs[i] : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
