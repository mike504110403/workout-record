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

    test('肌群篩選:當天沒練到該肌群的資料點 y 落底為 0,不是被跳過', () {
      final points = [
        VolumeDataPoint(
          date: DateTime(2026, 8, 1),
          totalVolume: 500,
          muscleGroupVolumes: const {PrimaryMuscleGroup.chest: 500},
        ),
        VolumeDataPoint(date: DateTime(2026, 8, 2), totalVolume: 300), // 沒練胸
      ];

      final spots = buildVolumeSpots(points, MuscleGroupFilter.chest);

      // 若「跳過」而非「落底 0」,spots 長度會是 1 而非 2。
      expect(spots, hasLength(2));
      expect(spots[0].y, 500);
      expect(spots[1].y, 0);
    });

    test('空資料回傳空清單', () {
      expect(buildVolumeSpots(const [], MuscleGroupFilter.all), isEmpty);
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
