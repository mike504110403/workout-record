import SwiftUI

struct AddSetSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    
    let exerciseName: String
    let setNumber: Int
    let previousWeight: Double?  // 前一組的重量
    let previousReps: Int?       // 前一組的次數
    let onSave: (Double, Int, Double?, Int) -> Void  // 添加 restSeconds 參數
    
    @State private var weight: String = ""
    @State private var reps: String = ""
    @State private var rpe: String = ""
    @State private var isWarmup: Bool = false
    @State private var restSeconds: Int
    @State private var showRestTimerToggle: Bool = true
    
    init(exerciseName: String, setNumber: Int, previousWeight: Double? = nil, previousReps: Int? = nil, onSave: @escaping (Double, Int, Double?, Int) -> Void) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.previousWeight = previousWeight
        self.previousReps = previousReps
        self.onSave = onSave
        
        // 從全局設定讀取預設休息時間
        self._restSeconds = State(initialValue: GlobalSettingsManager.shared.defaultRestTime)
        
        // 設置預設值 - 根據當前單位轉換顯示
        if let prevWeight = previousWeight {
            let displayWeight = WeightFormatter.shared.convert(prevWeight, to: GlobalSettingsManager.shared.weightUnit)
            self._weight = State(initialValue: String(format: "%.1f", displayWeight))
        }
        if let prevReps = previousReps {
            self._reps = State(initialValue: "\(prevReps)")
        }
    }
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case weight, reps, rpe
    }
    
    var calculatedVolume: Double {
        guard let w = Double(weight), let r = Int(reps) else { return 0 }
        return w * Double(r)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exerciseName)
                        .font(.headline)
                    
                    Text("第 \(setNumber) 組")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Section("組數資料") {
                    HStack {
                        Text("重量")
                            .frame(width: 60, alignment: .leading)
                        
                        TextField("0", text: $weight)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .weight)
                            .font(.title3)
                            .multilineTextAlignment(.trailing)
                        
                        Text(globalSettings.weightUnit.symbol)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("次數")
                            .frame(width: 60, alignment: .leading)
                        
                        TextField("0", text: $reps)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .reps)
                            .font(.title3)
                            .multilineTextAlignment(.trailing)
                        
                        Text("次")
                            .foregroundColor(.secondary)
                    }
                    
                    if calculatedVolume > 0 {
                        HStack {
                            Text("容量")
                                .frame(width: 60, alignment: .leading)
                            
                            Spacer()
                            
                            Text(globalSettings.formatWeight(calculatedVolume))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Section("進階選項") {
                    HStack {
                        Text("RPE")
                            .frame(width: 60, alignment: .leading)
                        
                        TextField("選填", text: $rpe)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .rpe)
                            .multilineTextAlignment(.trailing)
                        
                        Text("/ 10")
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("暖身組", isOn: $isWarmup)
                    
                    if !isWarmup {
                        Stepper("休息時間: \(restSeconds) 秒", value: $restSeconds, in: 0...300, step: 15)
                        
                        Toggle("自動開始休息計時", isOn: $showRestTimerToggle)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("記錄組數")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("儲存") {
                        saveSet()
                    }
                    .disabled(weight.isEmpty || reps.isEmpty)
                    .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        
                        Button("完成") {
                            focusedField = nil
                        }
                    }
                }
            }
            .onAppear {
                focusedField = .weight
            }
        }
    }
    
    private func saveSet() {
        guard let weightValue = Double(weight),
              let repsValue = Int(reps) else {
            return
        }
        
        // 將輸入的重量轉換回公斤（數據庫始終以公斤存儲）
        let weightInKg = WeightFormatter.shared.convertToKg(weightValue, from: globalSettings.weightUnit)
        
        let rpeValue = Double(rpe)
        // 傳遞用戶選擇的休息時間
        onSave(weightInKg, repsValue, rpeValue, restSeconds)
        dismiss()
    }
}

#Preview {
    AddSetSheet(
        exerciseName: "槓鈴臥推",
        setNumber: 1,
        onSave: { weight, reps, rpe, restSeconds in
            print("Weight: \(weight), Reps: \(reps), RPE: \(rpe ?? 0), Rest: \(restSeconds)s")
        }
    )
}

