import SwiftUI

/// 手動新增三項記錄的表單
struct AddPowerLiftRecordSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    
    let lift: PowerLift
    let onSave: (PowerLiftRecord) -> Void
    
    @State private var weight: String = ""
    @State private var reps: String = "1"
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本資訊")) {
                    // 三項動作
                    HStack {
                        Text("動作")
                        Spacer()
                        Text(lift.rawValue)
                            .foregroundColor(.secondary)
                    }
                    
                    // 重量
                    HStack {
                        Text("重量")
                        Spacer()
                        TextField("重量", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(globalSettings.weightUnit.symbol)
                            .foregroundColor(.secondary)
                    }
                    
                    // 次數
                    HStack {
                        Text("次數")
                        Spacer()
                        TextField("次數", text: $reps)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("次")
                            .foregroundColor(.secondary)
                    }
                    
                    // 日期
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }
                
                Section(header: Text("備註（選填）")) {
                    TextEditor(text: $note)
                        .frame(height: 100)
                }
                
                // 計算的 1RM
                if let weightValue = Double(weight), weightValue > 0,
                   let repsValue = Int(reps), repsValue > 0 {
                    Section(header: Text("估算 1RM")) {
                        HStack {
                            Text("推估最大重量")
                            Spacer()
                            Text(WeightFormatter.format(
                                OneRMCalculator.calculate(
                                    weight: WeightFormatter.toKilograms(weightValue, from: globalSettings.weightUnit),
                                    reps: repsValue
                                ),
                                unit: globalSettings.weightUnit
                            ))
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("新增\(lift.rawValue)記錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveRecord()
                    }
                    .disabled(weight.isEmpty || reps.isEmpty)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("完成") {
                            isFocused = false
                        }
                    }
                }
            }
            .alert("錯誤", isPresented: $showError) {
                Button("確定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveRecord() {
        guard let weightValue = Double(weight),
              let repsValue = Int(reps),
              weightValue > 0,
              repsValue > 0 else {
            errorMessage = "請輸入有效的重量和次數"
            showError = true
            return
        }
        
        // 轉換重量為公斤（內部統一使用公斤）
        let weightInKg = WeightFormatter.toKilograms(weightValue, from: globalSettings.weightUnit)
        
        // 計算 1RM
        let oneRM = OneRMCalculator.calculate(weight: weightInKg, reps: repsValue)
        
        // 創建記錄
        let userId = DataMigrationService.getCurrentUserId()
        let record = PowerLiftRecord(
            userId: userId,
            lift: lift,
            weight: weightInKg,
            reps: repsValue,
            oneRepMax: oneRM,
            achievedAt: date,
            note: note.isEmpty ? nil : note
        )
        
        onSave(record)
        dismiss()
    }
}

#Preview {
    AddPowerLiftRecordSheet(
        lift: .benchPress,
        onSave: { _ in }
    )
}

