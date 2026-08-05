// Stats tab 共用的固定配色。對照 iOS
// `ios/.../Sources/Models/ChartModels.swift` 的 `MuscleGroupFilter.color`
// (字串 -> `VolumeChartView.getColor(for:)` 轉成 SwiftUI Color)。刻意獨立
// 成檔案(而非塞進某個子頁),因為三個子頁(體重/訓練統計/三項)未來都可能需要
// 一致的肌群配色語彙。
//
// 顏色照 iOS 原樣搬移,包含其看似巧合的重疊:`back`(背部)跟 `all`(總容量)
// 都是純藍——這不是這裡的筆誤,是 iOS 原始定義本來就這樣(見
// ChartModels.swift:70-80),為了「對齊 iOS」原樣保留,不自作主張改掉。
import 'package:flutter/material.dart';

import '../../data/models/exercise.dart';

/// 肌群篩選 chip 的可選項。`all` 代表「總容量」(不篩選特定肌群)。
enum MuscleGroupFilter {
  all('總容量'),
  chest('胸'),
  back('背'),
  legs('腿'),
  shoulders('肩'),
  arms('手臂'),
  core('核心');

  const MuscleGroupFilter(this.label);

  final String label;

  /// 對應的 domain 肌群值,`all` 沒有對應值(回傳 null)。
  PrimaryMuscleGroup? get primaryMuscleGroup => switch (this) {
        MuscleGroupFilter.all => null,
        MuscleGroupFilter.chest => PrimaryMuscleGroup.chest,
        MuscleGroupFilter.back => PrimaryMuscleGroup.back,
        MuscleGroupFilter.legs => PrimaryMuscleGroup.legs,
        MuscleGroupFilter.shoulders => PrimaryMuscleGroup.shoulders,
        MuscleGroupFilter.arms => PrimaryMuscleGroup.arms,
        MuscleGroupFilter.core => PrimaryMuscleGroup.core,
      };
}

/// 固定配色表,照 iOS `MuscleGroupFilter.color`:
/// 總容量/背部 = 藍、胸 = 紅、腿 = 綠、肩 = 橙、手臂 = 紫、核心 = 黃。
const Map<MuscleGroupFilter, Color> chartPalette = {
  MuscleGroupFilter.all: Colors.blue,
  MuscleGroupFilter.chest: Colors.red,
  MuscleGroupFilter.back: Colors.blue,
  MuscleGroupFilter.legs: Colors.green,
  MuscleGroupFilter.shoulders: Colors.orange,
  MuscleGroupFilter.arms: Colors.purple,
  MuscleGroupFilter.core: Color(0xFFFBC02D),
};
