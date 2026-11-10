// stats 折線圖共用的 Y 軸刻度格式化與標籤 widget。
//
// fl_chart 預設左軸會把刻度值以預設小數位輸出(例如 72.40000000000001 或
// "72.4\n0" 換行疊字),reservedSize 又只有 40~44,實機會被擠成兩行。這裡集中
// 兩件事:(1) 純函式 [formatYAxisLabel] 依刻度間隔決定「整數或 1 位小數」;
// (2) [yAxisTitle] 產出單行不換行的 SideTitleWidget,四張圖共用。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Y 軸左側標籤建議保留寬度(容納 "1000.5"、"-72.4" 這類最長約 6 字元)。
const double kYAxisReservedSize = 52;

/// 把 Y 軸刻度值 [value] 格式化成短字串。
///
/// - [interval] 是 fl_chart 實際套用的刻度間隔(`TitleMeta.appliedInterval`):
///   間隔為 >=1 的整數時刻度全是整數 → 輸出整數;否則(間隔 <1 或帶小數,如
///   0.5、2.5)輸出 1 位小數。這樣同一條軸上所有標籤小數位一致、不會「72.4/73」
///   混排。
/// - [compactThousands] 為 true 時,絕對值 >=1000 輸出 "1.5k"(容量圖用,
///   數值動輒上萬)。
/// - 浮點誤差(72.4000000001)由 toStringAsFixed 吃掉;-0 一律顯示成 0。
String formatYAxisLabel(double value, {required double interval, bool compactThousands = false}) {
  if (compactThousands && value.abs() >= 1000) {
    return '${_fixed(value / 1000, 1)}k';
  }
  final integerAxis = interval >= 1 && (interval - interval.roundToDouble()).abs() < 1e-9;
  return _fixed(value, integerAxis ? 0 : 1);
}

String _fixed(double v, int digits) {
  final s = v.toStringAsFixed(digits);
  // -0 / -0.0(例如 -0.04 取整後)不顯示負號。
  return RegExp(r'^-0(\.0+)?$').hasMatch(s) ? s.substring(1) : s;
}

/// 左軸 `getTitlesWidget` 用的單行標籤:不換行、不省略成多行。
Widget yAxisTitle(double value, TitleMeta meta, {TextStyle? style, bool compactThousands = false}) {
  return SideTitleWidget(
    meta: meta,
    space: 6,
    child: Text(
      formatYAxisLabel(value, interval: meta.appliedInterval, compactThousands: compactThousands),
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    ),
  );
}
