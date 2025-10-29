import SwiftUI

struct CustomExerciseFormView: View {
    @ObservedObject var viewModel: CustomExerciseViewModel
    @Environment(\.dismiss) private var dismiss
    
    let mode: FormMode
    
    @State private var name: String
    @State private var type: Exercise.ExerciseType
    @State private var selectedCategory: ExerciseCategory?
    @State private var primaryMuscleGroup: Exercise.PrimaryMuscleGroup?
    @State private var movementPattern: Exercise.MovementPattern?
    @State private var selectedMuscles: Set<DetailedMuscleGroup> = []  // 多選肌群
    @State private var description: String
    @State private var nameError: String?
    @State private var showMuscleGroupPicker = false  // 顯示肌群選擇器
    
    enum FormMode: Identifiable {
        case create
        case edit(Exercise)
        
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let exercise): return "edit-\(exercise.id)"
            }
        }
        
        var title: String {
            switch self {
            case .create: return "新增動作"
            case .edit: return "編輯動作"
            }
        }
    }
    
    init(viewModel: CustomExerciseViewModel, mode: FormMode) {
        self.viewModel = viewModel
        self.mode = mode
        
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _type = State(initialValue: .freeWeight)
            _primaryMuscleGroup = State(initialValue: nil)
            _movementPattern = State(initialValue: nil)
            _selectedMuscles = State(initialValue: [])
            _description = State(initialValue: "")
            _selectedCategory = State(initialValue: MockData.categories.first)
        case .edit(let exercise):
            _name = State(initialValue: exercise.name)
            _type = State(initialValue: exercise.type)
            _primaryMuscleGroup = State(initialValue: exercise.primaryMuscleGroup)
            _movementPattern = State(initialValue: exercise.movementPattern)
            _selectedMuscles = State(initialValue: Set(exercise.targetMuscles))
            _description = State(initialValue: exercise.description ?? "")
            _selectedCategory = State(initialValue: exercise.category ?? MockData.categories.first)
        }
    }
    
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
                    
                    Picker("動作類型", selection: $type) {
                        ForEach(Exercise.ExerciseType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: iconForType(type))
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    
                    Picker("分類", selection: $selectedCategory) {
                        ForEach(MockData.categories) { category in
                            Text(category.name).tag(category as ExerciseCategory?)
                        }
                    }
                    .onChange(of: selectedCategory) { _, newCategory in
                        // 根據分類自動設置主要肌群
                        if let category = newCategory {
                            primaryMuscleGroup = mapCategoryToPrimaryMuscleGroup(category.name)
                            // 清空已選擇的詳細肌群
                            selectedMuscles.removeAll()
                        }
                    }
                }
                
                Section("動作分析") {
                    Picker("主要肌群", selection: $primaryMuscleGroup) {
                        Text("未選擇").tag(nil as Exercise.PrimaryMuscleGroup?)
                        ForEach(Exercise.PrimaryMuscleGroup.allCases, id: \.self) { group in
                            Text(group.displayName).tag(group as Exercise.PrimaryMuscleGroup?)
                        }
                    }
                    .onChange(of: primaryMuscleGroup) { _, newValue in
                        // 當主要肌群改變時，清空已選擇的詳細肌群
                        selectedMuscles.removeAll()
                    }
                    
                    // 目標肌群（多選）
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            showMuscleGroupPicker = true
                        }) {
                            HStack {
                                Text("目標肌群")
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedMuscles.isEmpty {
                                    Text("點擊選擇")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(selectedMuscles.count) 個")
                                        .foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // 顯示已選擇的肌群
                        if !selectedMuscles.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(selectedMuscles).sorted(by: { $0.displayName < $1.displayName }), id: \.self) { muscle in
                                        HStack(spacing: 4) {
                                            Text(muscle.displayName)
                                                .font(.caption)
                                            Button(action: {
                                                selectedMuscles.remove(muscle)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(muscle.color.opacity(0.2))
                                        .foregroundColor(muscle.color)
                                        .cornerRadius(12)
                                    }
                                }
                            }
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
                
                Section("說明（選填）") {
                    TextEditor(text: $description)
                        .frame(height: 100)
                }
                
                if case .edit = mode {
                    Section {
                        Button(role: .destructive) {
                            deleteExercise()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("刪除動作")
                            }
                        }
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        saveExercise()
                    }
                }
            }
            .sheet(isPresented: $showMuscleGroupPicker) {
                MuscleGroupPickerView(
                    selectedCategory: selectedCategory,
                    primaryMuscleGroup: primaryMuscleGroup,
                    selectedMuscles: $selectedMuscles
                )
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
    
    private func saveExercise() {
        // 驗證名稱
        if let error = viewModel.validateExerciseName(name) {
            nameError = error
            return
        }
        
        guard let category = selectedCategory else {
            nameError = "請選擇分類"
            return
        }
        
        switch mode {
        case .create:
            viewModel.createExercise(
                name: name,
                type: type,
                categoryId: category.id,
                targetMuscles: Array(selectedMuscles),
                primaryMuscleGroup: primaryMuscleGroup,
                movementPattern: movementPattern,
                description: description.isEmpty ? nil : description
            )
        case .edit(let exercise):
            var updatedExercise = exercise
            updatedExercise.name = name
            updatedExercise.type = type
            updatedExercise.targetMuscles = Array(selectedMuscles)
            updatedExercise.primaryMuscleGroup = primaryMuscleGroup
            updatedExercise.movementPattern = movementPattern
            updatedExercise.description = description.isEmpty ? nil : description
            viewModel.updateExercise(updatedExercise)
        }
        
        dismiss()
    }
    
    private func deleteExercise() {
        if case .edit(let exercise) = mode {
            viewModel.deleteExercise(id: exercise.id)
            dismiss()
        }
    }
    
    /// 根據分類名稱映射到主要肌群
    private func mapCategoryToPrimaryMuscleGroup(_ categoryName: String) -> Exercise.PrimaryMuscleGroup? {
        switch categoryName {
        case "胸部", "Chest":
            return .chest
        case "背部", "Back":
            return .back
        case "腿部", "Legs":
            return .legs
        case "肩部", "Shoulders":
            return .shoulders
        case "手臂", "Arms":
            return .arms
        case "核心", "Core":
            return .core
        case "臀部", "Glutes":
            return .glutes
        default:
            return nil
        }
    }
}

#Preview("Create") {
    CustomExerciseFormView(
        viewModel: CustomExerciseViewModel(),
        mode: .create
    )
}

#Preview("Edit") {
    let exercise = Exercise(
        name: "史密斯臥推",
        categoryId: UUID(),
        type: .machine,
        muscleGroups: ["胸大肌"],
        primaryMuscleGroup: .chest,
        movementPattern: .push,
        description: "使用史密斯機進行臥推",
        isSystem: false,
        userId: UUID()
    )
    
    return CustomExerciseFormView(
        viewModel: CustomExerciseViewModel(),
        mode: .edit(exercise)
    )
}

