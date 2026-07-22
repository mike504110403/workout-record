import Foundation
import Combine

@MainActor
class WorkoutTemplateViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var templates: [TemplateInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Computed Properties
    var systemTemplates: [TemplateInfo] {
        templates.filter { $0.isSystem }
    }
    
    var userTemplates: [TemplateInfo] {
        templates.filter { !$0.isSystem }
    }
    
    // MARK: - Private Properties
    private let repository = TemplateRepository()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadTemplates()
    }
    
    // MARK: - Public Methods
    func createTemplate(name: String, description: String?, exercises: [Exercise]) {
        let userId = DataMigrationService.getCurrentUserId()
        let templateExercises = exercises.map { exercise in
            TemplateInfo.TemplateExercise(
                id: exercise.id,
                exercise: exercise,
                suggestedSets: 4,
                suggestedReps: 10
            )
        }
        
        let template = TemplateInfo(
            id: UUID(),
            name: name,
            description: description,
            exercises: templateExercises,
            isSystem: false
        )
        
        do {
            _ = try repository.create(template: template, userId: userId)
            loadTemplates() // 重新加載
        } catch {
            errorMessage = "創建模板失敗: \(error.localizedDescription)"
            print("❌ 創建模板失敗: \(error)")
        }
    }
    
    @Published var editingTemplate: TemplateInfo?
    @Published var showEditSheet = false
    
    func editTemplate(_ template: TemplateInfo) {
        editingTemplate = template
        showEditSheet = true
    }
    
    func updateTemplate(id: UUID, name: String, description: String?, exercises: [Exercise]) {
        let templateExercises = exercises.map { exercise in
            TemplateInfo.TemplateExercise(
                id: exercise.id,
                exercise: exercise,
                suggestedSets: 4,
                suggestedReps: 10
            )
        }
        
        let updatedTemplate = TemplateInfo(
            id: id,
            name: name,
            description: description,
            exercises: templateExercises,
            isSystem: false
        )
        
        do {
            try repository.update(template: updatedTemplate)
            loadTemplates() // 重新加載
        } catch {
            errorMessage = "更新模板失敗: \(error.localizedDescription)"
            print("❌ 更新模板失敗: \(error)")
        }
    }
    
    func deleteTemplate(_ template: TemplateInfo) {
        do {
            try repository.delete(id: template.id)
            loadTemplates()
        } catch {
            errorMessage = "刪除模板失敗: \(error.localizedDescription)"
            print("❌ 刪除模板失敗: \(error)")
        }
    }
    
    func useTemplate(_ template: TemplateInfo) {
        // Send notification to start workout with template
        NotificationCenter.default.post(
            name: .startWorkoutFromTemplate,
            object: nil,
            userInfo: ["template": template]
        )
    }
    
    func refresh() {
        loadTemplates()
    }
    
    // MARK: - Private Methods
    
    private func loadTemplates() {
        isLoading = true
        errorMessage = nil
        
        let userId = DataMigrationService.getCurrentUserId()
        
        do {
            templates = try repository.fetchAll(userId: userId)
            print("✅ 載入 \(templates.count) 個模板")
        } catch {
            errorMessage = "載入模板失敗: \(error.localizedDescription)"
            print("❌ 載入模板失敗: \(error)")
            templates = []
        }
        
        isLoading = false
    }
    
    // MARK: - Deprecated Mock Methods (保留以備測試)
    #if DEBUG
    private func loadMockTemplates() {
        // Helper function to create mock exercise
        func mockExercise(name: String) -> Exercise {
            Exercise(
                id: UUID(),
                name: name,
                categoryId: UUID(),
                type: .freeWeight,
                isSystem: true
            )
        }
        
        // Helper function to create template exercise
        func mockTemplateExercise(name: String, sets: Int? = nil, reps: Int? = nil) -> TemplateInfo.TemplateExercise {
            TemplateInfo.TemplateExercise(
                id: UUID(),
                exercise: mockExercise(name: name),
                suggestedSets: sets,
                suggestedReps: reps
            )
        }
        
        templates = [
            // System templates
            TemplateInfo(
                id: UUID(),
                name: "PPL - Push (推)",
                description: "胸、肩、三頭訓練",
                exercises: [
                    mockTemplateExercise(name: "槓鈴臥推", sets: 4, reps: 8),
                    mockTemplateExercise(name: "上斜啞鈴臥推", sets: 4, reps: 10),
                    mockTemplateExercise(name: "肩推", sets: 4, reps: 10),
                    mockTemplateExercise(name: "側平舉", sets: 3, reps: 12),
                    mockTemplateExercise(name: "三頭下壓", sets: 3, reps: 12)
                ],
                isSystem: true
            ),
            TemplateInfo(
                id: UUID(),
                name: "PPL - Pull (拉)",
                description: "背、二頭訓練",
                exercises: [
                    mockTemplateExercise(name: "硬舉", sets: 3, reps: 5),
                    mockTemplateExercise(name: "引體向上", sets: 4, reps: 8),
                    mockTemplateExercise(name: "槓鈴划船", sets: 4, reps: 10),
                    mockTemplateExercise(name: "坐姿划船", sets: 3, reps: 12),
                    mockTemplateExercise(name: "槓鈴彎舉", sets: 3, reps: 10)
                ],
                isSystem: true
            ),
            TemplateInfo(
                id: UUID(),
                name: "PPL - Legs (腿)",
                description: "腿部完整訓練",
                exercises: [
                    mockTemplateExercise(name: "深蹲", sets: 4, reps: 8),
                    mockTemplateExercise(name: "羅馬尼亞硬舉", sets: 4, reps: 10),
                    mockTemplateExercise(name: "腿推機", sets: 4, reps: 12),
                    mockTemplateExercise(name: "腿彎舉", sets: 3, reps: 12),
                    mockTemplateExercise(name: "提踵", sets: 4, reps: 15)
                ],
                isSystem: true
            ),
            TemplateInfo(
                id: UUID(),
                name: "上肢訓練",
                description: "上半身完整訓練",
                exercises: [
                    mockTemplateExercise(name: "臥推", sets: 4, reps: 8),
                    mockTemplateExercise(name: "划船", sets: 4, reps: 10),
                    mockTemplateExercise(name: "肩推", sets: 3, reps: 10),
                    mockTemplateExercise(name: "二頭彎舉", sets: 3, reps: 12),
                    mockTemplateExercise(name: "三頭下壓", sets: 3, reps: 12)
                ],
                isSystem: true
            ),
            TemplateInfo(
                id: UUID(),
                name: "全身訓練",
                description: "適合初學者的全身訓練",
                exercises: [
                    mockTemplateExercise(name: "深蹲", sets: 3, reps: 10),
                    mockTemplateExercise(name: "臥推", sets: 3, reps: 10),
                    mockTemplateExercise(name: "硬舉", sets: 3, reps: 8),
                    mockTemplateExercise(name: "引體向上", sets: 3, reps: 8),
                    mockTemplateExercise(name: "肩推", sets: 3, reps: 10)
                ],
                isSystem: true
            )
        ]
    }
    #endif
}

// MARK: - Notification Names
extension Notification.Name {
    static let startWorkoutFromTemplate = Notification.Name("startWorkoutFromTemplate")
    static let switchToWorkoutTab = Notification.Name("switchToWorkoutTab")
    static let switchToStatsTab = Notification.Name("switchToStatsTab")
    static let switchToHistoryTab = Notification.Name("switchToHistoryTab")
    static let workoutCompleted = Notification.Name("workoutCompleted")
}
