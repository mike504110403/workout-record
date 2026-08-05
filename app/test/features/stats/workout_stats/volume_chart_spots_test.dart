// buildVolumeSpots/formatChartAxisDate 是「資料層」斷言的落點——widget
// test 只驗證使用者能觸發正確的資料變化,實際的 spot 數值在這裡直接手算
// 驗證,不逐像素檢查圖表畫面(對照 brief 的 fl_chart 驗收要求)。
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/features/stats/chart_palette.dart';
import 'package:workout_record/features/stats/workout_stats/chart_time_range.dart';
import 'package:workout_record/features/stats/workout_stats/volume_aggregation.dart';
import 'package:workout_record/features/stats/workout_stats/volume_chart_spots.dart';

void main() {
  group('buildVolumeSpots', () {
    test('all 篩選:x 為索引、y 為當日總容量', () {
      final points = [
        VolumeDataPoint(date: DateTime(2026, 8, 1), totalVolume: 100),
        VolumeDataPoint(date: DateTime(2026, 8, 2), totalVolume: 300),
      ];

      final spots = buildVolumeSpots(points, MuscleGroupFilter.all);

      expect(spots, hasLength(2));
      expect(spots[0].x, 0);
      expect(spots[0].y, 100);
      expect(spots[1].x, 1);
      expect(spots[1].y, 300);
    });

    // r2 review 打回記錄(major 1):先前這裡釘住「落底畫 0」,與 iOS
    // `VolumeChartView.swift:106`(`if let volume = ..., volume > 0` 才產生
    // mark)不符,也跟 `calculateVolumeStats` 的「平均/最高只算有練到的
    // 日子」自相矛盾。改成整點跳過,x 軸用篩選後子集合的連續索引——這裡的
    // 斷言反轉成釘住「跳過」;若實作改回落底畫 0,`hasLength(2)` 那條會
    // 失敗(變成 3,因為中間沒練到的那天也會被畫進來)。
    test('肌群篩選:當天沒練到該肌群的資料點被整個跳過(對齊 iOS volume>0 才產生 mark),x 軸是跳過後的連續索引', () {
      final points = [
        VolumeDataPoint(
          date: DateTime(2026, 8, 1),
          totalVolume: 500,
          muscleGroupVolumes: const {PrimaryMuscleGroup.chest: 500},
        ),
        VolumeDataPoint(date: DateTime(2026, 8, 2), totalVolume: 300), // 沒練胸,應被跳過
        VolumeDataPoint(
          date: DateTime(2026, 8, 3),
          totalVolume: 700,
          muscleGroupVolumes: const {PrimaryMuscleGroup.chest: 200},
        ),
      ];

      final spots = buildVolumeSpots(points, MuscleGroupFilter.chest);

      // 3 個資料點中只有 2 個練到胸——若被跳過的那天沒有真的被排除,這裡
      // 會是 3 而不是 2。
      expect(spots, hasLength(2));
      expect(spots[0].x, 0);
      expect(spots[0].y, 500);
      // 第二個留下的點 x=1(跳過後的連續索引),不是原始清單裡的索引 2——
      // 若 x 軸沒有跟著「跳過」重新編號、還是用原始索引,這裡會斷言到
      // x=2 而非 x=1。
      expect(spots[1].x, 1);
      expect(spots[1].y, 200);
    });

    test('all 篩選:即使某天容量為 0 也照樣輸出(不篩選,對齊 iOS all 模式不檢查 volume>0)', () {
      final points = [
        VolumeDataPoint(date: DateTime(2026, 8, 1), totalVolume: 0),
        VolumeDataPoint(date: DateTime(2026, 8, 2), totalVolume: 300),
      ];

      final spots = buildVolumeSpots(points, MuscleGroupFilter.all);

      expect(spots, hasLength(2));
      expect(spots[0].y, 0);
      expect(spots[1].y, 300);
    });

    test('空資料回傳空清單', () {
      expect(buildVolumeSpots(const [], MuscleGroupFilter.all), isEmpty);
    });
  });

  group('chartPointsForFilter', () {
    test('肌群篩選後的清單跟 buildVolumeSpots 的索引對得上(x 軸標籤用同一份清單)', () {
      final points = [
        VolumeDataPoint(
          date: DateTime(2026, 8, 1),
          totalVolume: 500,
          muscleGroupVolumes: const {PrimaryMuscleGroup.chest: 500},
        ),
        VolumeDataPoint(date: DateTime(2026, 8, 2), totalVolume: 300),
      ];

      final filtered = chartPointsForFilter(points, MuscleGroupFilter.chest);

      expect(filtered, hasLength(1));
      expect(filtered.single.date, DateTime(2026, 8, 1));
    });

    test('all 篩選回傳原始清單(不過濾)', () {
      final points = [
        VolumeDataPoint(date: DateTime(2026, 8, 1), totalVolume: 0),
        VolumeDataPoint(date: DateTime(2026, 8, 2), totalVolume: 300),
      ];

      expect(chartPointsForFilter(points, MuscleGroupFilter.all), points);
    });
  });

  group('formatChartAxisDate', () {
    test('週/月/3月用 MM/dd', () {
      final date = DateTime(2026, 3, 5);
      expect(formatChartAxisDate(date, ChartTimeRange.week), '03/05');
      expect(formatChartAxisDate(date, ChartTimeRange.month), '03/05');
      expect(formatChartAxisDate(date, ChartTimeRange.threeMonths), '03/05');
    });

    test('年用 yyyy/MM', () {
      expect(formatChartAxisDate(DateTime(2026, 3, 5), ChartTimeRange.year), '2026/03');
    });
  });
}
