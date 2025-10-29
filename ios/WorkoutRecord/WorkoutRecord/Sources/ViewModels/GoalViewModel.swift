import Foundation
import Combine

@MainActor
class GoalViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var weeklyWorkoutGoal: Int = 3
    @Published var targetWeight: String = ""
    @Published var chestVolumeGoal: String = ""
    @Published var backVolumeGoal: String = ""
    @Published var legsVolumeGoal: String = ""
    @Published var shouldersVolumeGoal: String = ""
    @Published var armsVolumeGoal: String = ""
    @Published var coreVolumeGoal: String = ""
    @Published var restDayReminder: Bool = false
    @Published var isSaving: Bool = false
    @Published var errorMessage: String?
    @Published var showSuccessMessage: Bool = false
    
    // MARK: - Private Properties
    private let repository = UserGoalRepository()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadGoals()
    }
    
    // MARK: - Public Methods
    
    func loadGoals() {
        do {
            let userId = DataMigrationService.getCurrentUserId()
            if let userGoal = try repository.fetchByUser(userId) {
                weeklyWorkoutGoal = userGoal.weeklyWorkoutGoal
                targetWeight = userGoal.targetWeight != nil ? String(format: "%.1f", userGoal.targetWeight!) : ""
                chestVolumeGoal = userGoal.volumeGoals.chest != nil ? String(format: "%.0f", userGoal.volumeGoals.chest!) : ""
                backVolumeGoal = userGoal.volumeGoals.back != nil ? String(format: "%.0f", userGoal.volumeGoals.back!) : ""
                legsVolumeGoal = userGoal.volumeGoals.legs != nil ? String(format: "%.0f", userGoal.volumeGoals.legs!) : ""
                shouldersVolumeGoal = userGoal.volumeGoals.shoulders != nil ? String(format: "%.0f", userGoal.volumeGoals.shoulders!) : ""
                armsVolumeGoal = userGoal.volumeGoals.arms != nil ? String(format: "%.0f", userGoal.volumeGoals.arms!) : ""
                coreVolumeGoal = userGoal.volumeGoals.core != nil ? String(format: "%.0f", userGoal.volumeGoals.core!) : ""
                restDayReminder = userGoal.restDayReminder
                
                print("✅ 載入目標成功")
            }
        } catch {
            errorMessage = "載入失敗: \(error.localizedDescription)"
            print("❌ 載入目標失敗: \(error)")
        }
    }
    
    func saveGoals() {
        isSaving = true
        errorMessage = nil
        showSuccessMessage = false
        
        do {
            let userId = DataMigrationService.getCurrentUserId()
            
            let volumeGoals = VolumeGoals(
                chest: Double(chestVolumeGoal),
                back: Double(backVolumeGoal),
                legs: Double(legsVolumeGoal),
                shoulders: Double(shouldersVolumeGoal),
                arms: Double(armsVolumeGoal),
                core: Double(coreVolumeGoal)
            )
            
            let userGoal = UserGoal(
                userId: userId,
                weeklyWorkoutGoal: weeklyWorkoutGoal,
                targetWeight: Double(targetWeight),
                volumeGoals: volumeGoals,
                restDayReminder: restDayReminder
            )
            
            _ = try repository.createOrUpdate(userGoal: userGoal)
            
            showSuccessMessage = true
            print("✅ 目標保存成功")
            
            // 發送通知，通知其他頁面更新
            NotificationCenter.default.post(name: .goalsUpdated, object: nil)
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
            print("❌ 保存目標失敗: \(error)")
        }
        
        isSaving = false
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let goalsUpdated = Notification.Name("goalsUpdated")
}

