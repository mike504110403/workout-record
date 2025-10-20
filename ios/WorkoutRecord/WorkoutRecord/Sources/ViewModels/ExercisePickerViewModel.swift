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
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        loadMockData()
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
        
        // TODO: Save to repository
    }
    
    /// Get favorite exercises
    func getFavoriteExercises() -> [Exercise] {
        return allExercises.filter { $0.isFavorite }
    }
    
    /// Refresh data
    func refresh() {
        isLoading = true
        // TODO: Fetch from repository
        loadMockData()
        isLoading = false
    }
    
    // MARK: - Private Methods
    private func loadMockData() {
        // Load from MockData
        categories = MockData.categories
        allExercises = MockData.allExercises
        
        // Mark some exercises as favorites for demo
        let favoriteNames = ["槓鈴臥推", "深蹲", "硬舉", "引體向上", "肩推"]
        for (index, exercise) in allExercises.enumerated() {
            if favoriteNames.contains(exercise.name) {
                allExercises[index].isFavorite = true
            }
        }
    }
}

