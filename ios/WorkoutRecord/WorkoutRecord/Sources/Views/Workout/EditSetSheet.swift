import SwiftUI

struct EditSetSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    
    let set: WorkoutSetViewModel
    let onSave: (Double, Int, Double?) -> Void
    
    @State private var weight: String
    @State private var reps: String
    @State private var rpe: String
    
    init(set: WorkoutSetViewModel, onSave: @escaping (Double, Int, Double?) -> Void) {
        self.set = set
        self.onSave = onSave
        
        let displayWeight = WeightFormatter.shared.convert(set.weight, to: GlobalSettingsManager.shared.weightUnit)
        self._weight = State(initialValue: String(format: "%.1f", displayWeight))
        self._reps = State(initialValue: "\(set.reps)")
        
        if let rpeValue = set.rpe {
            self._rpe = State(initialValue: String(format: "%.1f", rpeValue))
        } else {
            self._rpe = State(initialValue: "")
        }
    }
    
    var calculatedVolume: Double {
        guard let w = Double(weight), let r = Int(reps) else { return 0 }
        return w * Double(r)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("組數資料") {
                    HStack {
                        Text("重量")
                            .frame(width: 60, alignment: .leading)
                        
                        TextField("0", text: $weight)
                            .keyboardType(.decimalPad)
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
                            .multilineTextAlignment(.trailing)
                        
                        Text("/ 10")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("編輯組數")
            .navigationBarTitleDisplayMode(.inline)
            .dismissKeyboardOnInteraction()
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
                }
            }
        }
    }
    
    private func saveSet() {
        guard let weightValue = Double(weight),
              let repsValue = Int(reps) else { return }
        
        let rpeValue = Double(rpe)
        
        // 如果單位是磅，需要轉換回公斤
        let weightInKg = WeightFormatter.shared.convertToKg(weightValue, from: globalSettings.weightUnit)
        
        onSave(weightInKg, repsValue, rpeValue)
        dismiss()
    }
}

