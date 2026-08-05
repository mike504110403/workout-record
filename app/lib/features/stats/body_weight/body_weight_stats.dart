// 體重統計卡片與趨勢圖所需的純函式計算。刻意獨立於 UI/Repository，方便
// 直接用手算的參照值單元測試（見 /tdd：純函式化、參照值獨立於實作）。
import '../../../data/models/body_weight.dart';

/// 統計資訊卡片所需的彙總數字。無資料時全部欄位為 null（`target` 除外——
/// 目標體重獨立於是否有體重紀錄，即使一筆紀錄都沒有，只要
/// `UserGoalRepository` 有設定目標，卡片仍要顯示目標值）。
class BodyWeightSummary {
  const BodyWeightSummary({
    this.current,
    this.target,
    this.average,
    this.max,
    this.min,
    this.change,
  });

  /// 當前體重（最新一筆，對照 iOS `bodyWeights.first`）。
  final double? current;

  /// 目標體重（`UserGoalRepository.fetchByUser(...).targetWeight`）。
  final double? target;

  /// 平均體重（全部紀錄的算術平均）。
  final double? average;

  /// 最高體重。
  final double? max;

  /// 最低體重。
  final double? min;

  /// 變化幅度：最新一筆減次新一筆（對照 iOS
  /// `BodyWeightViewModel.weightChange` = `bodyWeights[0] - bodyWeights[1]`）。
  /// 只有一筆或沒有紀錄時為 null。
  final double? change;
}

/// 從體重紀錄計算統計卡片所需的彙總值。
///
/// [entriesDescByMeasuredAt] **必須**是「measuredAt 由新到舊」排序（對照
/// `BodyWeightRepository.fetchAll()` 既有的排序方式）——本函式不會重新
/// 排序輸入，`current` 直接取 `[0]`，`change` 直接取
/// `[0].weight - [1].weight`。呼叫端若不小心傳入排序相反（或未排序）的
/// list，這兩個欄位會直接算錯，這是刻意的：排序責任在呼叫端一次做好，
/// 不要讓這個純函式對輸入順序做隱性假設之外的糾正，隱性糾正會讓「呼叫端
/// 排序真的錯了」這種 bug 被靜默吃掉。
BodyWeightSummary computeBodyWeightSummary(
  List<BodyWeight> entriesDescByMeasuredAt, {
  double? targetWeight,
}) {
  if (entriesDescByMeasuredAt.isEmpty) {
    return BodyWeightSummary(target: targetWeight);
  }

  final weights = entriesDescByMeasuredAt.map((e) => e.weight).toList(growable: false);
  final sum = weights.fold<double>(0, (total, w) => total + w);
  final average = sum / weights.length;
  final max = weights.reduce((a, b) => a > b ? a : b);
  final min = weights.reduce((a, b) => a < b ? a : b);

  double? change;
  if (entriesDescByMeasuredAt.length >= 2) {
    change = entriesDescByMeasuredAt[0].weight - entriesDescByMeasuredAt[1].weight;
  }

  return BodyWeightSummary(
    current: entriesDescByMeasuredAt.first.weight,
    target: targetWeight,
    average: average,
    max: max,
    min: min,
    change: change,
  );
}

/// 依 measuredAt 由舊到新排序，給趨勢圖畫圖用。
///
/// `BodyWeightRepository.fetchAll()` 本身回傳新到舊（給列表用），趨勢圖
/// 需要相反的方向（見 brief：「按 measuredAt 升序畫圖」）——這裡刻意複製
/// 一份新 list 再排序（`List.sort` 是 in-place），不動到呼叫端手上的原始
/// list，因為同一份資料在同一個畫面裡列表仍要維持新到舊顯示。
List<BodyWeight> sortBodyWeightsAscending(List<BodyWeight> entries) {
  final sorted = List<BodyWeight>.of(entries);
  sorted.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  return sorted;
}
