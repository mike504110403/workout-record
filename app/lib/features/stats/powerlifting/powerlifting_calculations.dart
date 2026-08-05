// 「經典三項」子頁的純函式計算層。全部不碰 DB/DateTime.now(),方便單元測試
// 用手算參照值驗證。對照基準:
// `ios/WorkoutRecord/WorkoutRecord/Sources/ViewModels/PowerliftingViewModel.swift`
// `ios/WorkoutRecord/WorkoutRecord/Sources/Models/PowerLift.swift`。

import '../../../data/models/personal_record.dart';
import '../../../data/models/power_lift_record.dart';

/// 判斷動作名稱是否符合三項力量動作之一。對照 iOS
/// `PowerLift.matches(exerciseName:)`——整串先轉小寫再比對,中文關鍵字轉
/// 小寫不影響內容,英文關鍵字才需要這一步(避免使用者輸入 "Bench Press"
/// 之類大小寫混寫漏比對)。
bool powerLiftMatchesExerciseName(PowerLift lift, String exerciseName) {
  final lower = exerciseName.toLowerCase();
  switch (lift) {
    case PowerLift.squat:
      return lower.contains('深蹲') || lower.contains('squat');
    case PowerLift.benchPress:
      return lower.contains('臥推') || lower.contains('bench press');
    case PowerLift.deadlift:
      return lower.contains('硬舉') || lower.contains('deadlift');
  }
}

/// 手動紀錄中,指定動作的最佳成績(最高 1RM)。無紀錄回傳 null。對照 iOS
/// `manualRecords.filter({ $0.lift == lift }).max(by: { $0.oneRepMax < $1.oneRepMax })`。
PowerLiftRecord? bestManualRecord(List<PowerLiftRecord> records, PowerLift lift) {
  PowerLiftRecord? best;
  for (final record in records) {
    if (record.lift != lift) continue;
    if (best == null || record.oneRepMax > best.oneRepMax) best = record;
  }
  return best;
}

/// 三項總和。對照 iOS `PowerliftingViewModel.totalLifts` 的實際邏輯——
/// 只加總「手動紀錄」每個動作的最佳 1RM(系統推估紀錄不計入,iOS 原始碼
/// 只迭代 `manualRecords`,完全沒有讀 `systemEstimatedRecords`);沒有手動
/// 紀錄的動作直接跳過該項,**不補 0**(iOS 用 `if let pr = ... { total += ... }`,
/// 找不到就整條跳過)。
double totalLifts(List<PowerLiftRecord> manualRecords) {
  var total = 0.0;
  for (final lift in PowerLift.values) {
    final best = bestManualRecord(manualRecords, lift);
    if (best != null) total += best.oneRepMax;
  }
  return total;
}

/// 依動作篩選手動紀錄,依 achievedAt **由新到舊**排序。對照 iOS
/// `currentManualRecords`。
List<PowerLiftRecord> manualRecordsForLift(List<PowerLiftRecord> records, PowerLift lift) {
  final filtered = records.where((r) => r.lift == lift).toList()
    ..sort((a, b) => b.achievedAt.compareTo(a.achievedAt));
  return filtered;
}

/// 1RM 趨勢圖資料:指定動作的手動紀錄,依 achievedAt **由舊到新**排序
/// (對照 iOS `chartData`,圖表要照時間順序畫線,跟上面的列表排序方向相反)。
List<PowerLiftRecord> chartRecordsForLift(List<PowerLiftRecord> records, PowerLift lift) {
  final filtered = records.where((r) => r.lift == lift).toList()
    ..sort((a, b) => a.achievedAt.compareTo(b.achievedAt));
  return filtered;
}

/// 從 PR 總結中篩出「動作名稱匹配指定三項動作」的項目。對照 iOS
/// `PowerliftingViewModel.loadRecords` 用 `PowerLift.matches(exerciseName:)`
/// 從 `PersonalRecord.exercise.name` 篩選的邏輯——差異見本檔案開頭以外的
/// 呼叫端註解(改用 `PRSummary.exerciseName`,見 powerlifting_controller.dart)。
/// 可能匹配到多個動作(例如「上斜臥推」與「槓鈴臥推」都含「臥推」),對齊
/// iOS 用子字串比對、不要求動作名稱完全等於三項動作標準名稱的行為。
List<PRSummary> systemEstimatedSummaries(List<PRSummary> allSummaries, PowerLift lift) {
  return allSummaries.where((s) => powerLiftMatchesExerciseName(lift, s.exerciseName)).toList();
}

/// 指定動作的系統推估最佳 1RM——在所有匹配動作的 currentPR 中取最高。
/// 對照 iOS `currentSystemPR`(在攤平後的 systemEstimatedRecords 裡取最高
/// 1RM;這裡用 `PRSummary.currentPR` 已經是各動作歷史最高,取其中最高等價)。
PersonalRecord? bestSystemEstimate(List<PRSummary> allSummaries, PowerLift lift) {
  PersonalRecord? best;
  for (final summary in systemEstimatedSummaries(allSummaries, lift)) {
    final pr = summary.currentPR;
    if (pr == null) continue;
    if (best == null || pr.oneRepMax > best.oneRepMax) best = pr;
  }
  return best;
}
