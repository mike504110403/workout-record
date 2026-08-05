// PR 排行頁專用的純函式格式化工具。獨立於
// `features/stats/powerlifting/powerlifting_format.dart` 一份(不跨 feature
// 目錄 import,理由同該檔案開頭注解)。

/// 對照 iOS `String(format: "%.1f", value)`。
String formatWeight(double weight) => weight.toStringAsFixed(1);

/// 對照 iOS `.formatted(date: .abbreviated, time: .omitted)` 的視覺效果。
String formatDate(DateTime date) => '${date.year}/${date.month}/${date.day}';
