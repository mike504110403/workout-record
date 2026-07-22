import SwiftUI

struct EditExerciseSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var globalSettings = GlobalSettingsManager.shared
    
    let exercise: WorkoutExerciseViewModel
    let onSave: ([EditedSet]) -> Void
    
    @State private var editedSets: [EditedSet]
    
    struct EditedSet: Identifiable {
        let id: UUID
        var weight: String
        var reps: String
        var rpe: String
        
        init(from set: WorkoutSetViewModel) {
            self.id = set.id
            let displayWeight = WeightFormatter.shared.convert(set.weight, to: GlobalSettingsManager.shared.weightUnit)
            self.weight = String(format: "%.1f", displayWeight)
            self.reps = "\(set.reps)"
            self.rpe = set.rpe != nil ? String(format: "%.1f", set.rpe!) : ""
        }
    }
    
    init(exercise: WorkoutExerciseViewModel, onSave: @escaping ([EditedSet]) -> Void) {
        self.exercise = exercise
        self.onSave = onSave
        self._editedSets = State(initialValue: exercise.sets.map { EditedSet(from: $0) })
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exercise.exerciseName)
                        .font(.title2)
                        .fontWeight(.bold)
                } header: {
                    Text("動作")
                }
                
                Section {
                    ForEach($editedSets) { $set in
                        VStack(spacing: 12) {
                            HStack {
                                Text("第 \(editedSets.firstIndex(where: { $0.id == set.id })! + 1) 組")
                                    .font(.headline)
                                Spacer()
                            }
                            
                            HStack {
                                Text("重量")
                                    .frame(width: 60, alignment: .leading)
                                
                                TextField("0", text: $set.weight)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                
                                Text(globalSettings.weightUnit.symbol)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("次數")
                                    .frame(width: 60, alignment: .leading)
                                
                                TextField("0", text: $set.reps)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                
                                Text("次")
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("RPE")
                                    .frame(width: 60, alignment: .leading)
                                
                                TextField("選填", text: $set.rpe)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                
                                Text("/ 10")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("組數資料")
                }
            }
            .navigationTitle("編輯動作")
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
                        onSave(editedSets)
                        dismiss()
                    }
                }
            }
        }
    }
}

