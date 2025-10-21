import Foundation
import Combine

@MainActor
class HistoryViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var workouts: [WorkoutSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let repository = WorkoutRepository()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadWorkouts()
    }
    
    // MARK: - Public Methods
    
    func loadWorkouts() {
        isLoading = true
        errorMessage = nil
        
        do {
            let allWorkouts = try repository.fetchAll()
            workouts = allWorkouts.map { convertToSummary($0) }
            print("✅ 載入 \(workouts.count) 筆訓練記錄")
        } catch {
            errorMessage = "載入失敗: \(error.localizedDescription)"
            print("❌ 載入訓練歷史失敗: \(error)")
            workouts = []
        }
        
        isLoading = false
    }
    
    func refresh() {
        loadWorkouts()
    }
    
    func deleteWorkout(_ workout: WorkoutSummary) {
        do {
            try repository.delete(id: workout.id)
            loadWorkouts()
        } catch {
            errorMessage = "刪除失敗: \(error.localizedDescription)"
            print("❌ 刪除訓練記錄失敗: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func convertToSummary(_ workout: Workout) -> WorkoutSummary {
        return WorkoutSummary(
            id: workout.id,
            date: workout.startedAt,
            duration: workout.duration ?? 0,
            totalVolume: workout.totalVolume,
            totalSets: workout.totalSets,
            exercisesCount: workout.totalExercises
        )
    }
}

