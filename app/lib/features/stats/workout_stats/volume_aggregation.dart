// 容量趨勢圖的聚合邏輯,純函式(不吃 BuildContext/Ref/DB),方便獨立單元
// 測試、參照值手算。對照 iOS
// `ios/.../Sources/ViewModels/VolumeChartViewModel.swift` 的
// `aggregateVolumeByDate`/`inferMuscleGroupFromName`/`averageVolume`/
// `maxVolume`。
import '../../../data/models/exercise.dart';
import '../../../data/models/workout.dart';
import '../chart_palette.dart';

/// 單日的容量資料點:總容量 + 依肌群拆分的容量(只有「當天有練到」的肌群
/// 才會是這個 map 的 key——沒練到的肌群不補 0 這個 entry,對齊 iOS
/// `VolumeDataPoint.muscleGroupVolumes` 只在有動作命中該肌群時才寫入)。
class VolumeDataPoint {
  const VolumeDataPoint({
    required this.date,
    required this.totalVolume,
    this.muscleGroupVolumes = const {},
  });

  /// 當天日期(已正規化到當地午夜,不含時分秒)。
  final DateTime date;
  final double totalVolume;
  final Map<PrimaryMuscleGroup, double> muscleGroupVolumes;
}

class _DailyAcc {
  double total = 0;
  final Map<PrimaryMuscleGroup, double> byMuscleGroup = {};
}

/// 動作肌群歸屬:優先用 `Exercise.primaryMuscleGroup`(repository 已 join
/// 好的關聯動作);查無關聯動作或該動作沒填肌群時(自訂動作、或系統動作被
/// 刪除後留下的孤兒 id),退回從動作名稱推斷。
///
/// 與 iOS 的已知差異:iOS 在「查無關聯動作」與「名稱推斷」之間還有一層
/// `CustomExerciseStorage`(自訂動作的獨立儲存)查詢,Flutter 版的自訂動作
/// 本來就走 `Exercises` 表(`ExerciseRepository`),沒有獨立儲存這層,所以
/// 這裡只有「關聯動作有肌群」→「名稱推斷」兩層,少了 iOS 那層中繼 fallback
/// ——對應到的資料在 Flutter 版本來就會出現在 `exercise.primaryMuscleGroup`
/// 這一層,不會漏接。
PrimaryMuscleGroup? resolveMuscleGroup(WorkoutExercise exercise) {
  final direct = exercise.exercise?.primaryMuscleGroup;
  if (direct != null) return direct;
  final name = exercise.exerciseName ?? exercise.exercise?.name ?? '';
  return inferMuscleGroupFromName(name);
}

/// 從動作名稱推斷主要肌群。關鍵字與檢查順序照 iOS
/// `VolumeChartViewModel.inferMuscleGroupFromName` 原樣搬移,包含其看似
/// 重疊的地方——胸部關鍵字含「press」,肩部關鍵字也含「press」,但胸部檢查
/// 排在肩部之前,所以名稱只含「press」(例如英文的「Shoulder Press」)會被
/// 歸類成胸部而非肩部。這是 iOS 原始邏輯本來就有的行為(順序決定優先權),
/// 為了「對齊 iOS」原樣保留,不自作主張調整順序。
PrimaryMuscleGroup? inferMuscleGroupFromName(String exerciseName) {
  final name = exerciseName.toLowerCase();

  bool contains(List<String> keywords) => keywords.any(name.contains);

  if (contains(['胸', 'chest', '飛鳥', 'press'])) return PrimaryMuscleGroup.chest;
  if (contains(['背', 'back', '拉', 'pull', '划船'])) return PrimaryMuscleGroup.back;
  if (contains(['腿', 'leg', '蹲', 'squat', '深蹲'])) return PrimaryMuscleGroup.legs;
  if (contains(['肩', 'shoulder', '推舉', 'press'])) return PrimaryMuscleGroup.shoulders;
  if (contains(['手臂', 'arm', '二頭', '三頭', 'bicep', 'tricep'])) {
    return PrimaryMuscleGroup.arms;
  }
  if (contains(['核心', 'core', '腹', 'abs', '平板'])) return PrimaryMuscleGroup.core;

  return null;
}

/// 把一批(已由 repository 排除草稿、含 exercises/sets 的)訓練記錄按日期
/// 分組,算出每日總容量與各肌群容量。總容量與肌群容量皆排除暖身組(對齊
/// [nonWarmupTotalVolume] 慣例,不信任 `Workout.totalVolume`/
/// `WorkoutExercise.totalVolume` 欄位——這兩個欄位跟 dashboard 一樣沒有
/// 即時維護的寫入路徑)。回傳結果依日期升冪排序。
List<VolumeDataPoint> aggregateVolumeByDate(List<Workout> workouts) {
  final byDate = <DateTime, _DailyAcc>{};

  for (final workout in workouts) {
    final dateKey = DateTime(
      workout.startedAt.year,
      workout.startedAt.month,
      workout.startedAt.day,
    );
    final acc = byDate.putIfAbsent(dateKey, _DailyAcc.new);
    acc.total += nonWarmupTotalVolume(workout.exercises);

    for (final exercise in workout.exercises) {
      final volume = nonWarmupExerciseVolume(exercise);
      if (volume <= 0) continue;
      final muscleGroup = resolveMuscleGroup(exercise);
      if (muscleGroup == null) continue;
      acc.byMuscleGroup.update(
        muscleGroup,
        (current) => current + volume,
        ifAbsent: () => volume,
      );
    }
  }

  final points = byDate.entries
      .map(
        (entry) => VolumeDataPoint(
          date: entry.key,
          totalVolume: entry.value.total,
          muscleGroupVolumes: Map.unmodifiable(entry.value.byMuscleGroup),
        ),
      )
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return points;
}

/// 依目前選中的肌群篩選,取出單一資料點對應的容量值。`all` 用當日總容量;
/// 選了特定肌群時,若當天沒練到該肌群(`muscleGroupVolumes` 沒有這個 key)
/// 回傳 0。**唯一的 production 呼叫端是圖表的 `buildVolumeSpots`**
/// (volume_chart_spots.dart),且它只吃 `chartPointsForFilter` 已過濾
/// (該肌群 >0)的點——所以 `?? 0` 分支在圖表路徑不可達,保留為純防禦
/// (目前只有單元測試會走到);[calculateVolumeStats] 不呼叫這個函式,
/// 它直接讀 `muscleGroupVolumes` 並自行處理「沒練到的日子」的排除。
///
/// `filter == all` 已提前 return,之後的分支 `filter.primaryMuscleGroup`
/// 保證非 null(見 [MuscleGroupFilter.primaryMuscleGroup] 的 switch——只有
/// `all` 回傳 null),不需要再判一次 null。
double volumeForFilter(VolumeDataPoint point, MuscleGroupFilter filter) {
  if (filter == MuscleGroupFilter.all) return point.totalVolume;
  return point.muscleGroupVolumes[filter.primaryMuscleGroup!] ?? 0;
}

/// 圖下統計摘要:平均容量/最高容量/數據點數。對照 iOS
/// `VolumeChartViewModel.averageVolume`/`maxVolume`/`VolumeChartView` 的
/// 「數據點」欄位(`dataPoints.count`)。
///
/// 關鍵語意(照抄 iOS,容易看漏的地方):篩選特定肌群時,平均/最高容量只計
/// 「當天真的練到該肌群」的日子(`muscleGroupVolumes` 有該 key 的資料點)
/// ——不是把沒練到的日子當 0 拉低平均;但「數據點數」這個統計項固定顯示
/// [dataPoints] 的總天數,不受肌群篩選影響(iOS 用的是
/// `viewModel.dataPoints.count`,不是篩選後的子集合大小)。
///
/// **與 iOS 的刻意差異(空資料/篩選無命中時的「最高容量」)**:iOS
/// `VolumeChartViewModel.maxVolume` 在完全沒有資料時回退成寫死的 `100`
/// (那個值原本是給 iOS 圖表 y 軸上限用的 fallback,不是真的「最高容量」)。
/// 這裡回傳 `0`——因為 [VolumeStats.highest] 在這個 Flutter 版本只用來
/// 顯示在統計摘要文字上(見 `volume_chart_section.dart` 的
/// `formatVolumeKg(stats.highest)`),沒有 iOS 那種「拿這個值當圖表 y 軸
/// 上限」的用途,回傳 `0` 對使用者來說語意更誠實(「目前沒有資料」不該
/// 顯示一個看起來像是真實數值的 `100`)。r2 review 打回記錄:此差異先前
/// 只在 PR 回報文字裡提過,沒有落在程式碼裡,這裡補上。
class VolumeStats {
  const VolumeStats({
    required this.average,
    required this.highest,
    required this.dataPointCount,
  });

  final double average;
  final double highest;
  final int dataPointCount;
}

VolumeStats calculateVolumeStats(
  List<VolumeDataPoint> dataPoints,
  MuscleGroupFilter filter,
) {
  if (dataPoints.isEmpty) {
    return const VolumeStats(average: 0, highest: 0, dataPointCount: 0);
  }

  if (filter == MuscleGroupFilter.all) {
    final volumes = dataPoints.map((p) => p.totalVolume);
    final total = volumes.fold<double>(0, (a, b) => a + b);
    return VolumeStats(
      average: total / dataPoints.length,
      highest: volumes.reduce((a, b) => a > b ? a : b),
      dataPointCount: dataPoints.length,
    );
  }

  // `filter == all` 已在上面提前 return,這裡的 `filter.primaryMuscleGroup`
  // 保證非 null(理由同 [volumeForFilter] 的文件註解),不需要再判一次。
  final muscleGroup = filter.primaryMuscleGroup!;
  var total = 0.0;
  var highest = 0.0;
  var count = 0;
  for (final point in dataPoints) {
    final volume = point.muscleGroupVolumes[muscleGroup];
    if (volume == null) continue;
    total += volume;
    if (volume > highest) highest = volume;
    count += 1;
  }

  return VolumeStats(
    average: count > 0 ? total / count : 0,
    highest: highest,
    dataPointCount: dataPoints.length,
  );
}
