// 容量趨勢圖聚合邏輯的純函式測試。所有參照值都獨立手算(不是照抄被測程式
// 的公式),避免測試跟被測程式共用同一個(可能錯誤的)算法互相掩護。
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/features/stats/chart_palette.dart';
import 'package:workout_record/features/stats/workout_stats/volume_aggregation.dart';

final _now = DateTime(2026, 8, 5, 12);

Exercise _buildExercise({
  required String id,
  required String name,
  PrimaryMuscleGroup? primaryMuscleGroup,
}) {
  return Exercise(
    id: id,
    name: name,
    categoryId: 'cat-1',
    type: ExerciseType.freeWeight,
    primaryMuscleGroup: primaryMuscleGroup,
    createdAt: _now,
    updatedAt: _now,
  );
}

WorkoutSet _buildSet({
  required String id,
  required double weight,
  required int reps,
  bool isWarmup = false,
}) {
  return WorkoutSet(
    id: id,
    workoutExerciseId: 'we-x',
    setNumber: 1,
    weight: weight,
    reps: reps,
    isWarmup: isWarmup,
    createdAt: _now,
    updatedAt: _now,
  );
}

WorkoutExercise _buildWorkoutExercise({
  required String id,
  Exercise? exercise,
  String? exerciseName,
  required List<WorkoutSet> sets,
}) {
  return WorkoutExercise(
    id: id,
    workoutId: 'w-x',
    exerciseId: exercise?.id ?? 'unknown-exercise',
    exercise: exercise,
    exerciseName: exerciseName,
    sets: sets,
    createdAt: _now,
    updatedAt: _now,
  );
}

Workout _buildWorkout({
  required String id,
  required DateTime startedAt,
  required List<WorkoutExercise> exercises,
}) {
  return Workout(
    id: id,
    userId: 'user-1',
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 30)),
    exercises: exercises,
    createdAt: _now,
    updatedAt: _now,
  );
}

void main() {
  group('inferMuscleGroupFromName', () {
    test('中文關鍵字對應各肌群', () {
      expect(inferMuscleGroupFromName('槓鈴胸推'), PrimaryMuscleGroup.chest);
      expect(inferMuscleGroupFromName('滑輪下拉'), PrimaryMuscleGroup.back);
      expect(inferMuscleGroupFromName('深蹲'), PrimaryMuscleGroup.legs);
      expect(inferMuscleGroupFromName('二頭彎舉'), PrimaryMuscleGroup.arms);
      expect(inferMuscleGroupFromName('捲腹'), PrimaryMuscleGroup.core);
    });

    test('英文關鍵字對應各肌群(大小寫不敏感)', () {
      expect(inferMuscleGroupFromName('Bench Press'), PrimaryMuscleGroup.chest);
      expect(inferMuscleGroupFromName('LAT PULLDOWN'), PrimaryMuscleGroup.back);
      expect(inferMuscleGroupFromName('Barbell Squat'), PrimaryMuscleGroup.legs);
    });

    test('肩部關鍵字「肩」可正確推斷(不含 press 這個重疊關鍵字)', () {
      expect(inferMuscleGroupFromName('肩部側平舉'), PrimaryMuscleGroup.shoulders);
    });

    test(
      '對齊 iOS 原始邏輯的已知順序重疊:名稱只含「press」時因胸部檢查排在'
      '肩部之前,會被歸類成胸部,不是肩部(照 iOS VolumeChartViewModel 原樣'
      '搬移,不是這裡的臭蟲)',
      () {
        expect(inferMuscleGroupFromName('Shoulder Press'), PrimaryMuscleGroup.chest);
      },
    );

    test('無法辨識任何關鍵字時回傳 null', () {
      expect(inferMuscleGroupFromName('神秘動作 XYZ'), isNull);
    });
  });

  group('resolveMuscleGroup', () {
    test('關聯動作有 primaryMuscleGroup 時優先採用,不看名稱', () {
      final exercise = _buildExercise(id: 'e1', name: '深蹲', primaryMuscleGroup: PrimaryMuscleGroup.chest);
      final we = _buildWorkoutExercise(id: 'we1', exercise: exercise, sets: const []);
      // 動作名稱明明是「深蹲」(會被名稱推斷成 legs),但關聯動作的
      // primaryMuscleGroup 明確標成 chest,優先信任關聯動作。
      expect(resolveMuscleGroup(we), PrimaryMuscleGroup.chest);
    });

    test('沒有關聯動作(自訂動作)時退回從 exerciseName 推斷', () {
      final we = _buildWorkoutExercise(id: 'we1', exercise: null, exerciseName: '自訂深蹲變化式', sets: const []);
      expect(resolveMuscleGroup(we), PrimaryMuscleGroup.legs);
    });

    test('關聯動作存在但 primaryMuscleGroup 是 null 時退回名稱推斷(用關聯動作的 name)', () {
      final exercise = _buildExercise(id: 'e1', name: '某胸部動作');
      final we = _buildWorkoutExercise(id: 'we1', exercise: exercise, sets: const []);
      expect(resolveMuscleGroup(we), PrimaryMuscleGroup.chest);
    });

    test('名稱也推斷不出來時回傳 null', () {
      final we = _buildWorkoutExercise(id: 'we1', exercise: null, exerciseName: '神秘動作', sets: const []);
      expect(resolveMuscleGroup(we), isNull);
    });
  });

  group('aggregateVolumeByDate', () {
    test('同一天多筆訓練合併成一個資料點,總容量正確加總(手算)', () {
      final chest = _buildExercise(id: 'e-chest', name: '臥推', primaryMuscleGroup: PrimaryMuscleGroup.chest);
      final day = DateTime(2026, 8, 1, 8);
      final w1 = _buildWorkout(
        id: 'w1',
        startedAt: day,
        exercises: [
          _buildWorkoutExercise(
            id: 'we1',
            exercise: chest,
            sets: [_buildSet(id: 's1', weight: 60, reps: 10)], // 600
          ),
        ],
      );
      final w2 = _buildWorkout(
        id: 'w2',
        startedAt: DateTime(2026, 8, 1, 18), // 同一天晚上又練一次
        exercises: [
          _buildWorkoutExercise(
            id: 'we2',
            exercise: chest,
            sets: [_buildSet(id: 's2', weight: 40, reps: 10)], // 400
          ),
        ],
      );

      final points = aggregateVolumeByDate([w1, w2]);

      expect(points, hasLength(1));
      // 手算:600 + 400 = 1000。
      expect(points.single.totalVolume, 1000);
      expect(points.single.muscleGroupVolumes[PrimaryMuscleGroup.chest], 1000);
    });

    test('排除暖身組(不只總容量,肌群容量也要排除)——變異:暖身計入必紅', () {
      final chest = _buildExercise(id: 'e-chest', name: '臥推', primaryMuscleGroup: PrimaryMuscleGroup.chest);
      final w = _buildWorkout(
        id: 'w1',
        startedAt: DateTime(2026, 8, 1),
        exercises: [
          _buildWorkoutExercise(
            id: 'we1',
            exercise: chest,
            sets: [
              _buildSet(id: 's-warmup', weight: 20, reps: 10, isWarmup: true), // 200,應排除
              _buildSet(id: 's-work', weight: 60, reps: 10), // 600,應計入
            ],
          ),
        ],
      );

      final points = aggregateVolumeByDate([w]);

      // 手算:只有 work set 的 600,暖身的 200 不計入——若實作誤把暖身也
      // 加進去,這裡會斷言到 800 而非 600,測試必須紅。
      expect(points.single.totalVolume, 600);
      expect(points.single.muscleGroupVolumes[PrimaryMuscleGroup.chest], 600);
    });

    test('不同日期各自成一個資料點,依日期升冪排序', () {
      final chest = _buildExercise(id: 'e-chest', name: '臥推', primaryMuscleGroup: PrimaryMuscleGroup.chest);
      final wLater = _buildWorkout(
        id: 'w-later',
        startedAt: DateTime(2026, 8, 3),
        exercises: [
          _buildWorkoutExercise(id: 'we1', exercise: chest, sets: [_buildSet(id: 's1', weight: 10, reps: 1)]),
        ],
      );
      final wEarlier = _buildWorkout(
        id: 'w-earlier',
        startedAt: DateTime(2026, 8, 1),
        exercises: [
          _buildWorkoutExercise(id: 'we2', exercise: chest, sets: [_buildSet(id: 's2', weight: 20, reps: 1)]),
        ],
      );

      // 刻意先傳「較晚」的那筆,驗證排序不是單純依賴輸入順序。
      final points = aggregateVolumeByDate([wLater, wEarlier]);

      expect(points, hasLength(2));
      expect(points[0].date, DateTime(2026, 8, 1));
      expect(points[1].date, DateTime(2026, 8, 3));
    });

    test('多肌群動作各自累加,互不干擾', () {
      final chest = _buildExercise(id: 'e-chest', name: '臥推', primaryMuscleGroup: PrimaryMuscleGroup.chest);
      final legs = _buildExercise(id: 'e-legs', name: '深蹲', primaryMuscleGroup: PrimaryMuscleGroup.legs);
      final w = _buildWorkout(
        id: 'w1',
        startedAt: DateTime(2026, 8, 1),
        exercises: [
          _buildWorkoutExercise(id: 'we1', exercise: chest, sets: [_buildSet(id: 's1', weight: 50, reps: 10)]),
          _buildWorkoutExercise(id: 'we2', exercise: legs, sets: [_buildSet(id: 's2', weight: 100, reps: 5)]),
        ],
      );

      final points = aggregateVolumeByDate([w]);

      expect(points.single.totalVolume, 1000); // 500 + 500
      expect(points.single.muscleGroupVolumes[PrimaryMuscleGroup.chest], 500);
      expect(points.single.muscleGroupVolumes[PrimaryMuscleGroup.legs], 500);
    });
  });

  group('volumeForFilter', () {
    final point = VolumeDataPoint(
      date: DateTime(2026, 8, 1),
      totalVolume: 1000,
      muscleGroupVolumes: const {PrimaryMuscleGroup.chest: 400},
    );

    test('全部(all)回傳總容量', () {
      expect(volumeForFilter(point, MuscleGroupFilter.all), 1000);
    });

    test('選了有記錄的肌群回傳該肌群容量', () {
      expect(volumeForFilter(point, MuscleGroupFilter.chest), 400);
    });

    test('選了當天沒練到的肌群回傳 0(不是拋錯或回傳總容量)', () {
      expect(volumeForFilter(point, MuscleGroupFilter.legs), 0);
    });
  });

  group('calculateVolumeStats', () {
    test('空資料回傳全 0', () {
      final stats = calculateVolumeStats(const [], MuscleGroupFilter.all);
      expect(stats.average, 0);
      expect(stats.highest, 0);
      expect(stats.dataPointCount, 0);
    });

    test('all 模式:平均/最高取自所有資料點的總容量(手算)', () {
      final points = [
        VolumeDataPoint(date: DateTime(2026, 8, 1), totalVolume: 100),
        VolumeDataPoint(date: DateTime(2026, 8, 2), totalVolume: 300),
        VolumeDataPoint(date: DateTime(2026, 8, 3), totalVolume: 200),
      ];

      final stats = calculateVolumeStats(points, MuscleGroupFilter.all);

      // 手算:(100+300+200)/3 = 200。
      expect(stats.average, 200);
      expect(stats.highest, 300);
      expect(stats.dataPointCount, 3);
    });

    test(
      '篩選特定肌群時,平均/最高只計「當天有練到該肌群」的資料點——'
      '不把沒練到的日子當 0 拉低平均(對齊 iOS 語意)',
      () {
        final points = [
          VolumeDataPoint(
            date: DateTime(2026, 8, 1),
            totalVolume: 500,
            muscleGroupVolumes: const {PrimaryMuscleGroup.chest: 500},
          ),
          // 這天沒有練胸(muscleGroupVolumes 完全沒有 chest 這個 key)。
          VolumeDataPoint(date: DateTime(2026, 8, 2), totalVolume: 300),
          VolumeDataPoint(
            date: DateTime(2026, 8, 3),
            totalVolume: 700,
            muscleGroupVolumes: const {PrimaryMuscleGroup.chest: 300},
          ),
        ];

        final stats = calculateVolumeStats(points, MuscleGroupFilter.chest);

        // 手算:只有兩天練胸(500、300),平均 = (500+300)/2 = 400——
        // 若誤把沒練到的那天當 0 一起除以 3,會得到 800/3 ≈ 266.67,
        // 這裡斷言 400 能抓到那個錯誤實作。
        expect(stats.average, 400);
        expect(stats.highest, 500);
        // 數據點數固定顯示總天數(3 天),不受肌群篩選影響——若誤用篩選後
        // 的子集合大小,這裡會是 2 而非 3。
        expect(stats.dataPointCount, 3);
      },
    );

    test('篩選的肌群完全沒有任何一天練到時,平均/最高皆為 0', () {
      final points = [
        VolumeDataPoint(date: DateTime(2026, 8, 1), totalVolume: 500),
      ];

      final stats = calculateVolumeStats(points, MuscleGroupFilter.core);

      expect(stats.average, 0);
      expect(stats.highest, 0);
      expect(stats.dataPointCount, 1);
    });
  });
}
