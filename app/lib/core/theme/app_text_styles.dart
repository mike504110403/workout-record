import 'package:flutter/material.dart';

/// 數字專用文字樣式 helper:一律啟用 tabular figures(等寬數字),
/// 讓計時器、重量、次數在數值變動時不會左右抖動。
///
/// 用法:`AppNumberStyles.large(context)`,或對任意樣式
/// `style.tabular`。
class AppNumberStyles {
  const AppNumberStyles._();

  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  /// 特大數字(例如休息計時、主要指標)。
  static TextStyle display(BuildContext context) => Theme.of(
    context,
  ).textTheme.displaySmall!.tabular.copyWith(fontWeight: FontWeight.w700);

  /// 大數字(MetricTile 預設)。
  static TextStyle large(BuildContext context) => Theme.of(
    context,
  ).textTheme.headlineMedium!.tabular.copyWith(fontWeight: FontWeight.w700);

  /// 中數字(列表中的重量 × 次數)。
  static TextStyle medium(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleLarge!.tabular.copyWith(fontWeight: FontWeight.w600);

  /// 內文大小的數字(表格、紀錄列)。
  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.tabular;
}

/// 為 [TextStyle] 加上 tabular figures。
extension TabularTextStyle on TextStyle {
  TextStyle get tabular =>
      copyWith(fontFeatures: AppNumberStyles.tabularFigures);
}
