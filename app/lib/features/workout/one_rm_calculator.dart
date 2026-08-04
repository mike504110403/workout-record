// 1RM(單次最大重量)估算。對照 iOS
// `ios/WorkoutRecord/WorkoutRecord/Sources/Utils/OneRMCalculator.swift` +
// `Models/User.swift:59-83`(`OneRMFormula`)——只移植 PR 偵測實際會用到的
// Epley 公式(iOS `User.OneRMFormula` 預設值,`WorkoutViewModel.swift:261`
// 的 PR 偵測固定呼叫 `OneRMCalculator.calculate(weight:reps:)` 不帶
// `formula:` 參數,即採用預設的 `.epley`)。Brzycki/Lander 兩個非預設公式
// 沒有任何呼叫路徑會用到(brief 範圍不含 1RM 公式選擇設定),不搬。
//
// 邊界處理照 iOS `OneRMCalculator.calculate`:reps <= 0 時直接回傳 weight
// (原始碼用 `guard reps > 0 else { return weight }`);reps == 1 時 1RM 就是
// 該次重量本身,不套公式(該次已經是單次最大重量)。
double calculateOneRepMax({required double weight, required int reps}) {
  if (reps <= 1) return weight;
  return weight * (1 + reps / 30.0);
}
