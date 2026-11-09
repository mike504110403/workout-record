import 'package:flutter_test/flutter_test.dart';
import 'package:workout_record/features/settings/preferences/one_rm_formula_preference.dart';
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

  group('公式選擇(對照 iOS User.OneRMFormula.calculate)', () {
    test('Brzycki:100kg×5 = 100×36/32 = 112.5', () {
      expect(calculateOneRepMax(weight: 100, reps: 5, formula: OneRmFormula.brzycki), closeTo(112.5, 1e-9));
    });
    test('Lander:100kg×5 = 100×100/(101.3−13.35615)', () {
      expect(
        calculateOneRepMax(weight: 100, reps: 5, formula: OneRmFormula.lander),
        closeTo(100 * 100 / (101.3 - 2.67123 * 5), 1e-9),
      );
    });
    test('預設 Epley 不變:100kg×5 ≈ 116.67', () {
      expect(calculateOneRepMax(weight: 100, reps: 5), closeTo(100 * (1 + 5 / 30), 1e-9));
    });
    test('reps<=1 三公式皆回傳原重量', () {
      for (final f in OneRmFormula.values) {
        expect(calculateOneRepMax(weight: 80, reps: 1, formula: f), 80);
      }
    });
    test('分母<=0(reps 40)時 Brzycki/Lander 退回 Epley,不出無限大或負值', () {
      final epley = calculateOneRepMax(weight: 50, reps: 40);
      expect(calculateOneRepMax(weight: 50, reps: 40, formula: OneRmFormula.brzycki), epley);
      expect(calculateOneRepMax(weight: 50, reps: 40, formula: OneRmFormula.lander), epley);
    });
  });
}
