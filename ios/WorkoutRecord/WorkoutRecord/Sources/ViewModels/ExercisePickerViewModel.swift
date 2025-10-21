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
    
    /// Search exercises by name (支持系統動作和自定義動作)
    func searchExercises(query: String) -> [Exercise] {
        guard !query.isEmpty else { return allExercises }
        
        let lowercasedQuery = query.lowercased()
        return allExercises.filter { exercise in
            // 搜尋動作名稱（中文）
            exercise.name.lowercased().contains(lowercasedQuery) ||
            // 搜尋英文名稱
            (exercise.nameEn?.lowercased().contains(lowercasedQuery) ?? false) ||
            // 搜尋舊的肌群標籤
            exercise.muscleGroups.contains { $0.lowercased().contains(lowercasedQuery) } ||
            // 搜尋新的詳細肌群
            exercise.targetMuscles.contains { muscle in
                muscle.displayName.lowercased().contains(lowercasedQuery) ||
                muscle.displayNameEn.lowercased().contains(lowercasedQuery)
            } ||
            // 搜尋主要肌群
            (exercise.primaryMuscleGroup?.displayName.lowercased().contains(lowercasedQuery) ?? false)
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
        
        print("🔄 ExercisePickerViewModel - 開始載入動作...")
        
        do {
            // ✅ 從 repository 加載系統動作
            var systemExercises = try exerciseRepo.fetchAll()
            print("   - 系統動作: \(systemExercises.count) 個")
            
            // ✅ 加載自定義動作
            let customExercises = CustomExerciseStorage.shared.loadCustomExercises()
            print("   - 自定義動作: \(customExercises.count) 個")
            
            // ✅ 合併系統動作和自定義動作
            allExercises = systemExercises + customExercises
            
            // 提取並去重 category
            let categoryIds = Set(allExercises.map { $0.categoryId })
            categories = MockData.categories.filter { categoryIds.contains($0.id) }
            
            print("✅ 總共載入 \(allExercises.count) 個動作")
            print("✅ 載入 \(categories.count) 個分類")
            
            // 調試：列出前 5 個動作
            for (index, exercise) in allExercises.prefix(5).enumerated() {
                print("   動作 \(index + 1): \(exercise.name) (\(exercise.isSystem ? "系統" : "自定義"))")
            }
        } catch {
            errorMessage = "載入失敗: \(error.localizedDescription)"
            print("❌ 載入動作失敗: \(error)")
            allExercises = []
            categories = []
        }
        
        isLoading = false
    }
}
