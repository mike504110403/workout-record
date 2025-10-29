import SwiftUI
import Combine
import Foundation

/// 增強版計劃模板視圖
struct EnhancedTemplateView: View {
    @StateObject private var viewModel = EnhancedTemplateViewModel()
    @State private var showAddTemplateSheet = false
    @State private var showTemplateDetailSheet = false
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
            VStack {
                // 搜尋欄
                SearchBar(text: $searchText)
                
                // 模板列表
                if viewModel.isLoading {
                        SwiftUI.ProgressView()
                            .overlay(
                                Text("載入中...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredTemplates.isEmpty {
                    EmptyTemplatesView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredTemplates) { template in
                                EnhancedTemplateCard(template: template) {
                                    selectedTemplate = template
                                    showTemplateDetailSheet = true
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("訓練模板")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddTemplateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddTemplateSheet) {
                AddTemplateSheet { template in
                    viewModel.addTemplate(template)
                }
                .dismissOnTapSheet {
                    showAddTemplateSheet = false
                }
            }
            .sheet(isPresented: $showTemplateDetailSheet) {
                if let template = selectedTemplate {
                    TemplateDetailView(template: template)
                        .dismissOnTapSheet {
                            showTemplateDetailSheet = false
                        }
                }
            }
            .onAppear {
                viewModel.loadTemplates()
            }
        }
    }
    
    private var filteredTemplates: [WorkoutTemplate] {
        if searchText.isEmpty {
            return viewModel.templates
        } else {
            return viewModel.templates.filter { template in
                template.name.localizedCaseInsensitiveContains(searchText) ||
                (template.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
}

// MARK: - Supporting Views

// SearchBar 定義已移至 Views/Components/SearchBarView.swift

struct EmptyTemplatesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("尚無訓練模板")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("點擊右上角 + 號新增模板")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EnhancedTemplateCard: View {
    let template: WorkoutTemplate
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // 標題區域
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(template.isSystem ? "系統模板" : "自定義模板")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(template.estimatedDuration) 分鐘")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("\(template.exercises.count) 個動作")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 描述
                if let description = template.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // 動作預覽
                if !template.exercises.isEmpty {
                    HStack {
                        Text("動作預覽:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            ForEach(template.exercises.prefix(3), id: \.id) { exercise in
                                Text(exercise.exercise?.name ?? "未知動作")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            if template.exercises.count > 3 {
                                Text("+\(template.exercises.count - 3)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // 統計資訊
                HStack(spacing: 20) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar")
                            .font(.caption)
                        Text("\(Int(template.estimatedVolume)) kg")
                            .font(.caption)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "list.number")
                            .font(.caption)
                        Text("\(template.totalSets) 組")
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    // 難度標籤已移除，因為 WorkoutTemplate 沒有 difficulty 屬性
                }
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Template Sheet

struct AddTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (WorkoutTemplate) -> Void
    
    @State private var templateName = ""
    @State private var templateDescription = ""
    @State private var templateCategory: WorkoutCategory = .strength
    @State private var templateDifficulty: WorkoutDifficulty = .beginner
    @State private var estimatedDuration = 60
    @State private var exercises: [TemplateExercise] = []
    @State private var showExercisePicker = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("基本資訊") {
                    TextField("模板名稱", text: $templateName)
                    
                    TextField("描述（選填）", text: $templateDescription, axis: .vertical)
                        .lineLimit(3...6)
                    
                    Picker("類別", selection: $templateCategory) {
                        ForEach(WorkoutCategory.allCases, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    
                    Picker("難度", selection: $templateDifficulty) {
                        ForEach(WorkoutDifficulty.allCases, id: \.self) { difficulty in
                            Text(difficulty.displayName).tag(difficulty)
                        }
                    }
                    
                    Stepper("預估時長: \(estimatedDuration) 分鐘", value: $estimatedDuration, in: 15...180, step: 15)
                }
                
                Section("訓練動作") {
                    ForEach(exercises) { exercise in
                        TemplateExerciseRow(exercise: exercise) { updatedExercise in
                            if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
                                exercises[index] = updatedExercise
                            }
                        }
                    }
                    .onDelete(perform: deleteExercise)
                    
                    Button {
                        showExercisePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("新增動作")
                        }
                    }
                }
            }
            .navigationTitle("新增模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("儲存") {
                        saveTemplate()
                    }
                    .disabled(templateName.isEmpty || exercises.isEmpty)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView { exercise in
                    let templateExercise = TemplateExercise(
                        exerciseId: exercise.id,
                        name: exercise.name,
                        sets: [
                            TemplateSet(weight: 0, reps: 10, restSeconds: 90)
                        ]
                    )
                    exercises.append(templateExercise)
                }
                .dismissOnTapSheet {
                    showExercisePicker = false
                }
            }
        }
    }
    
    private func deleteExercise(at offsets: IndexSet) {
        exercises.remove(atOffsets: offsets)
    }
    
    private func saveTemplate() {
        // 轉換 TemplateExercise 為 WorkoutTemplateExercise
        let workoutTemplateExercises = exercises.map { templateExercise in
            WorkoutTemplateExercise(
                templateId: UUID(), // 暫時使用 UUID()，實際應該使用模板 ID
                exerciseId: templateExercise.exerciseId,
                exercise: nil, // 需要從 ExerciseRepository 獲取
                orderIndex: 0,
                suggestedSets: templateExercise.sets.count,
                suggestedReps: templateExercise.sets.first?.reps ?? 10,
                note: nil,
                createdAt: Date()
            )
        }
        
        let template = WorkoutTemplate(
            userId: DataMigrationService.getCurrentUserId(),
            name: templateName,
            description: templateDescription.isEmpty ? nil : templateDescription,
            isSystem: false,
            exercises: workoutTemplateExercises,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        onSave(template)
        dismiss()
    }
    
    private func calculateEstimatedVolume() -> Double {
        return exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { setTotal, set in
                setTotal + (set.weight * Double(set.reps))
            }
        }
    }
}

// MARK: - Template Detail View

struct TemplateDetailView: View {
    let template: WorkoutTemplate
    @Environment(\.dismiss) private var dismiss
    @State private var showStartWorkoutSheet = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 模板標題
                    VStack(alignment: .leading, spacing: 8) {
                        Text(template.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        HStack {
                            Text(template.isSystem ? "系統模板" : "自定義模板")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // 難度標籤已移除，因為 WorkoutTemplate 沒有 difficulty 屬性
                        }
                    }
                    
                    // 描述
                    if let description = template.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // 模板統計
                    HStack(spacing: 20) {
                        StatItem(icon: "clock", label: "預估時長", value: "\(template.estimatedDuration)", unit: "分鐘")
                        StatItem(icon: "figure.strengthtraining.traditional", label: "動作數量", value: "\(template.exercises.count)", unit: "個")
                        StatItem(icon: "list.number", label: "總組數", value: "\(template.totalSets)", unit: "組")
                        StatItem(icon: "chart.bar", label: "預估容量", value: "\(Int(template.estimatedVolume))", unit: "kg")
                    }
                    
                    // 動作列表
                    VStack(alignment: .leading, spacing: 12) {
                        Text("訓練動作")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        ForEach(template.exercises) { exercise in
                            WorkoutTemplateExerciseDetailCard(exercise: exercise)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("模板詳情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("關閉") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("開始訓練") {
                        showStartWorkoutSheet = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showStartWorkoutSheet) {
                StartWorkoutFromTemplateSheet(template: template)
                    .dismissOnTapSheet {
                        showStartWorkoutSheet = false
                    }
            }
        }
    }
}

// MARK: - Supporting Components

struct TemplateExerciseRow: View {
    let exercise: TemplateExercise
    let onUpdate: (TemplateExercise) -> Void
    
    @State private var sets: [TemplateSet]
    
    init(exercise: TemplateExercise, onUpdate: @escaping (TemplateExercise) -> Void) {
        self.exercise = exercise
        self.onUpdate = onUpdate
        self._sets = State(initialValue: exercise.sets)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.name)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(sets.indices, id: \.self) { index in
                HStack {
                    Text("組 \(index + 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                    
                    TextField("重量", value: $sets[index].weight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    
                    Text("kg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("次數", value: $sets[index].reps, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    
                    Text("次")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button {
                        sets.remove(at: index)
                        updateExercise()
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundColor(.red)
                    }
                }
            }
            
            Button {
                sets.append(TemplateSet(weight: 0, reps: 10, restSeconds: 90))
                updateExercise()
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("新增組數")
                }
                .font(.caption)
            }
        }
        .onChange(of: sets) { _ in
            updateExercise()
        }
    }
    
    private func updateExercise() {
        let updatedExercise = TemplateExercise(
            id: exercise.id,
            exerciseId: exercise.exerciseId,
            name: exercise.name,
            sets: sets
        )
        onUpdate(updatedExercise)
    }
}

// MARK: - WorkoutTemplateExerciseDetailCard
struct WorkoutTemplateExerciseDetailCard: View {
    let exercise: WorkoutTemplateExercise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.exercise?.name ?? "未知動作")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack {
                Text("建議組數: \(exercise.suggestedSets ?? 0)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("建議次數: \(exercise.suggestedReps ?? 0)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let note = exercise.note, !note.isEmpty {
                Text("備註: \(note)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct TemplateExerciseDetailCard: View {
    let exercise: TemplateExercise
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.name)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(exercise.sets.indices, id: \.self) { index in
                let set = exercise.sets[index]
                HStack {
                    Text("組 \(index + 1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                    
                    Text("\(Int(set.weight)) kg")
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    
                    Text("× \(set.reps) 次")
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                    
                    if let rest = set.restSeconds {
                        Text("休息 \(rest) 秒")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Data Models

// WorkoutTemplate 定義已移至 Models/Workout.swift

struct TemplateExercise: Identifiable, Codable {
    let id: UUID
    let exerciseId: UUID
    let name: String
    var sets: [TemplateSet]
    
    init(id: UUID = UUID(), exerciseId: UUID, name: String, sets: [TemplateSet]) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.sets = sets
    }
}

struct TemplateSet: Identifiable, Codable, Equatable {
    let id: UUID
    var weight: Double
    var reps: Int
    var restSeconds: Int?
    
    init(id: UUID = UUID(), weight: Double, reps: Int, restSeconds: Int?) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.restSeconds = restSeconds
    }
}

enum WorkoutCategory: String, Codable, CaseIterable {
    case strength = "strength"
    case cardio = "cardio"
    case flexibility = "flexibility"
    case mixed = "mixed"
    case powerlifting = "powerlifting"
    case bodybuilding = "bodybuilding"
    
    var displayName: String {
        switch self {
        case .strength: return "肌力訓練"
        case .cardio: return "有氧運動"
        case .flexibility: return "柔軟度"
        case .mixed: return "混合訓練"
        case .powerlifting: return "健力"
        case .bodybuilding: return "健美"
        }
    }
}

enum WorkoutDifficulty: String, Codable, CaseIterable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
    
    var displayName: String {
        switch self {
        case .beginner: return "初級"
        case .intermediate: return "中級"
        case .advanced: return "高級"
        }
    }
    
    var color: Color {
        switch self {
        case .beginner: return .green
        case .intermediate: return .orange
        case .advanced: return .red
        }
    }
}

// MARK: - View Model

@MainActor
class EnhancedTemplateViewModel: ObservableObject {
    @Published var templates: [WorkoutTemplate] = []
    @Published var isLoading = false
    
    func loadTemplates() {
        isLoading = true
        // TODO: 從資料庫載入模板
        // 目前使用模擬資料
        templates = [
            WorkoutTemplate(
                userId: DataMigrationService.getCurrentUserId(),
                name: "胸肌訓練",
                description: "專注於胸肌發展的訓練計劃",
                isSystem: true,
                exercises: [],
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        isLoading = false
    }
    
    func addTemplate(_ template: WorkoutTemplate) {
        templates.append(template)
        // TODO: 儲存到資料庫
    }
    
    func deleteTemplate(_ template: WorkoutTemplate) {
        templates.removeAll { $0.id == template.id }
        // TODO: 從資料庫刪除
    }
}

// MARK: - StartWorkoutFromTemplateSheet
struct StartWorkoutFromTemplateSheet: View {
    let template: WorkoutTemplate
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("開始訓練")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("使用模板：\(template.name)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("此功能正在開發中...")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
            .navigationTitle("開始訓練")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("關閉") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Helper Functions
// 計算函數已移至 WorkoutTemplate 擴展中

#Preview {
    EnhancedTemplateView()
}
