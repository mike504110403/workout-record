// 1RM(單次最大重量)估算。對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Utils/OneRMCalculator.swift` +
// `Models/User.swift`(`OneRMFormula.calculate`)三公式:Epley/Brzycki/Lander,
// 使用者在偏好設定選擇(oneRmFormulaProvider),預設 Epley。
//
// 邊界處理照 iOS `OneRMCalculator.calculate`:reps <= 1 直接回傳 weight。
// iOS 未防 Brzycki/Lander 分母 <= 0(reps 約 37 以上);此處分母 <= 0 時退回
// Epley,避免除以零或負值。
import '../settings/preferences/one_rm_formula_preference.dart';

double calculateOneRepMax({
  required double weight,
  required int reps,
  OneRmFormula formula = OneRmFormula.epley,
}) {
  if (reps <= 1) return weight;
  final r = reps.toDouble();
  double epley() => weight * (1 + r / 30.0);
  switch (formula) {
    case OneRmFormula.epley:
      return epley();
    case OneRmFormula.brzycki:
      final d = 37.0 - r;
      return d > 0 ? weight * (36.0 / d) : epley();
    case OneRmFormula.lander:
      final d = 101.3 - 2.67123 * r;
      return d > 0 ? weight * (100.0 / d) : epley();
  }
}
