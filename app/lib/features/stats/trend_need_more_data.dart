// 趨勢圖的「資料不足」空狀態。折線圖只有 0~1 個資料點時畫不出趨勢(孤點
// 反而誤導),改顯示這個空狀態——訓練容量、體重、三項 1RM 三種趨勢圖共用。
import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

/// 趨勢圖至少要幾個資料點才畫圖。
const int kMinTrendPoints = 2;

/// 資料點不足 [kMinTrendPoints] 時取代圖表的空狀態。
///
/// 預設標題「再記錄一筆就能看到趨勢」;[message] 補充說明目前的資料量。
class TrendNeedMoreData extends StatelessWidget {
  const TrendNeedMoreData({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return EmptyState(icon: Icons.show_chart, title: '再記錄一筆就能看到趨勢', message: message ?? '目前只有 1 筆資料');
  }
}
