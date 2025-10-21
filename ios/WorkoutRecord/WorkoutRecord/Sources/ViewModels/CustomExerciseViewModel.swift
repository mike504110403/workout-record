import Foundation
import Combine

@MainActor
class CustomExerciseViewModel: ObservableObject {
    @Published var customExercises: [Exercise] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let storage = CustomExerciseStorage.shared
    
    init() {
        loadExercises()
    }
    
    // MARK: - Load
    
    func loadExercises() {
        customExercises = storage.loadCustomExercises()
    }
    
    // MARK: - Create
    
    func createExercise(
        name: String,
        type: Exercise.ExerciseType,
        categoryId: UUID,
        targetMuscles: [DetailedMuscleGroup] = [],
        primaryMuscleGroup: Exercise.PrimaryMuscleGroup? = nil,
        movementPattern: Exercise.MovementPattern? = nil,
        description: String? = nil
    ) {
        // 從詳細肌群生成舊的 muscleGroups 字符串數組（向後兼容）
        let muscleGroups = targetMuscles.map { $0.displayName }
        
        let exercise = Exercise(
            name: name,
            categoryId: categoryId,
            type: type,
            muscleGroups: muscleGroups,
            targetMuscles: targetMuscles,
            primaryMuscleGroup: primaryMuscleGroup,
            movementPattern: movementPattern,
            description: description,
            isSystem: false,
            userId: UUID() // 當前用戶 ID（未來從認證系統獲取）
        )
        
        storage.addCustomExercise(exercise)
        loadExercises()
    }
    
    // MARK: - Update
    
    func updateExercise(_ exercise: Exercise) {
        var updatedExercise = exercise
        updatedExercise.updatedAt = Date()
        storage.updateCustomExercise(updatedExercise)
        loadExercises()
    }
    
    // MARK: - Delete
    
    func deleteExercise(id: UUID) {
        storage.deleteCustomExercise(id: id)
        loadExercises()
    }
    
    func deleteExercises(at offsets: IndexSet) {
        for index in offsets {
            let exercise = customExercises[index]
            storage.deleteCustomExercise(id: exercise.id)
        }
        loadExercises()
    }
    
    // MARK: - Validation
    
    func validateExerciseName(_ name: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "動作名稱不能為空"
        }
        if name.count < 2 {
            return "動作名稱至少需要 2 個字符"
        }
        if name.count > 50 {
            return "動作名稱不能超過 50 個字符"
        }
        // 檢查是否與已有動作重名
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if customExercises.contains(where: { $0.name == trimmedName }) {
            return "此動作名稱已存在"
        }
        return nil
    }
    
    // MARK: - Utility
    
    func clearAll() {
        storage.clearAll()
        loadExercises()
    }
    
    func exportToJSON() -> Data? {
        return storage.exportToJSON()
    }
    
    func importFromJSON(_ data: Data) {
        do {
            try storage.importFromJSON(data)
            loadExercises()
        } catch {
            errorMessage = "匯入失敗：\(error.localizedDescription)"
        }
    }
}

