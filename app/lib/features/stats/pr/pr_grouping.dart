// PR 排行頁的純函式分組層。`PersonalRecordRepository.getPRSummary` 已經依
// 「肌群 value → 動作名稱」排序回傳(見
// `data/repositories/personal_record_repository.dart` 的 `summaries.sort`),
// 這裡只需要照原順序把連續同肌群的項目收攏成區塊,不重新排序——避免跟
// repository 的排序邏輯重複一份、兩邊可能不一致。

import '../../../data/models/exercise.dart';
import '../../../data/models/personal_record.dart';

/// 一個肌群分組區塊。[muscleGroup] 為 null 代表該動作沒有設定主要肌群
/// (對照 iOS `PRCard` 在 `summary.primaryMuscleGroup == nil` 時不顯示肌群
/// 標籤;這裡用 [label] 顯示「未分類」)。
class PrGroupSection {
  const PrGroupSection({required this.muscleGroup, required this.label, required this.summaries});

  final PrimaryMuscleGroup? muscleGroup;
  final String label;
  final List<PRSummary> summaries;
}

const _uncategorizedLabel = '未分類';

/// 把已排序的 [summaries] 依肌群分組,保留輸入順序。
List<PrGroupSection> groupByMuscleGroup(List<PRSummary> summaries) {
  final sections = <PrGroupSection>[];

  for (final summary in summaries) {
    final group = summary.primaryMuscleGroup;
    final label = group?.displayName ?? _uncategorizedLabel;

    final last = sections.isEmpty ? null : sections.last;
    if (last != null && last.muscleGroup == group) {
      last.summaries.add(summary);
    } else {
      sections.add(PrGroupSection(muscleGroup: group, label: label, summaries: [summary]));
    }
  }

  return sections;
}

/// 依動作名稱搜尋 [summaries](不分大小寫、去頭尾空白;空字串回傳原清單)。
/// 保留輸入順序,分組仍交給 [groupByMuscleGroup]。
List<PRSummary> filterSummariesByName(List<PRSummary> summaries, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return summaries;
  return [
    for (final summary in summaries)
      if (summary.exerciseName.toLowerCase().contains(needle)) summary,
  ];
}
