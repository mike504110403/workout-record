import SwiftUI

struct QuickAddExerciseSheet: View {
    @ObservedObject var customExerciseVM: CustomExerciseViewModel
    @Environment(\.dismiss) private var dismiss
    
    let onExerciseCreated: (Exercise) -> Void
    
    @State private var name = ""
    @State private var type: Exercise.ExerciseType = .freeWeight
    @State private var primaryMuscleGroup: Exercise.PrimaryMuscleGroup? = nil
    @State private var movementPattern: Exercise.MovementPattern? = nil
    @State private var nameError: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("動作名稱", text: $name)
                            .onChange(of: name) { _, _ in
                                nameError = nil
                            }
                        
                        if let error = nameError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    Picker("類型", selection: $type) {
                        ForEach(Exercise.ExerciseType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: iconForType(type))
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                }
                
                Section("分類（選填）") {
                    Picker("主要肌群", selection: $primaryMuscleGroup) {
                        Text("未選擇").tag(nil as Exercise.PrimaryMuscleGroup?)
                        ForEach(Exercise.PrimaryMuscleGroup.allCases, id: \.self) { group in
                            Text(group.displayName).tag(group as Exercise.PrimaryMuscleGroup?)
                        }
                    }
                    
                    Picker("動作模式", selection: $movementPattern) {
                        Text("未選擇").tag(nil as Exercise.MovementPattern?)
                        ForEach(Exercise.MovementPattern.allCases, id: \.self) { pattern in
                            HStack {
                                Image(systemName: pattern.icon)
                                Text(pattern.displayName)
                            }
                            .tag(pattern as Exercise.MovementPattern?)
                        }
                    }
                }
                
                Section {
                    Text("快速創建後可在「設定 > 自定義動作」中編輯詳細資訊")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("快速新增動作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("創建並使用") {
                        createAndUseExercise()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func iconForType(_ type: Exercise.ExerciseType) -> String {
        switch type {
        case .freeWeight: return "dumbbell.fill"
        case .machine: return "gearshape.fill"
        case .bodyweight: return "figure.walk"
        }
    }
    
    private func createAndUseExercise() {
        // 驗證名稱
        if let error = customExerciseVM.validateExerciseName(name) {
            nameError = error
            return
        }
        
        // 創建動作
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultCategory = MockData.categories.first ?? ExerciseCategory(
            name: "其他",
            nameEn: "Other",
            displayOrder: 99
        )
        
        customExerciseVM.createExercise(
            name: trimmedName,
            type: type,
            categoryId: defaultCategory.id,
            primaryMuscleGroup: primaryMuscleGroup,
            movementPattern: movementPattern,
            description: nil
        )
        
        // 取得剛創建的動作
        if let newExercise = customExerciseVM.customExercises.last {
            // 回調並關閉
            onExerciseCreated(newExercise)
        } else {
            dismiss()
        }
    }
}

#Preview {
    QuickAddExerciseSheet(
        customExerciseVM: CustomExerciseViewModel(),
        onExerciseCreated: { _ in }
    )
}

