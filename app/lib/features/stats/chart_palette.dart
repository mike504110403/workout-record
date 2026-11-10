// Stats tab 共用的肌群篩選選項與配色。對照 iOS
// `ios/.../Sources/Models/ChartModels.swift` 的 `MuscleGroupFilter`。刻意獨立
// 成檔案(而非塞進某個子頁),因為三個子頁(體重/訓練統計/三項)未來都可能需要
// 一致的肌群配色語彙。
//
// UI 優化波 2:配色改走設計系統——原本照 iOS 搬的寫死 `Colors.*`(其中
// `back` 與 `all` 同為純藍是 iOS 的巧合)換成 `AppSemanticColors` 的肌群色
// (淺/深主題各一套);「總容量」(all)用主題主色。
import 'package:flutter/material.dart';

import '../../core/theme/app_semantic_colors.dart';
import '../../data/models/exercise.dart';

/// 肌群篩選 chip 的可選項。`all` 代表「總容量」(不篩選特定肌群)。
enum MuscleGroupFilter {
  all('總容量'),
  chest('胸部'),
  back('背部'),
  legs('腿部'),
  shoulders('肩部'),
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

/// 肌群篩選對應的圖表/標記顏色(隨淺/深主題變化)。
///
/// 總容量(`all`)= 主題主色;其餘六個肌群 = [AppSemanticColors] 的肌群色。
Color chartColorFor(BuildContext context, MuscleGroupFilter filter) {
  final semantic = context.semanticColors;
  return switch (filter) {
    MuscleGroupFilter.all => Theme.of(context).colorScheme.primary,
    MuscleGroupFilter.chest => semantic.muscleChest,
    MuscleGroupFilter.back => semantic.muscleBack,
    MuscleGroupFilter.legs => semantic.muscleLegs,
    MuscleGroupFilter.shoulders => semantic.muscleShoulders,
    MuscleGroupFilter.arms => semantic.muscleArms,
    MuscleGroupFilter.core => semantic.muscleCore,
  };
}
