// 月曆格線的純函式計算,獨立於 widget 樹之外方便單獨驗證。對照 iOS
// `HistoryCalendarView.getDaysInMonth()`,月初前 / 月底後的空格回傳 null。
// 與 iOS 差異:iOS 以週日為每列起點;這裡改週一,與歷史列表週分組、首頁
// 「本週」、每週目標的週一起算一致(2026-11-11 大腦依預授權裁定)。

/// 產生 [month] 所在月份的格線(7 欄一列,格數固定為 7 的倍數,對齊當月
/// 天數 + 月初前導空格後,補齊到 7 的倍數,不強制 6 列——天數少的月份
/// (如 2 月起始在週六)可能只需要 5 列,不必補到 42 格)。落在當月外的
/// 格子回傳 null,呼叫端渲染成空白。
List<DateTime?> buildCalendarGrid(DateTime month) {
  final firstOfMonth = DateTime(month.year, month.month, 1);
  // DateTime.weekday: 週一=1 .. 週日=7;週一為第 0 欄。
  final leadingEmpty = firstOfMonth.weekday - 1;
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

  final grid = <DateTime?>[
    for (var i = 0; i < leadingEmpty; i++) null,
    for (var day = 1; day <= daysInMonth; day++) DateTime(month.year, month.month, day),
  ];
  while (grid.length % 7 != 0) {
    grid.add(null);
  }
  return grid;
}

/// 截斷到「日」的精度(去掉時分秒),用於比對「這天有沒有訓練」。
DateTime dateOnly(DateTime dateTime) => DateTime(dateTime.year, dateTime.month, dateTime.day);

bool isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// 日曆星期標題列的標籤。順序與 [buildCalendarGrid] 的欄位一致:週一為第 0 欄。
const List<String> kCalendarWeekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
