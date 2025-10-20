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
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadMockTemplates()
    }
    
    // MARK: - Public Methods
    func createTemplate(name: String, description: String?, exercises: [Exercise]) {
        let template = TemplateInfo(
            id: UUID(),
            name: name,
            description: description,
            isSystem: false,
            exercises: exercises.map { exercise in
                TemplateInfo.TemplateExercise(
                    name: exercise.name,
                    suggestedSets: 4,
                    suggestedReps: 10
                )
            }
        )
        
        templates.append(template)
        
        // TODO: Save to repository
    }
    
    func editTemplate(_ template: TemplateInfo) {
        // TODO: Show edit sheet
    }
    
    func deleteTemplate(_ template: TemplateInfo) {
        templates.removeAll { $0.id == template.id }
        
        // TODO: Delete from repository
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
        isLoading = true
        // TODO: Fetch from repository
        loadMockTemplates()
        isLoading = false
    }
    
    // MARK: - Private Methods
    private func loadMockTemplates() {
        templates = [
            // System templates
            TemplateInfo(
                id: UUID(),
                name: "PPL - Push (推)",
                description: "胸、肩、三頭訓練",
                isSystem: true,
                exercises: [
                    .init(name: "槓鈴臥推", suggestedSets: 4, suggestedReps: 8),
                    .init(name: "上斜啞鈴臥推", suggestedSets: 4, suggestedReps: 10),
                    .init(name: "肩推", suggestedSets: 4, suggestedReps: 10),
                    .init(name: "側平舉", suggestedSets: 3, suggestedReps: 12),
                    .init(name: "三頭下壓", suggestedSets: 3, suggestedReps: 12)
                ]
            ),
            TemplateInfo(
                id: UUID(),
                name: "PPL - Pull (拉)",
                description: "背、二頭訓練",
                isSystem: true,
                exercises: [
                    .init(name: "硬舉", suggestedSets: 3, suggestedReps: 5),
                    .init(name: "引體向上", suggestedSets: 4, suggestedReps: 8),
                    .init(name: "槓鈴划船", suggestedSets: 4, suggestedReps: 10),
                    .init(name: "坐姿划船", suggestedSets: 3, suggestedReps: 12),
                    .init(name: "槓鈴彎舉", suggestedSets: 3, suggestedReps: 10)
                ]
            ),
            TemplateInfo(
                id: UUID(),
                name: "PPL - Legs (腿)",
                description: "腿部完整訓練",
                isSystem: true,
                exercises: [
                    .init(name: "深蹲", suggestedSets: 4, suggestedReps: 8),
                    .init(name: "羅馬尼亞硬舉", suggestedSets: 4, suggestedReps: 10),
                    .init(name: "腿推機", suggestedSets: 4, suggestedReps: 12),
                    .init(name: "腿彎舉", suggestedSets: 3, suggestedReps: 12),
                    .init(name: "提踵", suggestedSets: 4, suggestedReps: 15)
                ]
            ),
            TemplateInfo(
                id: UUID(),
                name: "上肢訓練",
                description: "上半身完整訓練",
                isSystem: true,
                exercises: [
                    .init(name: "臥推", suggestedSets: 4, suggestedReps: 8),
                    .init(name: "划船", suggestedSets: 4, suggestedReps: 10),
                    .init(name: "肩推", suggestedSets: 3, suggestedReps: 10),
                    .init(name: "二頭彎舉", suggestedSets: 3, suggestedReps: 12),
                    .init(name: "三頭下壓", suggestedSets: 3, suggestedReps: 12)
                ]
            ),
            TemplateInfo(
                id: UUID(),
                name: "全身訓練",
                description: "適合初學者的全身訓練",
                isSystem: true,
                exercises: [
                    .init(name: "深蹲", suggestedSets: 3, suggestedReps: 10),
                    .init(name: "臥推", suggestedSets: 3, suggestedReps: 10),
                    .init(name: "硬舉", suggestedSets: 3, suggestedReps: 8),
                    .init(name: "引體向上", suggestedSets: 3, suggestedReps: 8),
                    .init(name: "肩推", suggestedSets: 3, suggestedReps: 10)
                ]
            )
        ]
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let startWorkoutFromTemplate = Notification.Name("startWorkoutFromTemplate")
    static let switchToWorkoutTab = Notification.Name("switchToWorkoutTab")
    static let switchToStatsTab = Notification.Name("switchToStatsTab")
    static let switchToHistoryTab = Notification.Name("switchToHistoryTab")
}

