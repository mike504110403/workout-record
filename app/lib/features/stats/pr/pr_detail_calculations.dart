// PR 詳情頁的純函式計算層(不吃 BuildContext / WidgetRef,方便單獨測試)。
//
// 1RM 一律以「偏好設定的公式」對 weight/reps 重算(對照 iOS
// `PRDetailView` 顯示 PR 的 1RM,但 Flutter 版的公式可在偏好設定切換,見
// `features/settings/preferences/one_rm_formula_preference.dart`);儲存值
// `PersonalRecord.oneRepMax`(寫入當下的公式結果)在此頁不直接顯示。
// 重量單位換算不在此層——這裡全部回傳 kg,顯示層再依 `weightUnitProvider`
// 換算。
import '../../../data/models/personal_record.dart';
import '../../settings/preferences/one_rm_formula_preference.dart';
import '../../workout/one_rm_calculator.dart';

/// 一筆 PR 加上「依目前公式重算的 1RM(kg)」。
class PrDetailEntry {
  const PrDetailEntry({required this.record, required this.oneRepMax});

  final PersonalRecord record;

  /// 依 [OneRmFormula] 對 record.weight/reps 重算的 1RM(kg)。
  final double oneRepMax;
}

/// 進步統計:最早一筆到最新一筆(依達成日)的 1RM 差(kg)與百分比。
class PrProgress {
  const PrProgress({required this.deltaKg, required this.percent});

  final double deltaKg;
  final double percent;
}

class PrDetailData {
  const PrDetailData({
    required this.historyDesc,
    required this.current,
    required this.chartAsc,
    required this.progress,
  });

  /// 歷史列表:達成日新到舊(同日以輸入順序為準,排序穩定)。
  final List<PrDetailEntry> historyDesc;

  /// 當前 PR:重算 1RM 最高的一筆(同值取達成日較新者)。空資料為 null。
  final PrDetailEntry? current;

  /// 趨勢圖資料:達成日舊到新。
  final List<PrDetailEntry> chartAsc;

  /// 少於兩筆、或最早一筆 1RM <= 0 時為 null。
  final PrProgress? progress;

  bool get isEmpty => historyDesc.isEmpty;
}

PrDetailData buildPrDetailData(List<PersonalRecord> records, OneRmFormula formula) {
  final entries = [
    for (final r in records)
      PrDetailEntry(
        record: r,
        oneRepMax: calculateOneRepMax(weight: r.weight, reps: r.reps, formula: formula),
      ),
  ];

  // Dart 的 List.sort 不保證穩定,同日資料用 index 當 tie-breaker 固定順序。
  final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])];
  indexed.sort((a, b) {
    final byDate = b.$2.record.achievedAt.compareTo(a.$2.record.achievedAt);
    return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
  });
  final historyDesc = [for (final e in indexed) e.$2];

  PrDetailEntry? current;
  for (final e in historyDesc) {
    // historyDesc 新到舊,嚴格大於才換 => 同值時保留較新的一筆。
    if (current == null || e.oneRepMax > current.oneRepMax) current = e;
  }

  final chartAsc = historyDesc.reversed.toList();

  PrProgress? progress;
  if (historyDesc.length > 1) {
    final first = chartAsc.first.oneRepMax;
    final latest = historyDesc.first.oneRepMax;
    if (first > 0) {
      progress = PrProgress(deltaKg: latest - first, percent: (latest - first) / first * 100);
    }
  }

  return PrDetailData(historyDesc: historyDesc, current: current, chartAsc: chartAsc, progress: progress);
}
