import Foundation

/// 自定義動作本地存儲服務
/// 使用 UserDefaults 存儲用戶自定義的訓練動作
class CustomExerciseStorage {
    static let shared = CustomExerciseStorage()
    
    private let userDefaults = UserDefaults.standard
    private let customExercisesKey = "customExercises"
    private let exerciseFavoritesKey = "exerciseFavorites"
    private let exerciseHistoryKey = "exerciseHistory"
    
    private init() {}
    
    // MARK: - Custom Exercises CRUD
    
    /// 保存所有自定義動作
    func saveCustomExercises(_ exercises: [Exercise]) {
        if let encoded = try? JSONEncoder().encode(exercises) {
            userDefaults.set(encoded, forKey: customExercisesKey)
        }
    }
    
    /// 讀取所有自定義動作
    func loadCustomExercises() -> [Exercise] {
        guard let data = userDefaults.data(forKey: customExercisesKey),
              let exercises = try? JSONDecoder().decode([Exercise].self, from: data) else {
            return []
        }
        return exercises
    }
    
    /// 新增自定義動作
    func addCustomExercise(_ exercise: Exercise) {
        var exercises = loadCustomExercises()
        exercises.append(exercise)
        saveCustomExercises(exercises)
    }
    
    /// 更新自定義動作
    func updateCustomExercise(_ exercise: Exercise) {
        var exercises = loadCustomExercises()
        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
            exercises[index] = exercise
            saveCustomExercises(exercises)
        }
    }
    
    /// 刪除自定義動作
    func deleteCustomExercise(id: UUID) {
        var exercises = loadCustomExercises()
        exercises.removeAll { $0.id == id }
        saveCustomExercises(exercises)
    }
    
    /// 取得單一自定義動作
    func getCustomExercise(id: UUID) -> Exercise? {
        return loadCustomExercises().first { $0.id == id }
    }
    
    // MARK: - Favorites
    
    /// 保存收藏的動作 ID
    func saveFavorites(_ ids: [UUID]) {
        let idStrings = ids.map { $0.uuidString }
        userDefaults.set(idStrings, forKey: exerciseFavoritesKey)
    }
    
    /// 讀取收藏的動作 ID
    func loadFavorites() -> [UUID] {
        guard let idStrings = userDefaults.stringArray(forKey: exerciseFavoritesKey) else {
            return []
        }
        return idStrings.compactMap { UUID(uuidString: $0) }
    }
    
    /// 切換收藏狀態
    func toggleFavorite(_ exerciseId: UUID) {
        var favorites = loadFavorites()
        if favorites.contains(exerciseId) {
            favorites.removeAll { $0 == exerciseId }
        } else {
            favorites.append(exerciseId)
        }
        saveFavorites(favorites)
    }
    
    /// 檢查是否為收藏
    func isFavorite(_ exerciseId: UUID) -> Bool {
        return loadFavorites().contains(exerciseId)
    }
    
    // MARK: - Recently Used
    
    /// 保存最近使用的動作 ID
    func saveRecentlyUsed(_ ids: [UUID]) {
        let idStrings = ids.map { $0.uuidString }
        userDefaults.set(idStrings, forKey: exerciseHistoryKey)
    }
    
    /// 讀取最近使用的動作 ID
    func loadRecentlyUsed() -> [UUID] {
        guard let idStrings = userDefaults.stringArray(forKey: exerciseHistoryKey) else {
            return []
        }
        return idStrings.compactMap { UUID(uuidString: $0) }
    }
    
    /// 添加到最近使用（限制最多 20 個）
    func addToRecentlyUsed(_ exerciseId: UUID) {
        var recentIds = loadRecentlyUsed()
        // 移除舊的相同項目
        recentIds.removeAll { $0 == exerciseId }
        // 添加到最前面
        recentIds.insert(exerciseId, at: 0)
        // 限制數量
        if recentIds.count > 20 {
            recentIds = Array(recentIds.prefix(20))
        }
        saveRecentlyUsed(recentIds)
    }
    
    // MARK: - Utility
    
    /// 清除所有自定義數據
    func clearAll() {
        userDefaults.removeObject(forKey: customExercisesKey)
        userDefaults.removeObject(forKey: exerciseFavoritesKey)
        userDefaults.removeObject(forKey: exerciseHistoryKey)
    }
    
    /// 匯出自定義動作為 JSON
    func exportToJSON() -> Data? {
        let exercises = loadCustomExercises()
        return try? JSONEncoder().encode(exercises)
    }
    
    /// 從 JSON 匯入自定義動作
    func importFromJSON(_ data: Data) throws {
        let exercises = try JSONDecoder().decode([Exercise].self, from: data)
        saveCustomExercises(exercises)
    }
}

