import Foundation
import Combine

@MainActor
class ExercisePickerViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var categories: [ExerciseCategory] = []
    @Published var allExercises: [Exercise] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let exerciseRepo = ExerciseRepository()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadData()
    }
    
    // MARK: - Public Methods
    
    /// Get exercises for a specific category
    func exercises(for category: ExerciseCategory) -> [Exercise] {
        return allExercises.filter { $0.categoryId == category.id }
    }
    
    /// Search exercises by name
    func searchExercises(query: String) -> [Exercise] {
        guard !query.isEmpty else { return allExercises }
        
        let lowercasedQuery = query.lowercased()
        return allExercises.filter { exercise in
            exercise.name.lowercased().contains(lowercasedQuery) ||
            (exercise.nameEn?.lowercased().contains(lowercasedQuery) ?? false) ||
            exercise.muscleGroups.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }
    
    /// Toggle favorite status
    func toggleFavorite(for exercise: Exercise) {
        guard let index = allExercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        allExercises[index].isFavorite.toggle()
        
        // TODO: 保存到 UserDefaults 或其他持久化存儲
    }
    
    /// Get favorite exercises
    func getFavoriteExercises() -> [Exercise] {
        return allExercises.filter { $0.isFavorite }
    }
    
    /// Refresh data
    func refresh() {
        loadData()
    }
    
    // MARK: - Private Methods
    private func loadData() {
        isLoading = true
        errorMessage = nil
        
        do {
            // ✅ 從 repository 加載數據
            allExercises = try exerciseRepo.fetchAll()
            
            // 提取並去重 category（因為沒有單獨的 category repository）
            let categoryIds = Set(allExercises.map { $0.categoryId })
            categories = MockData.categories.filter { categoryIds.contains($0.id) }
            
            print("✅ 載入 \(allExercises.count) 個動作")
        } catch {
            errorMessage = "載入失敗: \(error.localizedDescription)"
            print("❌ 載入動作失敗: \(error)")
            allExercises = []
            categories = []
        }
        
        isLoading = false
    }
}
