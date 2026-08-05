import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/features/workout/one_rm_calculator.dart';

void main() {
  group('calculateOneRepMax', () {
    test('reps == 1:1RM 就是該次重量本身,不套 Epley 公式', () {
      expect(calculateOneRepMax(weight: 100, reps: 1), 100);
    });

    test('reps <= 0:回傳原始重量(邊界,對齊 iOS guard reps > 0)', () {
      expect(calculateOneRepMax(weight: 80, reps: 0), 80);
      expect(calculateOneRepMax(weight: 80, reps: -3), 80);
    });

    test('reps > 1:套 Epley 公式 weight * (1 + reps / 30)', () {
      // 100 * (1 + 10/30) = 100 * 1.3333... = 133.33...
      expect(calculateOneRepMax(weight: 100, reps: 10), closeTo(133.33, 0.01));
      // 60 * (1 + 5/30) = 60 * 1.1666... = 70
      expect(calculateOneRepMax(weight: 60, reps: 5), closeTo(70, 0.001));
    });
  });
}
