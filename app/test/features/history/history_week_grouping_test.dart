// 週分組與動作摘要的純函式測試(注入 now,不依賴執行當下日期)。
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_record/data/models/exercise.dart';
import 'package:workout_record/data/models/workout.dart';
import 'package:workout_record/features/history/history_format.dart';
import 'package:workout_record/features/history/history_week_grouping.dart';

Workout _workout(String id, DateTime startedAt, {List<WorkoutExercise> exercises = const []}) {
  final now = DateTime(2026, 1, 1);
  return Workout(
    id: id,
    userId: 'u',
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 30)),
    duration: 30,
    exercises: exercises,
    createdAt: now,
    updatedAt: now,
  );
}

WorkoutExercise _exercise(String id, {String? name, Exercise? exercise}) {
  final now = DateTime(2026, 1, 1);
  return WorkoutExercise(
    id: id,
    workoutId: 'w',
    exerciseId: 'e-$id',
    exerciseName: name,
    exercise: exercise,
    orderIndex: 0,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('groupWorkoutsByWeek', () {
    // 2026-11-11 是週三 → 本週 11/9(一) – 11/15(日)。
    final now = DateTime(2026, 11, 11, 12);

    test('本週/上週/日期區間標題,同週收攏、保留輸入順序', () {
      final groups = groupWorkoutsByWeek([
        _workout('a', DateTime(2026, 11, 11, 8)),
        _workout('b', DateTime(2026, 11, 9, 8)), // 本週一(週界線內)
        _workout('c', DateTime(2026, 11, 8, 23)), // 上週日(週界線外)
        _workout('d', DateTime(2026, 11, 3, 8)), // 上週二
        _workout('e', DateTime(2026, 10, 28, 8)), // 兩週前(10/26 – 11/1)
      ], now: now);

      expect([for (final g in groups) g.label], ['本週', '上週', '10/26 – 11/1']);
      expect(
        [
          for (final g in groups) [for (final w in g.workouts) w.id],
        ],
        [
          ['a', 'b'],
          ['c', 'd'],
          ['e'],
        ],
      );
    });

    test('跨月/跨年的區間標題', () {
      final groups = groupWorkoutsByWeek([_workout('x', DateTime(2025, 12, 31, 8))], now: now);
      expect(groups.single.label, '12/29 – 1/4');
    });

    test('空清單回傳空分組', () {
      expect(groupWorkoutsByWeek(const [], now: now), isEmpty);
    });
  });

  group('summarizeWorkoutExercises', () {
    test('無動作回傳 null', () {
      expect(summarizeWorkoutExercises(_workout('w', DateTime(2026, 11, 1))), isNull);
    });

    test('1~2 個動作列全名,>2 個以 +N 收尾', () {
      Workout withNames(List<String> names) => _workout(
        'w',
        DateTime(2026, 11, 1),
        exercises: [for (final (i, n) in names.indexed) _exercise('$i', name: n)],
      );
      expect(summarizeWorkoutExercises(withNames(['槓鈴臥推'])), '槓鈴臥推');
      expect(summarizeWorkoutExercises(withNames(['槓鈴臥推', '深蹲'])), '槓鈴臥推、深蹲');
      expect(summarizeWorkoutExercises(withNames(['槓鈴臥推', '深蹲', '硬舉', '划船'])), '槓鈴臥推、深蹲 +2');
    });

    test('缺名稱時退回「未知動作」', () {
      final w = _workout('w', DateTime(2026, 11, 1), exercises: [_exercise('0')]);
      expect(summarizeWorkoutExercises(w), '未知動作');
    });
  });

  test('formatHistoryWeekday:週一..週日', () {
    expect(formatHistoryWeekday(DateTime(2026, 11, 9)), '週一');
    expect(formatHistoryWeekday(DateTime(2026, 11, 15)), '週日');
  });
}
